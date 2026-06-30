---
stepsCompleted: [1,2,3]
inputDocuments:
  - sql/customers_sample.sql
  - sql/customers_vector_rag.sql
  - _bmad-output/planning-artifacts/research/diagnosis-customers-agent-notfound-2026-06-29.md
workflowType: 'research'
lastStep: 3
research_type: 'technical'
research_topic: 'Customers AI Agent — question space & retrieval method mapping (APEX 26.1 / DB 26ai)'
research_goals: 'Enumerate every question class a business user asks about the customers table; map each to exact-filter / aggregate / vector-RAG; derive the required agent tool set; feed Phase 2 user stories and Phase 3 MLE implementation.'
user_name: 'Gia Huy'
date: '2026-06-29'
web_research_enabled: false
source_verification: true
---

# Research Report: Customers AI Agent — Question Space & Retrieval Mapping
# Báo cáo nghiên cứu: Không gian câu hỏi & ánh xạ phương pháp truy xuất cho AI Agent bảng `customers`

**Date:** 2026-06-29
**Author:** Gia Huy
**Research Type:** technical (internal schema + UX question taxonomy)

---

## Research Overview / Tổng quan

**EN —** This report enumerates the realistic space of questions a business user asks an APEX AI Assistant about the `customers` table, and maps each question *class* to the correct retrieval mechanism: **exact SQL filter**, **GROUP BY aggregate**, or **vector RAG**. It is grounded in the verified Phase-0 diagnosis showing the current 2-tool agent (RAG + aggregate) fails all exact-lookup questions and miscounts aggregates. Output feeds Phase 2 (user stories) and Phase 3 (MLE tool design).

**VI —** Báo cáo này liệt kê toàn diện không gian câu hỏi thực tế mà người dùng nghiệp vụ hỏi AI Assistant về bảng `customers`, và ánh xạ mỗi *lớp* câu hỏi sang cơ chế truy xuất đúng: **lọc SQL chính xác**, **tổng hợp GROUP BY**, hay **vector RAG**. Dựa trên chẩn đoán Phase 0 đã kiểm chứng: agent 2-tool hiện tại trượt mọi câu tra cứu chính xác và đếm sai. Output làm đầu vào cho Phase 2 (user stories) và Phase 3 (thiết kế tool MLE).

### Methodology / Phương pháp
- Phân tích schema thực (`customers_sample.sql`): 11 cột, 12 dòng mẫu VN + quốc tế.
- Suy ra taxonomy câu hỏi từ bản chất từng cột (định danh, phân loại, định lượng, thời gian, tự do).
- Đối chiếu với bằng chứng Phase 0 (5 câu test) để xác nhận lỗ hổng.
- Mỗi lớp câu hỏi gắn: phương pháp truy xuất tối ưu + tool cần có + độ phức tạp.

---

## 1. Phân loại cột theo bản chất truy vấn / Column nature classification

| Cột | Kiểu | Bản chất | Phương pháp tra cứu phù hợp |
|-----|------|----------|------------------------------|
| `customer_id` | NUMBER PK | Định danh số | Exact filter (`= id`) |
| `full_name` | VARCHAR2(120) | Định danh văn bản (có dấu) | Exact / fuzzy (`LIKE`, normalize accent) |
| `email` | VARCHAR2(160) UNIQUE | Định danh duy nhất | Exact (`=`, `LIKE` domain) |
| `phone` | VARCHAR2(40) | Định danh | Exact / `LIKE` |
| `company` | VARCHAR2(120) | Phân loại văn bản (nullable) | Exact / fuzzy / `IS NULL` |
| `city` | VARCHAR2(80) | Phân loại địa lý (có dấu) | Exact / normalize accent / GROUP BY |
| `country` | VARCHAR2(80) | Phân loại địa lý | Exact / GROUP BY |
| `segment` | VARCHAR2(40) | Phân loại enum (Enterprise/SMB/Individual) | Exact / GROUP BY |
| `status` | VARCHAR2(20) CHECK | Phân loại enum (ACTIVE/INACTIVE/PROSPECT) | Exact / GROUP BY |
| `credit_limit` | NUMBER(12,2) | Định lượng | Range filter / ORDER BY / SUM/AVG/MIN/MAX |
| `created_at` | DATE | Thời gian | Range filter / GROUP BY thời gian |

**Nhận định cốt lõi:** 10/11 cột phục vụ **exact-filter hoặc aggregate**. Chỉ nội dung *mô tả tự do* (ghép nhiều cột thành câu, hoặc khi người dùng hỏi mơ hồ) mới cần RAG. → Với bảng có cấu trúc rõ, **RAG là phương pháp phụ, không phải chính**.

---

