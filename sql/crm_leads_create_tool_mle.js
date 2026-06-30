/* ============================================================================
 * crm_leads_create_tool_mle.js
 * TOOL 6 (WRITE) — create_lead — BẢN JAVASCRIPT / Oracle MLE
 * Tương đương crm_leads_create_tool.sql (PL/SQL), nhưng cho APEX AI Assistant
 * tool type = JavaScript (chạy trên Multilingual Engine, DB 23ai/26ai).
 *
 * CẤU HÌNH APEX: Shared Components > AI Agents > <agent> > Tools > Add Tool
 *   Name: create_lead | Execution Point: On Demand | Type: JavaScript
 *   >>> BẬT "Requires Confirmation" (human-in-the-loop) — bắt buộc cho write-tool.
 *   Parameters (Data Type / Required):
 *     p_name REQUIRED, p_company, p_phone, p_email, p_source, p_note (VARCHAR2)
 *
 * KHÁC BIỆT SO VỚI BẢN PL/SQL:
 *   1) Tham số model truyền vào đọc qua  this.data.<tên_tham_số>  (KHÔNG dùng :bind).
 *   2) Chạy SQL qua driver MLE  mle-js-oracledb  (defaultConnection), bind theo OBJECT.
 *   3) Trả kết quả về model bằng GIÁ TRỊ RETURN của hàm (chuỗi) — thay cho
 *      apex_ai.set_tool_result (API đó dành cho PL/SQL).
 *
 * !!! CHỈNH TRƯỚC KHI DÙNG:
 *   * <CRM_LEADS_SEQ>: thay bằng tên SEQUENCE PK thật của CRM_LEADS.
 *   * empId: map this user (APP_USER) -> emp_id của bạn; tạm để null.
 *   * Tập cột INSERT: bỏ/thêm cho khớp NOT NULL constraint thực tế của bảng.
 *
 * !!! KIỂM CHỨNG THEO PHIÊN BẢN APEX:
 *   * Cách APEX truyền tham số (this.data.*) và cách nhận giá trị return của JS
 *     tool — xác nhận trên đúng bản APEX 26.1 của bạn (UI có ô test tool).
 *   * Đảm bảo MLE + module mle-js-oracledb khả dụng trong schema (GRANT EXECUTE
 *     ON JAVASCRIPT, quyền apex_ai).
 * ==========================================================================*/

/* >>> DÁN TỪ ĐÂY VÀO Ô CODE CỦA JAVASCRIPT TOOL TRONG APEX <<< */

const oracledb = require("mle-js-oracledb");
const conn = oracledb.defaultConnection();

// --- Đọc tham số model trích xuất (APEX JS tool: this.data) ---
const d       = (typeof this !== "undefined" && this.data) ? this.data : {};
const name    = (d.p_name || "").trim();
const company = d.p_company || null;
const phone   = d.p_phone   || null;
const email   = d.p_email   || null;
const source  = d.p_source  || null;
const note    = d.p_note    || null;
const empId   = null;            // chốt: không map APP_USER -> để NULL

