---
stepsCompleted: [1, 2, 3]
inputDocuments: []
workflowType: 'research'
lastStep: 3
research_type: 'technical'
research_topic: 'CRM_LEADS AI Assistant latency optimization (CPU, keep model, split agents)'
research_goals: 'Giảm độ trễ phản hồi >1 phút xuống mức chấp nhận, giữ qwen2.5:3b + bge-m3, tách agent nhỏ, rà soát toàn bộ tool + embedding'
user_name: 'Gia Huy'
date: '2026-06-30'
web_research_enabled: true
source_verification: true
---

# Research Report: Technical — Tối ưu độ trễ AI Assistant CRM_LEADS (CPU)

**Date:** 2026-06-30 · **Author:** Gia Huy · **Research Type:** technical

## Research Overview

Độ trễ hiện ~45–180s/câu. Ràng buộc đã chốt: server B **CPU mạnh nhiều core, không
GPU**; **giữ qwen2.5:3b-instruct + bge-m3**; **được tách agent nhỏ**; tối ưu cả đọc
lẫn ghi. Mục tiêu: tìm đòn bẩy độ trễ theo thứ tự tác động, có nguồn xác minh.

## 1. Chẩn đoán: tiền xử lý prompt (prefill) là nút thắt

Log Ollama: `prompt eval ~1961 tokens @ ~50 tok/s ≈ 39s`, còn sinh chữ chỉ ~3–5s.
→ **>85% độ trễ là prefill** toàn bộ prompt (system + schema 5–6 tool + câu hỏi).
Agentic loop gọi LLM **2 lần** (quyết định tool + soạn đáp án) → nhân đôi.

**Phát hiện then chốt:** log có `looking for better prompt, base f_keep=0.001,
sim=0.001` → **KV/prompt cache KHÔNG tái dùng** (độ tương đồng ~0). Mỗi request
prefill lại từ đầu. Nếu prefix ổn định byte-for-byte, prefix ~1900 token được tính
MỘT lần rồi tái dùng → prefill tụt từ ~39s xuống ~1s. Đây là đòn bẩy #1.

## 2. Đòn bẩy theo thứ tự tác động

### A. Bật & giữ PROMPT PREFIX CACHE (tác động lớn nhất, miễn phí)
- KV cache tái dùng khi **prefix giống hệt từng byte**. TUYỆT ĐỐI không để phần đầu
  prompt có yếu tố động (timestamp, tên user, id phiên) → phá cache toàn bộ phần sau.
- `OLLAMA_KEEP_ALIVE=24h` để model + cache không bị xả sau 5 phút.
- `OLLAMA_NUM_PARALLEL=1` (1 người dùng/lúc): dồn TOÀN BỘ context + compute cho 1
  request; >1 chia nhỏ slot → mỗi request ít tài nguyên + dễ evict cache.
- Kiểm chứng: hỏi 2 lần CÙNG một câu; lần 2 phải nhanh hẳn (prefill ~0). Nếu vẫn
  chậm → APEX đang gửi prefix khác nhau mỗi lần (xác minh phần đầu messages).

### B. num_thread = số core VẬT LÝ (tác động trung bình)
- Ollama nhiều bản **đặt sai num_thread trên CPU nhiều core** → chỉ chạy ~50 tok/s
  dù CPU mạnh. Đặt `PARAMETER num_thread <số core vật lý>` (không tính hyperthread).
  Đo tok/s với vài giá trị để chọn tối ưu (+10–14% trở lên).

### C. Tách AGENT NHỎ (đã chốt — giảm token mỗi vòng)
- Agent **"Tra cứu"**: lookup_lead_exact, query_lead_metrics, rank_leads,
  suggest_lead_actions, search_leads_semantic.
- Agent **"Nhập liệu"**: chỉ create_lead (+ lookup_lead_exact để kiểm tra trùng).
- Mỗi agent ít tool → schema ngắn → prefix nhỏ → prefill nhanh hơn mỗi vòng. Người
  dùng chọn assistant theo việc (tra cứu vs nhập liệu). Kết hợp với prefix cache:
  mỗi agent có prefix riêng, ổn định, cache rất tốt.