## 2. Taxonomy câu hỏi (8 lớp) / Question taxonomy (8 classes)

### Lớp Q1 — Exact lookup theo định danh / Exact identity lookup
Tra thuộc tính của 1 khách cụ thể theo tên/email/phone/id.
- "Email của Nguyễn Văn An là gì?" → `an.nguyen@vietsoft.vn`
- "Số điện thoại của John Smith?" · "Khách hàng id 5 là ai?"
- **Phương pháp:** Exact SQL filter (`WHERE UPPER(full_name) LIKE ...`). **RAG SAI cho lớp này** (Phase 0 câu 1 ❌).

### Lớp Q2 — Filtered list theo thuộc tính / Attribute-filtered list
Liệt kê các khách thỏa điều kiện 1 cột phân loại.
- "Những khách hàng nào ở Hà Nội?" → An, Đức, Lan
- "Liệt kê khách hàng INACTIVE." · "Khách hàng phân khúc SMB?" · "KH ở Vietnam?"
- **Phương pháp:** Exact SQL filter + `ORDER BY`. (Phase 0 câu 2 ❌ — thiếu tool).

### Lớp Q3 — Multi-condition filter / Lọc đa điều kiện
Kết hợp nhiều điều kiện AND/OR.
- "Khách Enterprise đang ACTIVE ở Việt Nam?" → An, Bình, Lan
- "KH có credit_limit > 100 triệu và là SMB?"
- **Phương pháp:** Exact SQL filter đa điều kiện (đây là nơi tool exact cần tham số linh hoạt).

### Lớp Q4 — Aggregate / Đếm & tổng hợp
Đếm, tổng, trung bình, min/max theo nhóm.
- "Có bao nhiêu khách Enterprise?" → 6 (Phase 0 câu 3 ❌ trả 4 — bug scope VN)
- "Tổng credit_limit theo quốc gia?" · "Trung bình credit_limit theo segment?" · "Đếm KH theo status."
- **Phương pháp:** GROUP BY aggregate. **Tool hiện có nhưng bị bug filter** → cần sửa.

### Lớp Q5 — Ranking / Top-N & cực trị
Sắp xếp theo cột định lượng.
- "Top 3 khách có credit_limit cao nhất?" → Lan (2 tỷ), Bình (750tr), An (500tr)
- "Khách có hạn mức thấp nhất?" · "5 khách mới nhất theo created_at?"
- **Phương pháp:** `ORDER BY ... FETCH FIRST n`. (Lưu ý: `FETCH FIRST` thường, KHÔNG `APPROX` vì không phải vector).

### Lớp Q6 — Range / Khoảng giá trị & thời gian
Lọc theo khoảng số hoặc ngày.
- "KH có credit_limit từ 100 đến 500 triệu?" · "KH tạo trong tháng này?"
- **Phương pháp:** Range filter (`BETWEEN`, so sánh DATE).

### Lớp Q7 — Semantic / Mô tả tự do (RAG hợp lệ)
Câu hỏi mô tả mơ hồ, không map thẳng 1 cột.
- "Tìm khách hàng doanh nghiệp lớn ở Việt Nam." (Phase 0 câu 4 ⚠️ 2/4 + bịa tên)
- "Khách hàng trong lĩnh vực thương mại điện tử?" (suy luận từ company: Tiki, Shopee...)
- **Phương pháp:** Vector RAG — NHƯNG cần tăng top-k, chống hallucinate, và chỉ kích hoạt khi không match được filter có cấu trúc.

### Lớp Q8 — Robustness / Biến thể ngôn ngữ & gõ
Không dấu, song ngữ, viết tắt, sai chính tả.
- "khach hang o tokyo" (Phase 0 câu 5 ❌) · "show me customers in Spain" · "kh enterprise"
- **Phương pháp:** Cross-cutting — **normalize accent/case trước khi lọc** (ứng viên MLE), system prompt song ngữ.

---

## 3. Ma trận ánh xạ Lớp → Phương pháp → Tool / Mapping matrix

| Lớp | Tên | Phương pháp | Tool cần có | Hiện trạng |
|-----|-----|-------------|-------------|-----------|
| Q1 | Exact lookup | SQL `WHERE` exact/LIKE | `lookup_customer_exact` 🆕 | ❌ thiếu |
| Q2 | Filtered list | SQL `WHERE` + ORDER | `lookup_customer_exact` (đa năng) 🆕 | ❌ thiếu |
| Q3 | Multi-condition | SQL `WHERE` AND/OR | `lookup_customer_exact` (tham số động) 🆕 | ❌ thiếu |
| Q4 | Aggregate | GROUP BY | `query_customer_metrics` 🔧 sửa bug | ⚠️ sai số |
| Q5 | Ranking Top-N | ORDER BY + FETCH | `rank_customers` 🆕 (hoặc gộp metrics) | ❌ thiếu |
| Q6 | Range | BETWEEN/DATE | `lookup_customer_exact` (range params) 🆕 | ❌ thiếu |
| Q7 | Semantic | Vector RAG | `search_customers_semantic` 🔧 tăng top-k | ⚠️ yếu |
| Q8 | Robustness | Normalize (MLE) + prompt | lớp tiền xử lý dùng chung (MLE) 🆕 | ❌ thiếu |

