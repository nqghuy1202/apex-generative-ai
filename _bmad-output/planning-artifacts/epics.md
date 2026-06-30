---
stepsCompleted: [1,2,3]
inputDocuments:
  - _bmad-output/planning-artifacts/research/technical-customers-agent-question-space-research-2026-06-29.md
  - _bmad-output/planning-artifacts/research/diagnosis-customers-agent-notfound-2026-06-29.md
  - sql/customers_sample.sql
  - sql/customers_vector_rag.sql
---

# apex-ai — Customers AI Agent — Epic Breakdown
# apex-ai — Phân rã Epic & Story cho AI Agent bảng `customers`

## Overview / Tổng quan

**EN —** Decomposes the Phase-1 research (8 question classes Q1–Q8) into user-value epics and implementable stories for the APEX 26.1 / DB 26ai AI Assistant over the `customers` table. Each story names the required tool and has Given/When/Then acceptance criteria. A traceability table links every question class → story → tool.

**VI —** Phân rã research Phase 1 (8 lớp câu hỏi Q1–Q8) thành các epic theo giá trị người dùng và story có thể triển khai cho AI Assistant trên bảng `customers` (APEX 26.1 / DB 26ai). Mỗi story nêu rõ tool cần dùng và có tiêu chí chấp nhận Given/When/Then. Bảng truy vết nối mọi lớp câu hỏi → story → tool.

---

## Requirements Inventory / Danh mục yêu cầu

### Functional Requirements (FRs)

- **FR1 — Exact attribute lookup:** Agent trả thuộc tính (email, phone, company, segment, status, credit_limit…) của một khách hàng được nêu đích danh theo tên/email/id. *(Q1)*
- **FR2 — Single-attribute filtered list:** Agent liệt kê các khách thỏa 1 điều kiện phân loại (city, country, segment, status, company). *(Q2)*
- **FR3 — Multi-condition filter:** Agent liệt kê khách thỏa nhiều điều kiện kết hợp AND/OR. *(Q3)*
- **FR4 — Range filter:** Agent lọc theo khoảng số/ngày (credit_limit, created_at). *(Q6)*
- **FR5 — Aggregate metrics:** Agent trả COUNT/SUM/AVG/MIN/MAX, GROUP BY theo cột bất kỳ, **tổng không bị giới hạn phạm vi ngầm** (vá bug VN). *(Q4)*
- **FR6 — Ranking / Top-N:** Agent trả Top-N hoặc cực trị theo cột định lượng. *(Q5)*
- **FR7 — Semantic discovery:** Agent trả câu hỏi mô tả tự do qua vector RAG, đủ top-k, **không bịa tên** (lấy nguyên `full_name` từ JOIN). *(Q7)*
- **FR8 — Multilingual robustness & routing:** Agent xử lý tiếng Việt có/không dấu, song ngữ EN/VI, và **định tuyến đúng tool thay vì từ chối**. *(Q8)*

### Non-Functional Requirements (NFRs)

- **NFR1 — Performance:** Truy vấn exact/aggregate/ranking dùng **SQL set-based**; MLE chỉ cho xử lý chuỗi/glue. KHÔNG dùng MLE thay `vector_distance` / `GROUP BY` / `FETCH`.
- **NFR2 — Aggregate correctness:** Tổng hợp **không gắn filter ngầm** (vd `country='Vietnam'`) trừ khi người dùng yêu cầu.
- **NFR3 — No hallucination:** Tên/định danh trả về **nguyên văn từ kết quả SQL**, model không tự ghép/cắt.
- **NFR4 — Security:** WHERE động qua **bind variables / tham số hoá**; MLE không nối chuỗi SQL thô (chống injection).
- **NFR5 — Project conventions:** PK bằng **SEQUENCE + .NEXTVAL**; system prompt **tiếng Việt CÓ dấu**, song ngữ.

### Additional Requirements (kỹ thuật)

- Tool định nghĩa trong APEX AI Assistant; SQL/MLE tác giả ở repo này, **chạy trên server Linux** (hand lệnh, không tự chạy).
- Dữ liệu nguồn: bảng `customers` (12 dòng mẫu) + `customer_embeddings` (HNSW, bge-m3 1024d, COSINE).
- Đồng bộ embedding khi `customers` đổi (chạy lại BƯỚC 2+3 của `customers_vector_rag.sql`).

---

## FR Coverage Map / Bản đồ phủ yêu cầu

| FR | Question class | Epic | Story | Tool |
|----|----------------|------|-------|------|
| FR1 | Q1 Exact lookup | E1 | 1.2 | `lookup_customer_exact` |
| FR2 | Q2 Filtered list | E1 | 1.3 | `lookup_customer_exact` |
| FR3 | Q3 Multi-condition | E1 | 1.4 | `lookup_customer_exact` |
| FR4 | Q6 Range | E1 | 1.5 | `lookup_customer_exact` |
| FR5 | Q4 Aggregate | E2 | 2.1 | `query_customer_metrics` (fix) |
| FR6 | Q5 Ranking | E2 | 2.2 | `rank_customers` |
| FR7 | Q7 Semantic | E3 | 3.1 | `search_customers_semantic` (harden) |
| FR8 | Q8 Robustness | E1/E4 | 1.1, 4.1, 4.2 | MLE normalize + system prompt |

