# Chẩn đoán: AI Agent trả lời "không tìm thấy" trên bảng `customers`
# Diagnosis: APEX AI Agent returns "not found" for customer questions

- **Ngày / Date:** 2026-06-29
- **Phase:** 0 — Diagnostic (BMad workflow, sequential)
- **Trạng thái / Status:** ✅ Đã có bằng chứng — kết luận H2 (thiếu tool) + tool aggregate sai số
- **Triệu chứng / Symptom:** Hỏi thông tin khách hàng → agent trả lời `VI: Tôi không tìm thấy thông tin này trong dữ liệu khách hàng.`
- **Stack:** APEX 26.1 / DB 26ai; generation model `qwen3-erp` (FROM `qwen2.5:3b-instruct`) CPU-only trên server B; embed `apex-embed` (Ollama `bge-m3:latest`, dim 1024, COSINE).
- **Tool hiện có:** `search_customers_semantic` (vector RAG), `query_customer_metrics` (GROUP BY aggregate).

---

## 1. Giả thuyết cần phân biệt / Competing hypotheses

| # | Giả thuyết | Dấu hiệu xác nhận | Dấu hiệu loại trừ |
|---|-----------|-------------------|-------------------|
| H1 | **Model định tuyến sai / không gọi tool** (qwen3-erp 3b chọn nhầm hoặc trả lời thẳng không gọi tool) | `journalctl` cho thấy `content` có text "không tìm thấy" mà **không** có `tool_calls`; hoặc gọi sai tool | Log cho thấy tool_calls đúng nhưng SQL trả 0 dòng |
| H2 | **Thiếu loại tool** (câu hỏi exact-lookup như "email của Nguyễn Văn An?" bị ép qua RAG ngữ nghĩa → sai/không khớp) | Tool gọi là `search_customers_semantic` cho câu hỏi đáng lẽ là filter chính xác; distance cao | Câu hỏi đã có tool phù hợp vẫn trượt |
| H3 | **Retrieval RAG kém / dữ liệu lỗi** (embedding NULL, hoặc top-k không chứa khách cần tìm) | SQL kiểm tra có `embedding IS NULL`; hoặc top-3 distance đều > ~0.6 cho câu hỏi rõ ràng | Embedding đủ, distance thấp, vẫn báo not found |
| H4 | **Threshold/format trong tool khiến kết quả bị loại** (tool lọc distance hoặc trả JSON sai khiến model coi như rỗng) | Tool trả dòng nhưng agent vẫn nói not found | Tool trả rỗng thật |

---

## 2. Bộ câu hỏi thử nghiệm / Test question battery

Chạy lần lượt **trong APEX AI Assistant**, ghi lại câu trả lời của agent (OK / "không tìm thấy" / sai).

### A. Exact-lookup (kỳ vọng: filter chính xác)
1. `Email của Nguyễn Văn An là gì?`
2. `Số điện thoại của khách hàng John Smith?`
3. `Những khách hàng nào ở Hà Nội?`
4. `Liệt kê khách hàng có status INACTIVE.`
5. `Khách hàng nào thuộc công ty FPT Software?`
6. `What is the credit limit of Vietcombank's contact?`

### B. Aggregate/đếm (kỳ vọng: GROUP BY)
7. `Có bao nhiêu khách hàng phân khúc Enterprise?`
8. `Tổng credit_limit theo từng quốc gia?`
9. `Đếm số khách hàng theo status.`
10. `How many customers are PROSPECT?`

### C. Semantic (kỳ vọng: vector RAG)
11. `Khách hàng doanh nghiệp lớn ở Việt Nam?`
12. `Tìm khách hàng làm trong lĩnh vực thương mại điện tử.`

### D. Song ngữ / không dấu (kỳ vọng: vẫn hiểu)
13. `khach hang o tokyo` (không dấu)
14. `Show me customers in Spain.`

> **Cách ghi kết quả:** điền vào bảng cuối tài liệu (mục 5).

---

## 3. Lệnh thu thập bằng chứng trên server / Evidence-gathering commands

### 3.1 Theo dõi model trong lúc hỏi (server B — Linux/bash)
Mở 1 terminal tail log, rồi sang APEX hỏi từng câu mục 2:
```bash
journalctl -u ollama -f --no-hostname
```
Với **mỗi** câu hỏi, ghi lại từ log:
- Có khối `tool_calls` không? Tên tool nào? Tham số (`search_text` / filter) là gì?
- `done_reason` = `stop` hay `length`?
- `content` có rỗng (`""`) hay chứa text trả lời thẳng?

> Nếu thấy `tool_calls` **trống** và `content` chứa "không tìm thấy" → **H1**.
> Nếu `tool_calls` gọi `search_customers_semantic` cho câu hỏi nhóm A → **H2**.

### 3.2 Kiểm tra dữ liệu & embedding (DB — SQL Workshop / SQLcl)
```sql
-- (a) Có khách hàng nào chưa được embed không? (H3)
SELECT (SELECT COUNT(*) FROM customers)            AS customers_total,
       (SELECT COUNT(*) FROM customer_embeddings)  AS emb_rows,
       (SELECT COUNT(*) FROM customer_embeddings
         WHERE embedding IS NULL)                   AS emb_null;

-- (b) Vector index còn sống không?
SELECT index_name, index_type, status
FROM   user_indexes
WHERE  index_name = 'CUST_EMB_HNSW_IDX';

-- (c) Thử retrieval thô cho 1 câu hỏi exact-lookup (H2/H3):
--     nếu khách cần tìm KHÔNG nằm trong top-3 hoặc distance cao -> RAG không hợp cho lookup chính xác.
SELECT c.full_name, c.email, c.city,
       ROUND(VECTOR_DISTANCE(
               e.embedding,
               apex_ai.get_vector_embeddings(
                 p_value => 'Email của Nguyễn Văn An',
                 p_service_static_id => 'apex-embed'),
               COSINE), 4) AS dist
FROM   customer_embeddings e
JOIN   customers c ON c.customer_id = e.customer_id
ORDER  BY dist
FETCH  APPROX FIRST 3 ROWS ONLY;

-- (d) Xác nhận dữ liệu exact tồn tại (loại trừ "dữ liệu không có thật"):
SELECT customer_id, full_name, email, city, status
FROM   customers
WHERE  UPPER(full_name) LIKE UPPER('%An%')
   OR  UPPER(city)      = UPPER('Hà Nội');
```

