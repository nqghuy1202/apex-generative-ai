---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments: ['technical-crm-leads-latency-numa-round2-research-2026-06-30.md', 'technical-crm-leads-latency-optimization-research-2026-06-30.md']
workflowType: 'research'
lastStep: 6
research_type: 'technical'
research_topic: 'CRM_LEADS AI Assistant latency (round 3) — cắt LLM call-2, num_batch prefill, model size'
research_goals: 'Giảm câu-dùng-tool từ ~1m7s (SAU §0-OPT) xuống <30s, CHỈ bằng software/config/kiến trúc, giữ nguyên phần cứng Xeon E5-2680 v2 (no AVX2).'
user_name: 'Gia Huy'
date: '2026-07-01'
web_research_enabled: true
source_verification: true
---

# Research Report (Round 3): Cắt lượt LLM thứ 2 — đòn bẩy latency còn lại

**Date:** 2026-07-01 · **Author:** Gia Huy · **Type:** technical
**Tiếp nối:** round 1 (`...latency-optimization...`) + round 2 (`...latency-numa-round2...`)

---

## 0. TL;DR (đọc cái này trước)

> **Baseline hiện tại = ~1m7s cho câu-dùng-tool, ĐÃ áp §0-OPT.** Ràng buộc round 3:
> KHÔNG đổi phần cứng, mục tiêu <30s.

Round 2 đã chứng minh: latency ≈ **prefill lượt-1 + prefill lượt-2**, và **lượt-2
LUÔN cache-miss** vì APEX chèn marker ngẫu nhiên `UNTRUSTED-DATA-<hex>`. §0-OPT đã nén
prompt hết mức mà vẫn 1m7s → **nén thêm không còn dư địa đáng kể**. Vậy đòn bẩy phải
đổi từ "nén token" sang "cắt bớt công việc".

**Kết luận round 3 — xếp theo tác động:**

| # | Đòn bẩy | Bản chất | Kỳ vọng | Công sức | Rủi ro |
|---|---------|----------|---------|----------|--------|
| **1** | **CẮT lượt-2 LLM** (hard-exit trong `APEX_AI.GENERATE/CHAT`) | Kiến trúc | **~1m7s → ~20–35s** (xóa hẳn ~35–71s prefill lượt-2 không cache được) | Trung bình–cao | Trung bình |
| **2** | **Tăng `num_batch` 512→1024/2048** | Config Ollama | prefill nhanh **~20–40%** trên CPU (còn dư 37GB RAM) | Rất thấp | Thấp |
| **3** | **Đảm bảo lượt-1 CACHE HIT thật** (prefix tĩnh + keep_alive -1 + num_parallel 1) | Config | lượt-1 warm ~1s thay vì ~18–30s | Thấp | Thấp |
| **4** | **Giảm SỐ tool trên agent** (6 → 3–4, hoặc tách agent) | Kiến trúc | prefill cả 2 lượt giảm tỉ lệ với token schema | Trung bình | Thấp |
| **5** | **`num_predict` thấp ở lượt-2** (nếu vẫn giữ 2 lượt) | Config | cắt vài giây generation | Rất thấp | Thấp |
| ❌ | ~~Hạ model xuống 1.5b~~ | — | **LOẠI**: tool-calling sụp (xem §4) | — | Cao |
| ❌ | ~~Nâng phần cứng / GPU~~ | — | **LOẠI**: ngoài phạm vi (bạn đã chốt) | — | — |

**Đòn bẩy #1 là quyết định.** #2–#5 là bồi thêm, gần như miễn phí, làm song song.

---

## 1. Vì sao "nén prompt" đã hết dư địa

Round 2 đo lượt-2 luôn `sim=0.001`, `cached n_tokens≈0` → prefill lại toàn bộ
~1700–2900 token @ ~50 tok/s = **35–71s CHỈ riêng lượt-2**. §0-OPT nén system prompt
xuống ~700 token nhưng payload lượt-2 = `system nén + 6 schema + câu hỏi + KẾT QUẢ
TOOL + marker` → vẫn ~1700+ token, và **không byte nào ở đầu ổn định** (marker đổi mỗi
request) nên cache vô dụng. Đây là lý do 1m7s vẫn còn dù đã §0-OPT.

⇒ Mỗi token cắt được ở lượt-2 chỉ tiết kiệm ~20ms; muốn giảm 30–40s thì phải **bỏ hẳn
lượt-2**, không phải nén nó.

---

## 2. ★ ĐÒN BẨY #1: Cắt lượt-2 bằng `APEX_AI` "hard exit" (PL/SQL agent)