---

## Epic List / Danh sách Epic

1. **Epic 1 — Exact Lookup & Filtering** *(Tra cứu & lọc chính xác)* — vá lỗ hổng lớn nhất; phủ FR1–FR4, FR8(normalize). Standalone, mở đường cho mọi epic sau.
2. **Epic 2 — Metrics & Ranking** *(Thống kê & xếp hạng)* — phủ FR5, FR6; sửa bug đếm.
3. **Epic 3 — Semantic Discovery Hardening** *(Tìm kiếm ngữ nghĩa)* — phủ FR7; tăng top-k, chống bịa tên.
4. **Epic 4 — Multilingual UX & Routing** *(Đa ngữ & định tuyến)* — phủ FR8; system prompt song ngữ có dấu, guard định tuyến.

---

## Epic 1: Exact Lookup & Filtering / Tra cứu & lọc chính xác

**Goal:** Người dùng tra cứu chính xác thông tin khách hàng theo định danh, thuộc tính, đa điều kiện và khoảng giá trị — không còn câu trả lời "không tìm thấy" cho dữ liệu tồn tại. Đây là epic vá nguyên nhân chính (H2) từ chẩn đoán Phase 0.

### Story 1.1: MLE accent/case normalization foundation

As a người dùng, I want gõ tên/thành phố **có hoặc không dấu** vẫn ra đúng, So that tôi không bị "không tìm thấy" chỉ vì gõ "ha noi".

**Acceptance Criteria:**
- **Given** một MLE JS module chuẩn hoá chuỗi (bỏ dấu tiếng Việt + lowercase + trim), **When** nhận `"Hà Nội"`, `"ha noi"`, `"HA NOI"`, **Then** cả ba cho cùng khoá so khớp `"ha noi"`.
- **Given** module được expose cho SQL (call spec), **When** gọi trong WHERE, **Then** so khớp không phân biệt dấu/hoa-thường.
- **And** module thuần xử lý chuỗi, **không** chứa truy vấn set-based (NFR1).

### Story 1.2: Exact attribute lookup by identity (FR1, Q1)

As a người dùng, I want hỏi "email/điện thoại/công ty của [tên]?", So that tôi lấy đúng thuộc tính của một khách cụ thể.

**Acceptance Criteria:**
- **Given** tool `lookup_customer_exact` với tham số `name`, **When** hỏi "Email của Nguyễn Văn An?", **Then** trả `an.nguyen@vietsoft.vn`.
- **Given** tên gõ không dấu ("nguyen van an"), **When** tra cứu, **Then** vẫn khớp nhờ normalize (Story 1.1).
- **And** khớp dùng bind variable (NFR4); tên trả nguyên văn từ SQL (NFR3).
- **And** nếu không khớp ai, trả thông báo rõ "không có khách tên X" thay vì guard chung.

### Story 1.3: Single-attribute filtered list (FR2, Q2)

As a người dùng, I want "liệt kê khách ở [city]/[country]/[segment]/[status]", So that tôi xem nhóm khách theo một tiêu chí.

**Acceptance Criteria:**
- **Given** `lookup_customer_exact` với tham số `city`, **When** hỏi "Khách hàng nào ở Hà Nội?", **Then** trả đúng An, Đức, Lan (3 người).
- **Given** tham số `status='INACTIVE'`, **When** hỏi, **Then** trả Đặng Thị Hoa.
- **And** kết quả `ORDER BY full_name`; số lượng khớp dữ liệu thật.

### Story 1.4: Multi-condition filter (FR3, Q3)

As a người dùng, I want kết hợp điều kiện ("Enterprise ACTIVE ở Việt Nam"), So that tôi lọc chính xác hơn.

**Acceptance Criteria:**
- **Given** `lookup_customer_exact` nhận nhiều tham số (`segment`, `status`, `country`), **When** hỏi "Khách Enterprise ACTIVE ở Việt Nam", **Then** trả An, Bình, Lan.
- **And** các điều kiện nối bằng AND qua bind variables; tham số rỗng thì bỏ qua (không ép filter ngầm).

### Story 1.5: Range filter — value & date (FR4, Q6)

As a người dùng, I want lọc theo khoảng credit_limit/ngày tạo, So that tôi tìm khách theo ngưỡng.

**Acceptance Criteria:**
- **Given** tham số `credit_min`, `credit_max`, **When** hỏi "Khách có credit_limit từ 100 đến 500 triệu", **Then** trả đúng tập khách trong khoảng.
- **Given** tham số ngày, **When** hỏi "khách tạo trong tháng này", **Then** lọc theo `created_at` đúng khoảng.

---

## Epic 2: Metrics & Ranking / Thống kê & xếp hạng

**Goal:** Người dùng nhận số liệu tổng hợp đúng và bảng xếp hạng theo cột định lượng. Sửa bug đếm sai (H4) và bổ sung Top-N.

