---
stepsCompleted: [1, 2, 3]
inputDocuments: []
workflowType: 'research'
lastStep: 3
research_type: 'technical'
research_topic: 'CRM_LEADS create-lead WRITE tool for APEX AI Assistant (PL/SQL action tool)'
research_goals: 'Thiết kế tool ghi (PL/SQL INSERT) cho APEX AI Assistant tạo lead mới từ ngôn ngữ tự nhiên, an toàn, có chống trùng + auto-embed, kèm system prompt + rủi ro model 3B'
user_name: 'Gia Huy'
date: '2026-06-30'
web_research_enabled: true
source_verification: true
---

# Research Report: Technical — CRM_LEADS "create_lead" WRITE Tool cho APEX AI Assistant

**Date:** 2026-06-30
**Author:** Gia Huy
**Research Type:** technical

---

## Research Overview

Mục tiêu: chuyển AI Assistant trên `CRM_LEADS` từ **chỉ-đọc** (5 read-tool hiện có)
sang có **hành động ghi** — tạo lead mới từ câu nói tự nhiên ("Tạo lead anh Minh,
công ty Thép Việt, SĐT 0901234567, nguồn hội chợ"), giống mẫu *Support Ticket* trong
video YouTube `ApErCVFoK9Q`. Khác biệt cốt lõi so với 5 tool cũ: tool này dùng
**PL/SQL** (thực thi DML phía server) thay vì SQL SELECT.

Phương pháp: nghiên cứu tài liệu chính thức APEX 26.1 + blog Oracle APEX + cộng đồng,
đối chiếu với quyết định phạm vi đã chốt cùng người dùng. Mọi cơ chế nêu dưới đây
đều có nguồn (xem mục Sources).

---

## 1. Cơ chế Tool của APEX AI Assistant (đã xác minh)

**Nơi cấu hình:** Shared Components → **AI Agents** → chọn agent → tab **Tools** →
**Add Tool**. Mỗi tool gồm:
- **Identification:** `Name` (chữ thường + gạch dưới, vd `create_lead`), `Type`,
  `Execution Point` = *On Demand* (để LLM tự gọi theo ngữ cảnh), `Description`
  (hướng dẫn model KHI NÀO gọi tool).
- **Settings → Type:** một trong `SQL Query` | **`PL/SQL`** | `Function Body` |
  `JavaScript`. Read-tool dùng SQL Query; **action/write-tool dùng PL/SQL**.
- **Parameters:** mỗi tham số có `Name`, `Data Type` ∈ {VARCHAR2, NUMBER, BOOLEAN,
  CLOB}, cờ `Required`, và `Description`. **Model đọc Description để biết điền gì.**

**Cách model → PL/SQL nhận giá trị:** tool SQL/PL/SQL tham chiếu tham số qua **bind
variable** `:P_NAME` (giống `:PERSON_ID` trong ví dụ Oracle). APEX tự gán giá trị
model trích xuất vào bind — **không nối chuỗi**, nên an toàn injection theo thiết kế
(điểm mạnh quyết định so với tự build SQL động). Ngoài tham số, bind hệ thống như
`:APP_USER` cũng dùng được trong PL/SQL.

**Trả kết quả về model:** dùng API
```plsql
apex_ai.set_tool_result(
  p_result               => '...',     -- chuỗi model đọc để soạn câu trả lời
  p_notification_message => '...',     -- (tùy chọn) toast hiển thị
  p_notification_type    => 'success'  -- success | warning | error ...
);
```
Ví dụ Oracle (escalate ticket):
```plsql
begin
  support_pkg.escalate_ticket(p_ticket_id => :TICKET_ID, p_reason => :REASON,
                              p_user_id => :APP_USER);
  apex_ai.set_tool_result(p_result => 'Ticket '||:TICKET_ID||' escalated.',
                          p_notification_message => 'Ticket escalated',
                          p_notification_type => 'success');
end;
```
Nếu không gọi `set_tool_result`, APEX trả kết quả "success" mặc định.

**Agentic loop:** LLM quyết định cần tool → APEX validate tham số → chạy PL/SQL →
kết quả quay lại model → model soạn câu trả lời cuối. (Giống loop của read-tool.)

---

## 2. An toàn cho WRITE-tool: Human-in-the-loop (BẮT BUỘC bật)

APEX 26.1 có option **"Requires Confirmation"** ở cấu hình tool: agent **TẠM DỪNG**
chờ người dùng bấm đồng ý trước khi chạy DML. Cấu hình được: tiêu đề, thông điệp,
nhãn nút Approve/Cancel. Cơ chế: APEX chờ Promise settle → loop dừng cho tới khi
người dùng phản hồi trên UI.

> **Khuyến nghị chốt:** với `create_lead` (ghi dữ liệu), **BẬT Requires Confirmation**.
> Đây là tuyến phòng thủ chính chống việc model 3B trích xuất sai rồi tạo lead rác.
> Người dùng thấy trước "Sẽ tạo lead: <tên> / <SĐT> — Đồng ý?" rồi mới INSERT.

---

## 3. Thiết kế tool `create_lead` (theo phạm vi đã chốt)

| Quyết định | Chốt |
|---|---|
| Trường trích xuất | Cốt lõi tối thiểu: tên lead/công ty, SĐT **hoặc** email, nguồn, ghi chú |
| Sinh `cle_code` | PL/SQL tự sinh `LEAD-YYYYMM-####` (model KHÔNG cần biết) |
| Embedding | Sinh ngay trong tool (INSERT CRM_LEADS → đồng bộ `crm_lead_embeddings` → `apex_ai`) |
| Chống trùng | SĐT/email đã tồn tại → KHÔNG chèn, trả mã lead cũ |
| PK | `SEQUENCE.NEXTVAL` (quy ước dự án, không IDENTITY) |
| owner/emp_id | Lấy từ APEX context (map `:APP_USER` → emp_id); fallback NULL |
| Xác nhận | Requires Confirmation = ON |

**Tham số tool (5):** `p_name` (VARCHAR2, **required**) · `p_company` (VARCHAR2) ·
`p_phone` (VARCHAR2) · `p_email` (VARCHAR2) · `p_source` (VARCHAR2) · `p_note`
(VARCHAR2). *(Cần ≥1 trong p_phone/p_email để chống trùng có ý nghĩa.)*

**Luồng PL/SQL (xem `sql/crm_leads_create_tool.sql`):**
1. **Chống trùng** — chuẩn hoá SĐT (`regexp_replace [^0-9]`) + email (`lower`);
   nếu khớp lead cũ → `set_tool_result('Lead đã tồn tại: <cle_code>...')` + RETURN,
   KHÔNG INSERT.
2. **Sinh khoá** — `cle_id := CRM_LEADS_SEQ.NEXTVAL`; `cle_code := 'LEAD-'||
   TO_CHAR(SYSDATE,'YYYYMM')||'-'||LPAD(<đếm trong tháng+1>,4,'0')`.
3. **INSERT CRM_LEADS** — bind các giá trị; `status='NEW'`, `emp_id` từ context.
4. **Đồng bộ embedding** — ghép `profile_text` (chỉ trường có), gọi
   `apex_ai.get_vector_embeddings(..., 'apex-embed')`, INSERT `crm_lead_embeddings`.
5. **COMMIT** (action-tool phải commit để dữ liệu bền vững).
6. `set_tool_result('Đã tạo lead <cle_code> cho <tên>.')` (success).
7. `EXCEPTION WHEN OTHERS` → ROLLBACK + `set_tool_result(...,'error')`.

**Lưu ý transaction:** PL/SQL block tự `COMMIT` ở cuối nhánh thành công và `ROLLBACK`
khi lỗi — không để DML treo cho request sau. Embedding sinh inline tốn ~vài giây CPU
(chấp nhận vì có bước Confirmation người dùng đã chờ sẵn).

---

## 4. Rủi ro khi cho model 3B gọi WRITE-tool + giảm thiểu

| Rủi ro | Giảm thiểu |
|---|---|
| Model trích xuất sai tên/SĐT | **Requires Confirmation** (người dùng duyệt trước) |
| Gọi nhầm `create_lead` khi chỉ hỏi tra cứu | System prompt: chỉ tạo khi câu có Ý ĐỊNH TẠO rõ ("tạo/thêm/ghi nhận lead") + có tên |
| Tạo lead rác/trùng | Chống trùng SĐT/email trong PL/SQL |
| Thiếu tên (required) | Tool/đủ thông tin → model phải HỎI LẠI, không bịa |
| Token payload phình (giờ 6 tool) | Mô tả compact; cân nhắc tách agent "ghi" riêng nếu num_ctx căng (xem gotcha truncation) |
| Injection | Bind-only; KHÔNG nối chuỗi vào SQL động |

> Cảnh báo dung lượng: thêm tool thứ 6 làm tăng schema → kết hợp với
> `num_ctx 4096` đã nâng. Nếu payload vẫn sát trần, phương án sạch nhất là tách
> **một AI Assistant "Nhập liệu" riêng** chỉ chứa `create_lead` (+ vài read-tool),
> tách khỏi assistant "Tra cứu" 5-tool — mỗi assistant payload nhỏ, model chọn đúng
> dễ hơn.

---

## 5. Khuyến nghị triển khai (thứ tự)

1. Xác nhận tên SEQUENCE PK của `CRM_LEADS` và cách map `:APP_USER` → `emp_id`.
2. Dán PL/SQL `create_lead` (`sql/crm_leads_create_tool.sql`) vào tool mới, type
   PL/SQL, khai báo 6 tham số, **bật Requires Confirmation**.
3. Bổ sung mô tả tool + quy tắc "khi nào tạo lead" vào System Prompt (tối ưu qua
   prompt-master — xem `crm_leads_agent_prompts.md`).
4. Test: "Tạo lead anh Minh công ty Thép Việt, SĐT 0901234567, nguồn hội chợ" →
   duyệt confirmation → kiểm tra Interactive Report thấy lead `LEAD-202606-####`;
   lặp lại câu đó → phải báo "đã tồn tại". Hỏi tra cứu thường → KHÔNG được tạo lead.
5. Tail `journalctl -u ollama -f`: tool-call đúng `create_lead`, `done_reason: stop`.

---

## Sources

- [APEX 26.1 — New Features (AI Agents/Tools)](https://docs.oracle.com/en/database/oracle/apex/26.1/htmrn/new-features.html)
- [Move from Insights to Action with AI Agents in Oracle APEX](https://blogs.oracle.com/apex/ai-agents-in-oracle-apex)
- [Oracle APEX 26.1: Build Ad-hoc AI Agents Entirely in PL/SQL](https://blogs.oracle.com/apex/build-ad-hoc-ai-agents-entirely-in-pl-sql)
- [Build a CRM AI Agent with Oracle APEX](https://blogs.oracle.com/apex/build-a-crm-ai-agent-with-oracle-apex)
- [How to Add an AI Agent to an Oracle APEX Application (cloudnueva)](https://blog.cloudnueva.com/adding-ai-agent-to-apex-app)
- [Build Your First AI Agent in Oracle APEX (maxapex)](https://www.maxapex.com/blogs/build-ai-agent-oracle-apex/)
- [RAG vs Tool Functions in Oracle APEX 24.2 (Medium)](https://medium.com/cloud-ai-insights/rag-vs-tool-functions-in-oracle-apex-24-2-when-to-use-which-b7a0c974490e)
- Video phân tích: https://www.youtube.com/watch?v=ApErCVFoK9Q
