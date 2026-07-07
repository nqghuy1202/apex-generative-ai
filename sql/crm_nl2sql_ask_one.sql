--------------------------------------------------------------------------------
-- crm_nl2sql_ask_one.sql — hỏi THẬT 1 câu qua crm_nl2sql_pkg.ask()
-- Chạy: SQL Workshop > SQL Scripts > Upload > Run  (hoặc SQLcl: @crm_nl2sql_ask_one.sql)
-- Yêu cầu đã cài: uc_ai (APEX_DEV), bodau.sql, CRM_LEADS, crm_nl2sql_pkg (.pks+.pkb),
--   model qwen3-erp resident trên server B (ollama ps).
--------------------------------------------------------------------------------
set serveroutput on size unlimited

-- (tùy chọn) override cấu hình nếu server B khác IP/model:
-- BEGIN
--   crm_nl2sql_pkg.g_base_url       := 'http://172.25.10.38:11434/api';
--   crm_nl2sql_pkg.g_web_credential := 'credentials-for-apex-ollama';
--   crm_nl2sql_pkg.g_model          := 'qwen3-erp:latest';
-- END;
-- /

DECLARE
  l_question CONSTANT CLOB := 'có bao nhiêu lead nóng đến từ Facebook?';
  l_answer   CLOB;
  l_t0       TIMESTAMP;
  l_secs     NUMBER;
BEGIN
  l_t0     := systimestamp;
  -- p_debug => TRUE để thấy kèm JSON intent + câu SQL đã dựng
  l_answer := crm_nl2sql_pkg.ask(p_question => l_question, p_debug => TRUE);
  l_secs   := extract(second from (systimestamp - l_t0))
            + extract(minute from (systimestamp - l_t0)) * 60;

  dbms_output.put_line('CÂU HỎI : ' || l_question);
  dbms_output.put_line('THỜI GIAN: ' || round(l_secs, 1) || 's');
  dbms_output.put_line('TRẢ LỜI  :');
  dbms_output.put_line(l_answer);
EXCEPTION
  WHEN OTHERS THEN
    dbms_output.put_line('LỖI: ' || sqlerrm);
    dbms_output.put_line(dbms_utility.format_error_backtrace);
END;
/