**Legend:** 🆕 mới · 🔧 sửa · ✅ giữ

---

## 4. Đề xuất tool set (chốt ở Phase 3) / Proposed tool set

1. **`lookup_customer_exact`** 🆕 — phủ Q1, Q2, Q3, Q6. Tham số động: `name`, `email`, `city`, `country`, `segment`, `status`, `company`, `credit_min`, `credit_max`. Trả danh sách khách khớp. Đây là tool vá lỗ hổng lớn nhất.
2. **`query_customer_metrics`** 🔧 — phủ Q4. Sửa bug scope (nghi `WHERE country='Vietnam'` hardcode). Hỗ trợ COUNT/SUM/AVG/MIN/MAX + GROUP BY theo cột bất kỳ.
3. **`rank_customers`** 🆕 (tùy chọn, có thể gộp vào metrics) — phủ Q5. ORDER BY cột định lượng + FETCH FIRST n.
4. **`search_customers_semantic`** 🔧 — phủ Q7. Tăng top-k, kèm guard chống bịa tên (trả nguyên `full_name` từ JOIN, không để model tự ghép).
5. **Lớp normalize dùng chung (MLE)** 🆕 — phủ Q8. Hàm JS trong DB chuẩn hoá bỏ dấu/lowercase tên & city trước khi so khớp; định dạng phản hồi song ngữ.

---

## 5. Vai trò MLE (định hướng Phase 3) / MLE role

**Dùng MLE nơi thực sự lợi (string/logic glue), giữ SQL cho set-based:**
- ✅ **Hợp MLE:** normalize accent tiếng Việt ("ha noi" ↔ "Hà Nội"), parse/validate tham số tool, build điều kiện WHERE động an toàn, format JSON/markdown phản hồi song ngữ, chống SQL injection ở tầng tool.
- ❌ **KHÔNG dùng MLE thay SQL:** `vector_distance`, `GROUP BY`, `ORDER BY ... FETCH` — set-based SQL nhanh hơn; MLE không tăng tốc các phép này.
- Lý do: MLE (GraalVM JS trong DB 26ai) mạnh ở xử lý chuỗi/JSON in-database, tránh round-trip; nhưng engine SQL vẫn tối ưu nhất cho truy vấn tập hợp.

---

## 6. Bug đếm Enterprise (Phase 0 H4) / Aggregate count bug
- Quan sát: "Đếm Enterprise" → 4, đúng phải 6.
- Phân tích số: Enterprise toàn bộ = 6; Enterprise + `country='Vietnam'` = **4** (An, Bình, Hoa, Lan). → **Nghi tool hardcode `WHERE country='Vietnam'`** hoặc system prompt ép filter VN.
- **Cần:** dán SQL định nghĩa tool `query_customer_metrics` để xác nhận & vá ở Phase 3.

---

## 7. Findings & Next steps / Kết luận & bước kế

**Findings:**
1. Bảng có cấu trúc rõ → **exact-filter + aggregate là chủ đạo (Q1–Q6)**, RAG chỉ phụ (Q7).
2. Lỗ hổng lớn nhất = **không có tool exact-lookup** → vá bằng `lookup_customer_exact` đa năng.
3. Tool aggregate có bug scope → cần sửa, không cần viết lại.
4. RAG cần tăng top-k + chống hallucinate; chỉ dùng cho mô tả tự do.
5. Robustness (không dấu/song ngữ) = lớp tiền xử lý dùng chung → **đúng đất dùng MLE**.

**Next (Phase 2):** chuyển 8 lớp câu hỏi thành **epics + user stories** có acceptance criteria, bảng truy vết (lớp → story → tool). **Phase 3:** thiết kế chi tiết 5 tool (SQL + MLE) + system prompt song ngữ có dấu.

---

## Citations / Nguồn
- `sql/customers_sample.sql` — schema & 12 dòng dữ liệu mẫu (verified).
- `sql/customers_vector_rag.sql` — pipeline embedding + HNSW index hiện tại.
- `_bmad-output/.../diagnosis-customers-agent-notfound-2026-06-29.md` — bằng chứng Phase 0 (5 câu test).
- Đáp án kỳ vọng tính trực tiếp từ dữ liệu mẫu (không suy đoán).