**Phát hiện mới (APEX 26.1):** `APEX_AI.GENERATE` và `APEX_AI.CHAT` cho phép **định nghĩa
tool inline bằng PL/SQL** (kiểu `apex_ai.t_tools`, không cần Shared Component) VÀ quan
trọng nhất — **response handler có "hard exit": dừng vòng agentic TRƯỚC KHI APEX gửi kết
quả tool trở lại LLM** (nguồn: Oracle APEX blog "Build Ad-hoc AI Agents Entirely in
PL/SQL").

### 2.1 Đây chính là mảnh ghép còn thiếu

Luồng hiện tại (AI Assistant khai báo sẵn) = **2 lượt LLM**:
```
Lượt 1: system + 6 schema + câu hỏi        → LLM chọn tool + tham số   (~18–30s prefill)
  → APEX chạy SQL tool (sub-second)
Lượt 2: system + 6 schema + câu hỏi + KẾT QUẢ + marker UNTRUSTED  → LLM soạn câu trả lời
        ↑ LUÔN cache-miss vì marker ngẫu nhiên → +35–71s
```

Luồng đề xuất với **hard exit** = **1 lượt LLM**:
```
Lượt 1: system + N schema + câu hỏi        → LLM chọn tool + tham số   (~18–30s prefill, CACHE ĐƯỢC)
  → tool PL/SQL chạy SQL, TỰ ĐỊNH DẠNG kết quả thành câu trả lời tiếng Việt
  → response handler HARD-EXIT: trả chuỗi đó thẳng cho người dùng, KHÔNG gọi LLM lần 2
```

**Xóa hoàn toàn ~35–71s của lượt-2** (phần không cache được). Latency còn lại ≈ chỉ
lượt-1. Với prefix tĩnh + cache nóng (đòn bẩy #3), lượt-1 lặp lại có thể ~vài giây;
câu mới ~18–30s. ⇒ **Đạt mục tiêu <30s cho phần lớn câu hỏi.**

### 2.2 Đánh đổi (phải biết trước)

- **Mất khả năng "LLM diễn giải kết quả bằng lời".** Bù lại: các tool CRM đã trả về
  hàng có cấu trúc (mã lead, tên, status, cnt, avg_score…), nên **PL/SQL tự format**
  thành câu tiếng Việt là dễ và còn *chính xác hơn* (không bịa). Ví dụ
  `query_lead_metrics` → `'Có ' || cnt || ' khách hàng tiềm năng.'`.
- **Không còn là AI Assistant khai báo sẵn** — phải dựng 1 trang APEX gọi
  `APEX_AI.GENERATE(..., p_tools => apex_ai.t_tools(...))` với response handler hard-exit.
  Công sức trung bình–cao, nhưng dùng lại được toàn bộ SQL tool + `crm_agent_pkg` hiện có.
- **Vẫn cần lượt-1** để LLM đọc ngôn ngữ tự nhiên → chọn tool + trích tham số. Đây là
  phần LLM làm tốt và **cache được** (prefix tĩnh). Ta chỉ bỏ phần LLM làm chậm & vô ích
  (đọc lại kết quả tool đã có cấu trúc).

### 2.3 Biến thể (khi muốn giữ giọng văn LLM cho vài câu)

Có thể **hard-exit CÓ ĐIỀU KIỆN**: câu tra cứu/đếm/xếp hạng (kết quả có cấu trúc) →
hard-exit, trả PL/SQL-format (nhanh). Chỉ câu cần tóm tắt tự do mới cho chạy lượt-2.
Như vậy các câu phổ biến ("có bao nhiêu lead…", "top N…") đi đường nhanh, số ít câu
"mô tả giúp tôi…" mới chịu 2 lượt.

---

## 3. ĐÒN BẨY #2: `num_batch` — tăng tốc prefill lượt-1 (gần như miễn phí)

`num_batch` (mặc định **512**, kế thừa từ llama.cpp) quyết định **bao nhiêu token được
xử lý song song trong pha prefill**. Prefill trên CPU là **compute-bound (matmul)** —
batch lớn hơn tận dụng SIMD/cache tốt hơn. Báo cáo thực nghiệm: **512→1024 tăng
throughput ~60%** (ví dụ đó có VRAM, nhưng nguyên lý prefill áp dụng cho CPU).

- Server B còn **~37GB RAM trống** → thừa sức tăng batch (batch lớn chỉ tốn thêm bộ nhớ
  tạm, không phải VRAM). Đây là đòn bẩy **chưa từng thử** trong round 1/2.
- Cách làm: thêm `PARAMETER num_batch 1024` (thử tiếp 2048) vào `Modelfile.qwen3-erp`,
  `ollama create qwen3-erp -f Modelfile.qwen3-erp`, đo `prompt eval ... tok/s` trong
  `journalctl -u ollama -f`. Giữ giá trị cho tok/s prefill cao nhất.
- ⚠️ ĐỪNG hạ `num_batch` xuống <32 — dưới ngưỡng đó llama.cpp **tắt kernel prefill tối
  ưu**, prefill còn chậm hơn.

Lưu ý: prefill của ta ~1700–2900 token (không phải "chat prompt ngắn"), đúng vùng mà
batch lớn có tác dụng rõ.

---

## 4. Vì sao KHÔNG hạ model xuống 1.5b (loại đòn bẩy)

Hạ 3b→1.5b sẽ ~giảm nửa FLOPs prefill (hấp dẫn về tốc độ) **nhưng tool-calling sụp**:
- Benchmark tool-use: Qwen2.5 **1.5B base = 3.4%** độ chính xác chọn hàm, JSON hợp lệ
  73%; **3B base = 6.1%**, JSON hợp lệ 100%. Sau fine-tune GRPO: 1.5B lên 26.6% còn
  **3B đạt 71.1%**. Khoảng cách rất lớn ở đúng năng lực ta cần (chọn đúng 1 trong 6 tool
  + trích tham số).
- Model <7B "emit malformed tool calls past trivial tasks" — chấp nhận cho phân loại,
  không cho nhiều bước. `qwen2.5:3b-instruct` là mức tối thiểu an toàn cho 6-tool.

⇒ Giữ 3b. Nếu 3b thỉnh thoảng chọn sai tool, hướng đúng là **giảm số tool/agent** (đòn
bẩy #4) chứ không phải đổi kích thước model. Tốc độ lấy từ #1 (cắt lượt-2) + #2
(num_batch), không phải từ model nhỏ hơn.

> Speculative decoding: **không xét** — chỉ tăng tốc *generation*, không tăng tốc
> *prefill* (nút thắt của ta), lại cần thêm draft model tranh CPU/RAM.

---

## 5. ĐÒN BẨY #3–#5 (bồi thêm, làm song song)

**#3 — Lượt-1 cache HIT thật.** Sau khi cắt lượt-2, lượt-1 là tất cả → phải cache tối
đa. Prefix (system + schema) **tĩnh tuyệt đối, không timestamp/user/session ở đầu**;
`OLLAMA_KEEP_ALIVE=-1`, `OLLAMA_NUM_PARALLEL=1`, `OLLAMA_MAX_LOADED_MODELS=2`. Kiểm:
hỏi cùng câu 2 lần → lượt 2 `cached n_tokens ≈ task.n_tokens`, `prompt eval < 1s`.

**#4 — Giảm số tool / tách agent.** Prefill lượt-1 = system + **N schema** + câu hỏi.
6 tool → 3–4 tool (ví dụ tách agent "Tra cứu" 4 read-tool và agent "Ghi" create_lead)
cắt token schema tỉ lệ thuận → prefill nhanh hơn mỗi lần, và mỗi agent có prefix riêng
ổn định → cache tốt hơn. Kết hợp #1: mỗi agent = 1 `APEX_AI.GENERATE` PL/SQL riêng.

**#5 — `num_predict` thấp.** Nếu (biến thể §2.3) còn giữ lượt-2 cho vài câu, đặt
`num_predict` vừa đủ (128–256) để không sinh lê thê; câu trả lời CRM ngắn.

---

## 6. Trần thực tế sau round 3

| Kịch bản | Ước tính | Có đạt <30s? |
|----------|----------|--------------|
| Câu-dùng-tool, cache lượt-1 NÓNG, hard-exit | prefill ~1s + generation tool-pick ~2–4s | ✅ **~3–6s** |
| Câu-dùng-tool MỚI (cache lạnh), hard-exit + num_batch | prefill ~900–1700 tok, batch lớn → ~12–22s | ✅ **~15–25s** |
| Câu-dùng-tool nếu VẪN giữ 2 lượt (chỉ +num_batch) | 1m7s × (1 - ~0.3) | ⚠️ **~45s** (thường KHÔNG đạt) |
| Câu không dùng tool | 1 lượt, cache nóng | ✅ ~3s |

**Chốt:** mục tiêu <30s **đạt được** nhưng **bắt buộc phải làm đòn bẩy #1 (cắt lượt-2)**.
Chỉ tinh chỉnh Ollama (#2–#5) mà giữ kiến trúc 2-lượt thì trần vẫn ~45s — không đủ.
<10s không phải mục tiêu round này và chỉ khả thi ở luồng cache-nóng.

---

## 7. Playbook triển khai (thứ tự đo được, KHÔNG sửa production khi chưa duyệt)

> Lệnh Ollama chạy trên **server B (Linux)**. Trang PL/SQL dựng trong APEX Builder.
> Đo lại sau MỖI bước bằng `journalctl -u ollama -f` (`prompt eval ms/tok`,
> `cached n_tokens`, số **lượt** LLM/câu) hoặc `tcpdump port 11434` để đếm lượt.

1. **Nhanh trước (config, phút):** thêm `PARAMETER num_batch 1024` + `num_thread 16` +
   `num_ctx 4096` vào `Modelfile.qwen3-erp`; ENV `OLLAMA_KEEP_ALIVE=-1`,
   `OLLAMA_NUM_PARALLEL=1`. Rebuild, đo prefill tok/s (baseline vs 1024 vs 2048).
2. **Xác nhận cache lượt-1:** hỏi 1 câu 2 lần, xác nhận lượt 2 `cached n_tokens` cao.
3. **PoC đòn bẩy #1:** dựng 1 trang APEX gọi `APEX_AI.GENERATE` với **1 tool inline**
   (`query_lead_metrics`) + **response handler hard-exit** tự format kết quả. Đo: chỉ
   còn **1 lượt** LLM (tcpdump), latency "có bao nhiêu khách hàng tiềm năng?".
4. **So sánh:** ghi lại 1m7s (2 lượt) vs PoC (1 lượt) cho đúng câu đó.
5. **Nếu đạt:** mở rộng sang đủ 6 tool trong `t_tools`, tái dùng `crm_agent_pkg`; cân
   nhắc tách 2 agent (#4). Chuyển "Show AI Assistant" → nút mở trang PL/SQL này.
6. **Song song:** sửa bug `query_lead_metrics` khi `p_group_by=owner` (TODO từ round 2).

---

## 8. Câu hỏi mở / rủi ro cần kiểm khi làm

- Response handler hard-exit trả **chuỗi thô** cho người dùng — cần format tiếng Việt
  gọn trong PL/SQL cho từng loại tool (đã có Data Description làm khung nội dung).
- Trang `APEX_AI.GENERATE` PL/SQL không có sẵn UI chat của AI Assistant → phải tự dựng
  vùng hội thoại (hoặc dùng lại region chat + process PL/SQL). Cần xác nhận trong Builder.
- Kiểm marker `UNTRUSTED-DATA` có xuất hiện ở **lượt-1** không (đáng lẽ không, vì chưa có
  tool result). Nếu lượt-1 sạch marker → cache lượt-1 chắc chắn hit được.

---

## Sources

- [Oracle APEX 26.1: Build Ad-hoc AI Agents Entirely in PL/SQL — `APEX_AI.GENERATE/CHAT`, inline `t_tools`, response-handler hard exit dừng vòng agentic trước khi gửi kết quả về LLM](https://blogs.oracle.com/apex/build-ad-hoc-ai-agents-entirely-in-pl-sql)
- [Move from Insights to Action with AI Agents in Oracle APEX — APEX điều phối vòng agentic: chuẩn bị context, gọi tool, đưa kết quả về model rồi soạn câu trả lời (2 lượt)](https://blogs.oracle.com/apex/ai-agents-in-oracle-apex)
- [Announcing Oracle APEX 26.1 General Availability](https://blogs.oracle.com/apex/announcing-oracle-apex-261)
- [Oracle APEX 26.1 New Features (docs) — APEX_AI enhancements](https://docs.oracle.com/en/database/oracle/apex/26.1/htmrn/new-features.html)
- [RFC: Speed up prefill up to 2x by increasing ubatch size for prompt processing (llama.cpp Discussion #23262)](https://github.com/ggml-org/llama.cpp/discussions/23262)
- [Ollama Performance Optimization — num_batch mặc định 512, 512→1024 tăng throughput ~60%](https://eastondev.com/blog/en/posts/ai/20260410-ollama-performance-optimization/)
- [Ollama Issue #1800 — num_batch phải ≥32 nếu không mất kernel prefill tối ưu](https://github.com/ollama/ollama/issues/1800)
- [Best Settings for llama.cpp — batch size (-b) tăng prefill tok/s cho prompt dài](https://inferencerig.com/performance/best-settings-for-llama-cpp-speed-vs-quality-optimization-guide/)
- [Advancing SLM Tool-Use with RL — Qwen2.5 1.5B vs 3B tool-calling accuracy (3.4%/73% vs 6.1%/100%; GRPO 26.6% vs 71.1%)](https://arxiv.org/pdf/2509.04518)
- [Best Local Models for Tool Calling 2026 — model <7B emit malformed tool calls past trivial tasks](https://www.promptquorum.com/power-local-llm/best-local-models-tool-calling-2026)