try {
  // 0) Bắt buộc có tên ------------------------------------------------------
  if (!name) {
    return "Chưa đủ thông tin: thiếu tên lead. Hãy hỏi lại người dùng tên khách hàng tiềm năng.";
  }

  // 1) CHỐNG TRÙNG theo SĐT (chỉ-số) hoặc email (lower) ---------------------
  const dup = conn.execute(
    `SELECT cle_code FROM CRM_LEADS
      WHERE ( :phone IS NOT NULL
              AND ( REGEXP_REPLACE(phone,'[^0-9]','')         = REGEXP_REPLACE(:phone,'[^0-9]','')
                 OR REGEXP_REPLACE(contact_phone,'[^0-9]','') = REGEXP_REPLACE(:phone,'[^0-9]','') ) )
         OR ( :email IS NOT NULL AND LOWER(email) = LOWER(:email) )
      FETCH FIRST 1 ROWS ONLY`,
    { phone: phone, email: email });

  if (dup.rows && dup.rows.length > 0) {
    return `Lead đã tồn tại với mã ${dup.rows[0][0]} (trùng SĐT/email). KHÔNG tạo mới. `
         + `Báo người dùng dùng mã này để tra cứu.`;
  }

  // 2) Sinh khoá: cle_id (sequence) + cle_code = LEAD-YYYYMM-#### ------------
  const ym   = conn.execute(`SELECT TO_CHAR(SYSDATE,'YYYYMM') FROM dual`).rows[0][0];
  const next = conn.execute(
    `SELECT COUNT(*)+1 FROM CRM_LEADS WHERE cle_code LIKE 'LEAD-'||:ym||'-%'`,
    { ym: ym }).rows[0][0];
  const code  = `LEAD-${ym}-${String(next).padStart(4, "0")}`;
  const cleId = conn.execute(`SELECT <CRM_LEADS_SEQ>.NEXTVAL FROM dual`).rows[0][0];

  // profile_text cho embedding (chỉ trường cốt lõi có)
  const profile = (`Khách hàng tiềm năng: ${name}. Công ty: ${company || "không rõ"}. `
                +  `Nguồn: ${source || "không rõ"}. Ghi chú: ${note || "không có"}.`).substring(0, 4000);

  // 3) INSERT CRM_LEADS (chỉnh cột cho khớp NOT NULL của bảng) ---------------
  conn.execute(
    `INSERT INTO CRM_LEADS (cle_id, cle_code, cle_name, customer, phone, email,
                            source, introduce_note, status, temperature, emp_id,
                            last_activity_date)
     VALUES (:cleId, :code, :name, :company, :phone, :email,
             :source, :note, 'NEW', 'WARM', :empId, SYSDATE)`,
    { cleId: cleId, code: code, name: name, company: company, phone: phone,
      email: email, source: source, note: note, empId: empId });

  // 4) XẾP HÀNG embedding (embedding=NULL) — KHÔNG gọi apex_ai ở đây.
  //    Lý do: gọi bge-m3 inline làm nạp model thứ 2 lên CPU, tranh tài nguyên với
  //    qwen3-erp -> vòng chat thứ 2 vượt 180s -> ORA-29276 transfer timeout.
  //    Job nền (crm_leads_embed_backfill) sẽ sinh embedding sau, ngoài luồng chat.
  conn.execute(
    `INSERT INTO crm_lead_embeddings
       (emb_id, cle_id, status, temperature, emp_id, profile_text, embedding)
     VALUES (crm_lead_emb_seq.NEXTVAL, :cleId, 'NEW', 'WARM', :empId, :profile, NULL)`,
    { cleId: cleId, empId: empId, profile: profile });

  // 5) COMMIT + trả kết quả cho model --------------------------------------
  conn.commit();
  return `Đã tạo lead ${code} cho "${name}". Báo người dùng mã lead này.`;

} catch (e) {
  conn.rollback();
  return `Lỗi khi tạo lead: ${e.message}. KHÔNG báo là đã tạo thành công.`;
}

/* >>> ĐẾN ĐÂY <<< */

/* ----------------------------------------------------------------------------
 * GHI CHÚ MLE:
 *  - mle-js-oracledb: conn.execute(sql, binds) trả object có .rows (mảng-của-mảng
 *    theo mặc định -> dùng rows[0][0]). Bind theo OBJECT {tên: giá_trị}.
 *  - conn.commit() / conn.rollback() có sẵn trên defaultConnection.
 *  - apex_ai.get_vector_embeddings được gọi NGAY TRONG câu SQL INSERT (giữ phần
 *    embedding ở SQL, JS chỉ điều phối) — đơn giản và nhất quán với bản PL/SQL.
 *  - An toàn injection: chỉ bind, KHÔNG nối chuỗi giá trị model vào SQL.
 *
 * KHI NÀO CHỌN JS (MLE) THAY PL/SQL:
 *  - Cần xử lý chuỗi/logic phức tạp kiểu JS (chuẩn hoá, parse) trước khi ghi.
 *  - Đội đã chuẩn JavaScript/MLE. Còn lại, bản PL/SQL gọn hơn cho tác vụ DML thuần.
 * --------------------------------------------------------------------------*/
