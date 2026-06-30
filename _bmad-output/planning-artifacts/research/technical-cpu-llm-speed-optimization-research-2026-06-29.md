---
title: "Optimizing CPU LLM Response Speed for APEX RAG — Technical Research"
research_type: technical
research_topic: "Speed optimization for qwen3.5 on CPU in APEX 26.1 RAG/AI Assistant"
date: 2026-06-29
author: Gia Huy (facilitated by BMad Technical Research)
stepsCompleted: [1, 2, 3]
status: complete
related: ["technical-local-llm-erp-cpu-research-2026-06-29.md"]
---

# Nghiên cứu kỹ thuật: Tối ưu TỐC ĐỘ phản hồi LLM trên CPU cho APEX RAG
# Technical Research: Optimizing CPU LLM Response Speed for APEX RAG

> **Grounding:** Số liệu tăng tốc là **ước tính tổng hợp từ nguồn công khai 2026** + suy luận từ log thực tế của hệ thống. Mục `[chưa chắc chắn]` = chưa kiểm chứng trực tiếp. Không bịa benchmark. **Số đáng tin duy nhất là đo lại trên chính máy đích sau mỗi thay đổi.**

---

## 1. Hiện trạng đo được / Measured Baseline

| Chỉ số | Giá trị (từ log 2026-06-29) |
|---|---|
| Model | `qwen3.5:latest`, 5.8 GiB, **100% CPU** (vram=0), num_ctx=4096, temp=1.0 |
| Prompt eval | ~20 tok/s → input 1200+ token tốn **~60s** |
| Generation | **~4.6 tok/s** → output 235–426 token tốn 50–91s |
| Tổng/request | **80–153 giây** (1m20s → 2m33s) |
| Embedding bge-m3 | ~0.4s/call — **KHÔNG phải nút thắt** |
| **Mục tiêu** | **5–15 giây/câu**, chỉ tối ưu phần mềm, CPU cố định |

**Hai nguồn tốn thời gian chính:** (A) sinh quá nhiều token output (thinking-mode), (B) prompt đầu vào quá dài (60s chỉ để đọc input).

---

## 2. Xếp hạng đòn bẩy tối ưu / Ranked Optimization Levers

> Sắp theo **(mức tăng tốc ước tính × độ dễ áp dụng)**.

### 🥇 Đòn bẩy #1 — TẮT THINKING MODE (tác động lớn nhất, dễ nhất)

**Vấn đề:** `qwen3.5` có chain-of-thought bật mặc định. Thinking mode **sinh nhiều hơn 2–3× số token** mỗi câu trả lời. Trong log, request sinh 426 token ở 4.6 tok/s = 91 giây — phần lớn là "suy nghĩ" vô hình.

**Cách áp dụng (chọn 1):**
- Thêm `/no_think` vào **system prompt** của AI Assistant trong APEX.
- Hoặc gửi tham số trong request: `"chat_template_kwargs": {"enable_thinking": false}`.
- Hoặc dùng bản `-instruct` thuần (không reasoning).

**Tăng tốc ước tính:** cắt **50–66% thời gian sinh output** → riêng đòn này có thể đưa 91s xuống ~30–45s. `[mức cụ thể cần đo]`
**Rủi ro:** giảm chất lượng suy luận đa bước; nhưng với Text-to-SQL/tool-calling đơn giản như 2 tool hiện tại thì **gần như không ảnh hưởng**.

### 🥈 Đòn bẩy #2 — ĐỔI MODEL NHỎ HƠN

`qwen3.5:latest` (5.8 GiB) quá nặng cho CPU. Các ứng viên:

| Model | RAM | Tốc độ CPU ước tính | Tiếng Việt | Function-calling |
|---|---|---|---|---|
| **qwen3:4b** (khuyến nghị) | ~3 GB | ~7–10 tok/s `[chưa chắc chắn]` | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ (agent-native) |
| Llama 3.2 3B | ~2 GB (⚠️ nguồn báo 11.4GB khi chạy) | ~11–12 tok/s | ⭐⭐⭐ | ⭐⭐⭐ |
| Gemma 3 4B | ~4.2 GB | ~10–11 tok/s (hiệu suất RAM tốt nhất) | ⭐⭐⭐ | ⭐⭐⭐ |