---

## 4. Cây quyết định / Decision tree

```
Câu hỏi nhóm A trượt?
├─ Log: không có tool_calls ........................ H1 (định tuyến) -> sửa system prompt + buộc tool-use
├─ Log: gọi search_customers_semantic .............. H2 (thiếu tool exact) -> thêm lookup_customer_exact (Phase 3)
└─ Log: gọi đúng nhưng SQL 0 dòng / agent vẫn báo not found
        ├─ emb_null > 0 hoặc index UNUSABLE ........ H3 (dữ liệu) -> re-embed (BƯỚC 2+3 customers_vector_rag.sql)
        └─ tool trả dòng nhưng agent bỏ ............ H4 (threshold/format tool) -> sửa tool output/threshold
```

---

## 5. Kết quả quan sát (điền sau khi chạy) / Observed results

| # | Câu hỏi | Đáp án đúng | Agent trả lời | Đánh giá | Giả thuyết |
|---|---------|-------------|---------------|----------|-----------|
| 1 | Email Nguyễn Văn An | `an.nguyen@vietsoft.vn` | "Tôi chỉ hỗ trợ các câu hỏi về dữ liệu khách hàng." (từ chối, không trả) | ❌ FAIL | **H2** — không có tool exact-lookup nên model không biết xử lý → trả guard chung |
| 2 | KH ở Hà Nội | An, Đức, Lan (3) | "Tôi không tìm thấy thông tin này..." | ❌ FAIL | **H2** — không có filter chính xác theo city; RAG không trả đúng |
| 3 | Bao nhiêu Enterprise | **6** (An, Bình, Hoa, Smith, Tanaka, Lan) | "Có **4** khách hàng" | ❌ SAI SỐ | **H4** — tool `query_customer_metrics` chạy nhưng đếm sai (thiếu/lọc nhầm) |
| 4 | DN lớn ở VN | An, Bình, Hoa, Lan (Enterprise VN) | "Có **2**": Đặng Thị Hoa + "Nguyễn Văn **A**" | ⚠️ MỘT PHẦN | RAG chạy nhưng top-k quá nhỏ (chỉ 2/4) + **bịa tên** ("Nguyễn Văn A" — cụt chữ) |
| 5 | khach hang o tokyo (không dấu) | Hiroshi Tanaka | "Tôi không tìm thấy thông tin này..." | ❌ FAIL | **H2 + H1** — không có filter city; tiếng Việt không dấu càng làm RAG lệch |

**→ Kết luận giả thuyết:**
- **H2 (THIẾU TOOL EXACT-LOOKUP) — nguyên nhân chính.** 3/5 câu (1, 2, 5) thất bại vì không có tool lọc chính xác theo cột (`full_name`, `email`, `city`, `status`...). Model bị ép qua RAG ngữ nghĩa hoặc trả guard chung.
- **H4 (TOOL AGGREGATE SAI SỐ) — lỗi thứ hai. ĐÃ XÁC ĐỊNH ROOT CAUSE (2026-06-29):** SQL gốc của `query_customer_metrics` có `GROUP BY c.country, c.segment, c.status` **bắt buộc, không tắt được**. "Đếm Enterprise" trả **4 DÒNG** (Vietnam/ACTIVE=3, Vietnam/INACTIVE=1, USA/ACTIVE=1, Japan/ACTIVE=1) thay vì 1 tổng. Model nhỏ **gộp nhầm 4 dòng nhóm thành "4 khách"** (đúng tổng `count(*)` = 6). KHÔNG phải hardcode Vietnam như giả định ban đầu. → Bản vá: `p_group_by` động/optional, `NULL` ⇒ 1 dòng tổng = 6.
- **RAG hiện tại yếu cho bảng 12 dòng:** câu 4 chỉ trả 2/4 và bịa tên → top-k nhỏ + model nhỏ hallucinate khi tổng hợp. RAG nên dành cho mô tả tự do, không phải lookup/đếm.
- **H1 (định tuyến) phụ:** câu 1 trả guard "chỉ hỗ trợ câu hỏi về dữ liệu KH" cho thấy system prompt + thiếu tool khiến model không định tuyến được; không phải lỗi định tuyến thuần.

**Hệ quả cho Phase 1–3:**
1. **Bổ sung tool exact-lookup/filter** (`lookup_customer_exact`) — ưu tiên #1, vá câu 1/2/5.
2. **Sửa & mở rộng `query_customer_metrics`** — đếm/tổng hợp đúng theo mọi cột.
3. **Chuẩn hoá input tiếng Việt không/có dấu** trước khi lọc (ứng viên dùng **MLE** — xử lý chuỗi/normalize accent).
4. **Giữ RAG** nhưng chỉ cho câu hỏi mô tả tự do; tăng top-k và chống bịa tên.
5. **Soát system prompt** để model định tuyến đúng thay vì trả guard.
