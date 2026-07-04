--------------------------------------------------------------------------------
-- crm_nl2sql_pkg.pks  — Phase B (2026-07-04)
-- NL->SQL hỏi-đáp trên CRM_LEADS qua uc_ai, dạng SINGLE-CALL structured-output.
--
-- Thiết kế (báo cáo technical-uc-ai-nl2sql-crm-leads-optimization-...-2026-07-04):
--   * uc_ai.generate_text(p_response_json_schema=..., KHÔNG đăng ký tool) => 1 LLM call.
--   * Model chỉ trả JSON PHẲNG ràng buộc enum {intent, filters[], group_by, metric,
--     limit}. Free-text DUY NHẤT = filters[].val (luôn BIND). Mọi định danh (cột/
--     toán tử/intent) là ENUM -> whitelist -> chống injection tận gốc.
--   * PL/SQL validate + dựng SQL tham số hoá (DBMS_SQL bind theo tên) + READ-ONLY
--     (chỉ SELECT trên CRM_LEADS) + cap dòng.
--
-- Phụ thuộc: uc_ai (đã cài schema APEX_DEV), CRM_LEADS, bodau.sql.
-- KHÔNG dùng bge-m3/vector ở path này (câu metric/list/rank thuần cấu trúc -> nhanh
--   trên CPU; không đụng bge-m3 => không tranh chấp model trên server B).
--
-- An toàn: chỉ chạy SELECT tự-dựng từ token whitelist; không EXECUTE gì từ LLM.
--   Khuyến nghị chạy package dưới schema/role chỉ có quyền SELECT trên CRM_LEADS.
--------------------------------------------------------------------------------
create or replace package crm_nl2sql_pkg
  authid definer
as

  -- Cấu hình Ollama (đặt 1 lần; mặc định trỏ server B). Có thể override trước khi gọi.
  g_base_url        varchar2(255 char) := 'http://172.25.10.38:11434/api'; -- PHẢI có /api
  g_web_credential  varchar2(255 char) := 'credentials-for-apex-ollama';
  g_model           varchar2(128 char) := 'qwen3-erp:latest';
  g_row_cap         pls_integer        := 50;   -- trần dòng trả về (an toàn + ít token)

  /*
   * ask: trả lời một câu hỏi tiếng Việt về CRM_LEADS.
   *   p_question    câu hỏi ngôn ngữ tự nhiên (VD "có bao nhiêu lead nóng nguồn Facebook?")
   *   p_debug       TRUE => kèm JSON intent + SQL đã dựng vào kết quả (để benchmark/soi)
   * Trả về: CLOB câu trả lời tiếng Việt (đã format).
   * Thực hiện ĐÚNG 1 LLM call (structured output). Ném lỗi có tiền tố 'CRM_NL2SQL:'
   *   khi JSON không hợp lệ / intent-cột ngoài whitelist.
   */
  function ask (
    p_question in clob,
    p_debug    in boolean default false
  ) return clob;

  /*
   * build_only: KHÔNG chạy SQL, chỉ trả JSON intent (từ LLM) + câu SQL sẽ dựng.
   *   Dùng cho accuracy-harness / adversarial test mà không chạm dữ liệu.
   */
  function build_only (
    p_question in clob
  ) return clob;

end crm_nl2sql_pkg;
/