**Khuyến nghị:** **qwen3:4b** — giữ tốt nhất tiếng Việt + function-calling (quan trọng cho 2 tool SQL của anh), nhanh hơn qwen3.5 rõ rệt.
**Tăng tốc ước tính:** generation ~4.6 → ~8–10 tok/s (**~2×**).
**Rủi ro:** chất lượng nhỉnh thấp hơn qwen3.5, nhưng đủ cho tác vụ ERP.

> 💡 **Kết hợp #1 + #2** (qwen3:4b + tắt thinking) nhiều khả năng **đủ đạt mốc 5–15s** mà chưa cần các bước sau.

### 🥉 Đòn bẩy #3 — GIẢM PROMPT ĐẦU VÀO (cắt 60s "prompt eval")

Prompt đang phình tới 6303 token (tool schema + RAG context + lịch sử chat). Ở 20 tok/s, mỗi 1000 token input = ~50s.

**Cách áp dụng:**
- **Giảm RAG top-k:** `fetch approx first 5 rows only` → **`first 3 rows only`** trong tool `search_customers_semantic`. Cắt ~40% context RAG.
- **Rút gọn mô tả tool & system prompt:** mô tả ngắn gọn, bỏ ví dụ thừa trong tool schema.
- **Cắt lịch sử hội thoại:** giới hạn số lượt chat APEX gửi lại (mỗi lượt cũ làm prompt dài thêm — thấy rõ prompt_len tăng dần trong log).
- **Giảm `num_ctx`** nếu không cần 4096: vd 2048 → giảm bộ nhớ KV-cache & tăng tốc.

**Tăng tốc ước tính:** cắt 30–50% thời gian prompt eval → 60s xuống ~30s. `[cần đo]`
**Rủi ro:** top-k=3 có thể bỏ sót ngữ cảnh — kiểm tra chất lượng câu trả lời sau khi giảm.

### #4 — THAM SỐ SINH: temp thấp + giới hạn output

- `temperature 0.1` (đang 1.0) cho tác vụ tool/SQL → ổn định, ít lan man.
- Giới hạn `num_predict`/max_tokens (vd 512) để chặn câu trả lời dài lê thê.
- Ép prompt: "Trả lời ngắn gọn, đi thẳng kết quả."

**Tăng tốc:** gián tiếp giảm số token sinh. **Rủi ro:** thấp.

### #5 — THAM SỐ OLLAMA/llama.cpp TRÊN CPU

> Nguồn 2026: "đa số người chạy Ollama trên CPU đang để lãng phí 30–50% hiệu năng".

| Biến môi trường | Tác dụng |
|---|---|
| `OLLAMA_FLASH_ATTENTION=1` | Giảm KV-cache 30–50% (Ollama ≥ v0.13.5 đã bật mặc định) |
| `OLLAMA_KV_CACHE_TYPE=q8_0` | Giảm ~½ bộ nhớ KV-cache, mất chất lượng không đáng kể (chỉ hiệu lực khi flash attention bật) |
| `OLLAMA_KEEP_ALIVE=30m` | Tránh nạp lại model 5.8GB mỗi lần (cold-start rất tốn trên CPU) |
| `OLLAMA_NUM_THREADS` = số nhân vật lý | Khớp số luồng với CPU để tối đa throughput |
| `num_batch` | Tăng nhẹ để tăng tốc prompt eval (đổi lấy RAM) |

**Tăng tốc ước tính:** 10–30% tổng thể. **Rủi ro:** thấp; cần thử nghiệm `num_threads` đúng với CPU.

### #6 — QUANTIZATION Q4_K_M

Nếu model hiện tải ở mức quantization cao (Q6/Q8), hạ xuống **Q4_K_M** giảm dung lượng & tăng tốc, chất lượng giảm nhẹ. Với `qwen3:4b`, kéo thẳng bản Q4_K_M.
**Tăng tốc:** vừa phải. **Rủi ro:** giảm nhẹ độ chính xác (Q4 trên context dài có thể thấy được).