### Story 2.1: Correct aggregate metrics (FR5, Q4)

As a người dùng, I want đếm/tổng/trung bình đúng theo nhóm, So that báo cáo không sai số.

**Acceptance Criteria:**
- **Given** `query_customer_metrics` đã gỡ filter ngầm `country='Vietnam'`, **When** hỏi "Có bao nhiêu khách Enterprise?", **Then** trả **6** (không phải 4).
- **Given** GROUP BY động, **When** hỏi "Tổng credit_limit theo quốc gia", **Then** trả đúng tổng từng quốc gia.
- **And** hỗ trợ COUNT/SUM/AVG/MIN/MAX; chỉ thêm filter khi người dùng nêu rõ (NFR2).

### Story 2.2: Ranking / Top-N & extremes (FR6, Q5)

As a người dùng, I want "Top N khách theo credit_limit", So that tôi thấy khách giá trị nhất.

**Acceptance Criteria:**
- **Given** `rank_customers` với `order_by=credit_limit`, `n=3`, **When** hỏi "Top 3 khách credit cao nhất", **Then** trả Lan (2 tỷ), Bình (750tr), An (500tr).
- **And** dùng `ORDER BY ... FETCH FIRST n ROWS ONLY` (KHÔNG `APPROX` — không phải vector).

---

## Epic 3: Semantic Discovery Hardening / Tìm kiếm ngữ nghĩa

**Goal:** Câu hỏi mô tả tự do trả kết quả đủ và đúng, không bịa tên.

### Story 3.1: Hardened semantic RAG (FR7, Q7)

As a người dùng, I want hỏi mô tả tự do ("doanh nghiệp lớn ở VN", "lĩnh vực thương mại điện tử"), So that tôi tìm khách không cần biết tên chính xác.

**Acceptance Criteria:**
- **Given** `search_customers_semantic` tăng top-k phù hợp (vd 5), **When** hỏi "doanh nghiệp lớn ở Việt Nam", **Then** trả đủ nhóm Enterprise VN (An, Bình, Hoa, Lan), không cắt còn 2.
- **And** `full_name` lấy nguyên từ JOIN `customers` (NFR3 — không còn "Nguyễn Văn A" cụt).
- **And** chỉ kích hoạt RAG khi câu hỏi không map được sang exact/aggregate (định tuyến ở Epic 4).

---

## Epic 4: Multilingual UX & Routing / Đa ngữ & định tuyến

**Goal:** Agent chọn đúng tool, trả lời song ngữ có dấu, không từ chối nhầm.

### Story 4.1: Tool routing guard (FR8, Q8)

As a người dùng, I want agent gọi đúng tool thay vì trả "chỉ hỗ trợ câu hỏi về dữ liệu KH", So that câu hợp lệ luôn được phục vụ.

**Acceptance Criteria:**
- **Given** system prompt liệt kê rõ 4 tool + khi nào dùng, **When** hỏi "Email của Nguyễn Văn An?", **Then** model gọi `lookup_customer_exact` (không trả guard).
- **And** câu không dấu "khach hang o tokyo" → gọi `lookup_customer_exact(city='tokyo')` → trả Hiroshi Tanaka.

### Story 4.2: Bilingual response with diacritics (FR8, NFR5)

As a người dùng, I want phản hồi song ngữ VI có dấu + EN, So that dễ đọc và đúng quy ước dự án.

**Acceptance Criteria:**
- **Given** system prompt tiếng Việt **CÓ dấu**, **When** agent trả lời, **Then** phần VI có dấu đầy đủ, kèm phần EN.
- **And** định dạng phản hồi (markdown/bảng) có thể do lớp MLE format đảm nhiệm (NFR1 — glue, không phải truy vấn).

---

## Traceability Matrix / Ma trận truy vết (Question class → Story → Tool)

| Question class | Ví dụ | Story | Tool | Phương pháp |
|----------------|-------|-------|------|-------------|
| Q1 Exact lookup | "Email của An?" | 1.2 | `lookup_customer_exact` | SQL exact/LIKE + normalize |
| Q2 Filtered list | "KH ở Hà Nội" | 1.3 | `lookup_customer_exact` | SQL WHERE + ORDER |
| Q3 Multi-condition | "Enterprise ACTIVE VN" | 1.4 | `lookup_customer_exact` | SQL AND/OR |
| Q6 Range | "credit 100–500tr" | 1.5 | `lookup_customer_exact` | SQL BETWEEN/DATE |
| Q4 Aggregate | "đếm Enterprise" | 2.1 | `query_customer_metrics` 🔧 | GROUP BY |
| Q5 Ranking | "Top 3 credit" | 2.2 | `rank_customers` | ORDER BY + FETCH |
| Q7 Semantic | "DN lớn ở VN" | 3.1 | `search_customers_semantic` 🔧 | vector RAG |
| Q8 Robustness | "khach hang o tokyo" | 1.1, 4.1, 4.2 | MLE normalize + prompt | normalize + routing |

**Coverage check:** 8/8 lớp câu hỏi đã có story + tool. 5/5 thành phần tool set Phase 1 được phân bổ. ✅
