--------------------------------------------------------------------------------
-- crm_leads_embed_backfill.sql
-- Job nền sinh embedding cho các lead còn THIẾU (embedding IS NULL) — tách khỏi
-- luồng chat của AI Assistant để KHÔNG làm vòng chat thứ 2 vượt 180s
-- (tránh ORA-29276 transfer timeout do bge-m3 + qwen3-erp tranh CPU).
--
-- Dùng cho: lead tạo qua create_lead (Tool 6) chèn với embedding=NULL, và mọi
-- lead mới/đổi nội dung Nhóm A chưa có vector. Chạy lặp, idempotent.
--
-- !!! CHẠY 1 LẦN để tạo job. Sau đó job tự chạy theo lịch.
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON

--------------------------------------------------------------------------------
-- 1) Procedure backfill — sinh embedding theo LÔ NHỎ (tránh giữ CPU quá lâu).
--    p_limit: số dòng xử lý mỗi lần chạy (mặc định 50). Tăng/giảm theo tải.
--------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE crm_leads_embed_backfill (p_limit IN NUMBER DEFAULT 50)
IS
  v_done PLS_INTEGER := 0;
BEGIN
  FOR e IN (SELECT emb_id, profile_text
              FROM   crm_lead_embeddings
             WHERE   embedding IS NULL
               AND   profile_text IS NOT NULL
             FETCH FIRST p_limit ROWS ONLY) LOOP
    BEGIN
      UPDATE crm_lead_embeddings
         SET embedding = apex_ai.get_vector_embeddings(
                           p_value             => e.profile_text,
                           p_service_static_id => 'apex-embed')
       WHERE emb_id = e.emb_id;
      v_done := v_done + 1;
      COMMIT;                       -- commit từng dòng: lỗi 1 dòng không mất cả lô
    EXCEPTION WHEN OTHERS THEN
      ROLLBACK;                     -- bỏ qua dòng lỗi, để lần sau thử lại
      NULL;
    END;
  END LOOP;
  dbms_output.put_line('Backfill embedding: đã xử lý ' || v_done || ' lead.');
END;
/

--------------------------------------------------------------------------------
-- 2) Job DBMS_SCHEDULER — chạy mỗi 2 phút (chỉnh interval tùy nhu cầu).
--    Xoá job cũ nếu có (idempotent) rồi tạo lại.
--------------------------------------------------------------------------------
BEGIN
  BEGIN DBMS_SCHEDULER.DROP_JOB('CRM_LEADS_EMBED_JOB', force => TRUE);
  EXCEPTION WHEN OTHERS THEN NULL; END;

  DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'CRM_LEADS_EMBED_JOB',
    job_type        => 'PLSQL_BLOCK',
    job_action      => 'BEGIN crm_leads_embed_backfill(p_limit => 50); END;',
    start_date      => SYSTIMESTAMP,
    repeat_interval => 'FREQ=MINUTELY; INTERVAL=2',
    enabled         => TRUE,
    comments        => 'Sinh embedding cho lead mới (embedding IS NULL), tách khỏi luồng chat.');
END;
/

--------------------------------------------------------------------------------
-- 3) (TÙY CHỌN) Chạy backfill NGAY 1 lần thủ công, không chờ lịch:
--------------------------------------------------------------------------------
-- BEGIN crm_leads_embed_backfill(p_limit => 200); END;
-- /

--------------------------------------------------------------------------------
-- THEO DÕI:
--   * Còn bao nhiêu lead chưa có embedding:
--       SELECT COUNT(*) FROM crm_lead_embeddings WHERE embedding IS NULL;
--   * Lịch sử chạy job:
--       SELECT log_date, status, additional_info
--       FROM   user_scheduler_job_run_details
--       WHERE  job_name = 'CRM_LEADS_EMBED_JOB' ORDER BY log_date DESC;
--   * Tắt/bật job:  EXEC DBMS_SCHEDULER.DISABLE('CRM_LEADS_EMBED_JOB');
--                   EXEC DBMS_SCHEDULER.ENABLE('CRM_LEADS_EMBED_JOB');
--------------------------------------------------------------------------------