---

## 3. Lộ trình áp dụng đề xuất / Recommended Roadmap

**Vòng 1 — Quick wins (kỳ vọng đạt mốc 5–15s):**
1. Đổi sang `qwen3:4b` (Q4_K_M).
2. Tắt thinking mode (`/no_think` trong system prompt).
3. Giảm RAG top-k 5 → 3.
4. `temperature 0.1`, giới hạn output.
→ **Đo lại log.** Nếu đạt 5–15s → dừng.

**Vòng 2 — Nếu chưa đạt:**
5. Set biến môi trường Ollama (`KEEP_ALIVE`, `FLASH_ATTENTION`, `KV_CACHE_TYPE=q8_0`, `NUM_THREADS`).
6. Rút gọn tool schema + cắt lịch sử chat + giảm `num_ctx`.
→ Đo lại.

**Vòng 3 — Nếu vẫn chưa đạt:** cân nhắc model 3B (Llama 3.2 / Gemma 3) hoặc xem lại kỳ vọng so với ràng buộc CPU.

---

## 4. Cấu hình mẫu / Sample Configuration

```bash
# Vòng 1: kéo model nhỏ + đặt biến môi trường (sửa systemd: systemctl edit ollama)
ollama pull qwen3:4b

# /etc/systemd/system/ollama.service.d/override.conf
[Service]
Environment="OLLAMA_KEEP_ALIVE=30m"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_KV_CACHE_TYPE=q8_0"
# Environment="OLLAMA_NUM_THREADS=<số nhân vật lý của CPU>"
```

```text
# Modelfile cho AI Assistant ERP (tool-calling, không thinking)
FROM qwen3:4b
PARAMETER temperature 0.1
PARAMETER num_ctx 2048
PARAMETER num_predict 512
SYSTEM """/no_think
Bạn là trợ lý ERP. Trả lời ngắn gọn, đi thẳng kết quả.
Khi cần dữ liệu khách hàng, gọi đúng tool. Không bịa tên bảng/cột."""
```

```sql
-- Trong tool search_customers_semantic: giảm top-k 5 -> 3
fetch approx first 3 rows only
```

---

## 5. Rủi ro & lưu ý / Risks & Notes

- ⚠️ **Mục tiêu 5–15s là tham vọng trên CPU thuần** với input RAG dài. Quick wins vòng 1 có cơ hội cao đạt được, nhưng **chỉ log đo lại mới khẳng định**.
- ⚠️ Giảm top-k & tắt thinking đổi lấy một phần chất lượng — cần bộ câu test tiếng Việt để xác nhận độ chính xác không tụt.
- ✅ Đòn bẩy #1 và #2 **rẻ, đảo ngược dễ** — nên làm trước và đo ngay.

---

## Nguồn / Sources

- [Disabling Qwen3 think mode to improve speed — OpenWhispr Issue #512](https://github.com/OpenWhispr/openwhispr/issues/512)
- [Qwen3.5 How to Run Locally — Unsloth Docs](https://unsloth.ai/docs/models/qwen3.5)
- [It's time to turn off THINK MODE Qwen-3 — Medium (Duke Wang)](https://medium.com/@dukewillbe185/its-time-to-turn-off-the-annoying-think-mode-qwen-3-eefb7dedcadd)
- [Ollama Performance Optimization: Quantization, Batch, Memory Tuning — BetterLink](https://eastondev.com/blog/en/posts/ai/20260410-ollama-performance-optimization/)
- [Ollama Slow on CPU? Tune These Parameters (2026) — OpenClaw Sanctuary](https://openclawsanctuary.com/ollama-advanced)
- [OLLAMA_KV_CACHE_TYPE: Halve KV Cache Memory — ModelPiper](https://modelpiper.com/blog/ollama-kv-cache-quantization)
- [Local AI in 2026: Best Models for Your Hardware — AI Magicx](https://www.aimagicx.com/blog/local-ai-models-2026-qwen-mistral-llama-hardware-guide)
- [Best Small Language Models 2026 — Local AI Master](https://localaimaster.com/blog/small-language-models-guide-2026)
</content>