### D. KV cache q8_0 + num_ctx vừa đủ (tác động nhỏ)
- `OLLAMA_KV_CACHE_TYPE=q8_0`: ~1/2 bộ nhớ KV, mất chính xác không đáng kể → giữ
  cache + cả 2 model trong RAM dễ hơn.
- `num_ctx` để 4096 (đủ cho 6-tool sau khi compact). Không phình thêm.

### E. Giữ CẢ HAI model thường trú (chống tráo — đã xác định ở sự cố ORA-29276)
- `OLLAMA_MAX_LOADED_MODELS=2` để bge-m3 + qwen3-erp cùng nằm RAM, không nạp/đuổi
  lẫn nhau (nguyên nhân vòng chat 2 vượt 180s khi create_lead gọi embedding inline).

### F. Embedding tách khỏi luồng chat (đã làm)
- create_lead chèn `embedding=NULL`; job nền `CRM_LEADS_EMBED_JOB` sinh sau
  (`crm_leads_embed_backfill.sql`). Tool 2 (search) vẫn embed câu truy vấn 1 lần/câu
  — chấp nhận; có thể cache embedding các truy vấn lặp nếu cần.

## 3. Rà soát TOOL (SQL phía DB — KHÔNG phải nút thắt, nhưng cần đúng)

| Tool | Tối ưu |
|---|---|
| lookup_lead_exact | b-tree trên cle_code/email/tax_id; tránh mle_norm() quanh cột ở >500k |
| query_lead_metrics | index status/temperature (đã tạo); GROUP BY set-based |
| rank_leads | index score/(emp_id,score); ORDER BY CASE vô hiệu index khi không filter → giữ p_n nhỏ, khuyến khích filter |
| suggest_lead_actions | index next_action_date/last_activity_date (đã tạo) |
| search_leads_semantic | **pre-filter trước vector** (PRE_W trên HNSW); chỉ embed 1 lần/câu |
| create_lead | chèn embedding=NULL (deferred); 2 vòng LLM ~80s — chấp nhận, ưu tiên prefix cache |

> SQL tool chạy sub-second ở DB; độ trễ người dùng cảm nhận **gần như toàn bộ ở LLM
> prefill**. Vì vậy ưu tiên A→B→C, không phải tinh chỉnh SQL.

## 4. Khuyến nghị triển khai (thứ tự, đo sau mỗi bước)

1. `OLLAMA_KEEP_ALIVE=24h`, `OLLAMA_NUM_PARALLEL=1`, `OLLAMA_MAX_LOADED_MODELS=2`,
   `OLLAMA_KV_CACHE_TYPE=q8_0` → restart ollama. Đo lại câu hỏi lặp (cache hit).
2. Thêm `PARAMETER num_thread <core vật lý>` vào Modelfile → rebuild → đo tok/s.
3. Tách 2 agent (Tra cứu / Nhập liệu); mỗi agent system prompt riêng, ngắn, ổn định
   (tối ưu qua prompt-master).
4. Đảm bảo phần ĐẦU prompt mỗi agent tĩnh tuyệt đối (không timestamp/user/session).
5. Đo: prefill lần 2 của cùng câu phải ~1s; nếu không, dò phần prefix động từ APEX.

## Sources
- [Ollama FAQ — keep_alive, threads](https://docs.ollama.com/faq)
- [Optimizing Ollama Performance: Hardware, Quantization, Parallelism (Medium/Kapil Khatik)](https://medium.com/@kapildevkhatik2/optimizing-ollama-performance-on-windows-hardware-quantization-parallelism-more-fac04802288e)
- [How Ollama Handles Parallel Requests (Glukhov)](https://www.glukhov.org/post/2025/05/how-ollama-handles-parallel-requests/)
- [Ollama default num_thread incorrect on large core systems (issue #2496)](https://github.com/ollama/ollama/issues/2496)
- [Ollama CPU Optimization Guide (jameschrisa)](https://github.com/jameschrisa/Ollama_Tuning_Guide/blob/main/docs/cpu-optimization.md)
- [Prompt Caching — prefix KV reuse must be byte-identical](https://leanpub.com/read/ollama/prompt-caching)
- [Ollama Environment Variables Reference (2026)](https://modelpiper.com/blog/ollama-environment-variables)
