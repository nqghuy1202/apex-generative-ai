/* ============================================================================
 * crm_agent_create_lead_tool_mle.js
 * Code MLE (JavaScript) cho APEX AI Tool "create_lead" — GỌI PACKAGE
 * crm_agent_pkg.create_lead(... p_error OUT).
 *
 * APEX tool: Type = JavaScript | Execution Point = On Demand | Requires Confirmation = ON
 * Parameters phải khai báo (6 INPUT, KHÔNG khai p_error):
 *   p_name (REQUIRED), p_company, p_phone, p_email, p_source, p_note  (VARCHAR2)
 *
 * Điều kiện: procedure crm_agent_pkg.create_lead đã sửa đúng (return; sau thiếu tên
 * và sau khi gặp trùng; có commit; p_error=null khi thành công).
 * ==========================================================================*/

/* >>> DÁN TỪ ĐÂY VÀO Ô CODE CỦA JAVASCRIPT TOOL <<< */

const oracledb = require("mle-js-oracledb");
const conn = oracledb.defaultConnection();

// Đọc tham số tool; fallback tên HOA phòng khi APEX expose P_NAME thay vì p_name.
const d = (typeof this !== "undefined" && this.data) ? this.data : {};
const g = k => d[k] ?? d[k.toUpperCase()] ?? null;

try {
  const r = conn.execute(
    `BEGIN crm_agent_pkg.create_lead(
       p_name    => :p_name,
       p_company => :p_company,
       p_phone   => :p_phone,
       p_email   => :p_email,
       p_source  => :p_source,
       p_note    => :p_note,
       p_error   => :p_error); END;`,
    {
      p_name:    g("p_name"),
      p_company: g("p_company"),
      p_phone:   g("p_phone"),
      p_email:   g("p_email"),
      p_source:  g("p_source"),
      p_note:    g("p_note"),
      p_error:   { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 4000 }
    }
  );

  const err = r.outBinds.p_error;   // có giá trị = thiếu tên / trùng / lỗi
  if (err) {
    return err;                     // trả nguyên văn cho model
  }
  conn.commit();                    // thành công -> lưu (an toàn dù proc đã commit)
  return 'Đã tạo lead mới thành công.';

} catch (e) {
  conn.rollback();
  return 'Lỗi khi tạo lead: ' + e.message + '. KHÔNG báo là đã tạo thành công.';
}

/* >>> ĐẾN ĐÂY <<< */
