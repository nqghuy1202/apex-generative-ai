# Description tiếng Việt cho 4 tool — APEX AI Assistant (bảng `customers`)

Dán **Tool Description** và **Parameter Description** vào đúng ô tương ứng trong
App Builder → Generative AI → AI Assistant → Tools. Viết CÓ DẤU (quy ước dự án).
Mô tả rõ "khi nào dùng" + "tham số lấy từ đâu" là yếu tố quyết định agent định tuyến đúng.

---

## 1. `lookup_customer_exact`

**Tool Description:**
> Tra cứu và liệt kê khách hàng theo thông tin chính xác. Dùng tool này khi người dùng hỏi thông tin của một khách hàng cụ thể (email, số điện thoại, công ty, hạn mức...) hoặc muốn liệt kê/lọc khách hàng theo một hay nhiều tiêu chí: tên, email, công ty, thành phố, quốc gia, phân khúc (Enterprise/SMB/Individual), trạng thái (ACTIVE/INACTIVE/PROSPECT), hoặc khoảng hạn mức tín dụng. Hiểu cả tiếng Việt có dấu lẫn không dấu (ví dụ "ha noi" = "Hà Nội"). Chỉ truyền các tham số mà người dùng nhắc tới; tham số không liên quan để trống.

**Parameter Descriptions:**
- `p_name` — Tên khách hàng cần tìm (có hoặc không dấu). Khớp gần đúng một phần. Ví dụ: "Nguyễn Văn An", "nguyen van".
- `p_email` — Địa chỉ email chính xác của khách hàng.
- `p_company` — Tên công ty (khớp một phần). Ví dụ: "FPT", "VietSoft".
- `p_city` — Thành phố. Ví dụ: "Hà Nội", "ha noi", "Tokyo".
- `p_country` — Quốc gia. Ví dụ: "Vietnam", "Japan", "USA".
- `p_segment` — Phân khúc khách hàng: Enterprise, SMB hoặc Individual.
- `p_status` — Trạng thái khách hàng: ACTIVE, INACTIVE hoặc PROSPECT.
- `p_credit_min` — Hạn mức tín dụng tối thiểu (số). Dùng khi hỏi "từ ... trở lên".
- `p_credit_max` — Hạn mức tín dụng tối đa (số). Dùng khi hỏi "dưới ...", "không quá ...".

---

## 2. `query_customer_metrics`

**Tool Description:**
> Tính số liệu tổng hợp về khách hàng: đếm số lượng, tổng/trung bình/lớn nhất/nhỏ nhất của hạn mức tín dụng. Dùng tool này khi người dùng hỏi "có bao nhiêu...", "tổng...", "trung bình...". Nếu người dùng muốn xem theo từng nhóm (theo phân khúc, trạng thái, quốc gia, thành phố, công ty) thì truyền tham số p_group_by; nếu chỉ hỏi một con số tổng thì để p_group_by trống. Có thể lọc trước bằng phân khúc, trạng thái hoặc quốc gia.

**Parameter Descriptions:**
- `p_segment` — Lọc theo phân khúc trước khi tính (Enterprise/SMB/Individual). Để trống nếu tính tất cả.
- `p_status` — Lọc theo trạng thái trước khi tính (ACTIVE/INACTIVE/PROSPECT). Để trống nếu tính tất cả.
- `p_country` — Lọc theo quốc gia trước khi tính. Để trống nếu tính tất cả.
- `p_group_by` — Cột để gom nhóm kết quả: 'segment', 'status', 'country', 'city' hoặc 'company'. **Để TRỐNG nếu người dùng chỉ muốn một con số tổng** (ví dụ "có bao nhiêu khách Enterprise").

---

## 3. `rank_customers`

**Tool Description:**
> Xếp hạng khách hàng và lấy Top-N theo một cột định lượng. Dùng tool này khi người dùng hỏi "top", "cao nhất", "thấp nhất", "nhiều nhất", "mới nhất" (ví dụ "3 khách hàng có hạn mức cao nhất", "5 khách hàng mới nhất").

**Parameter Descriptions:**
- `p_order_col` — Cột để xếp hạng: 'credit_limit' (hạn mức tín dụng) hoặc 'created_at' (ngày tạo).
- `p_dir` — Hướng sắp xếp: 'DESC' cho cao nhất/mới nhất, 'ASC' cho thấp nhất/cũ nhất.
- `p_n` — Số lượng khách hàng cần lấy (ví dụ 3, 5, 10).

---

## 4. `search_customers_semantic`

**Tool Description:**
> Tìm kiếm khách hàng theo ngữ nghĩa cho các câu hỏi MÔ TẢ MƠ HỒ không khớp trực tiếp với một cột dữ liệu cụ thể (ví dụ "khách hàng trong lĩnh vực thương mại điện tử", "các doanh nghiệp công nghệ"). KHÔNG dùng tool này khi người dùng hỏi theo tên, email, thành phố, phân khúc hay trạng thái rõ ràng — khi đó hãy dùng lookup_customer_exact. Chỉ dùng khi không thể lọc bằng tiêu chí chính xác.

**Parameter Descriptions:**
- `p_search_text` — Câu mô tả nhu cầu tìm kiếm bằng ngôn ngữ tự nhiên (tiếng Việt hoặc tiếng Anh). KHÔNG được để trống.

---

## Mẹo định tuyến (nhắc lại trong system prompt)

| Người dùng hỏi kiểu | Tool đúng |
|---------------------|-----------|
| Thông tin/danh sách theo thuộc tính rõ ràng | `lookup_customer_exact` |
| Đếm / tổng / trung bình | `query_customer_metrics` |
| Top / cao nhất / thấp nhất / mới nhất | `rank_customers` |
| Mô tả mơ hồ, không map được cột | `search_customers_semantic` |
