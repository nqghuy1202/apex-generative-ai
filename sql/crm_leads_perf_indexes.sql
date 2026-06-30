--------------------------------------------------------------------------------
-- crm_leads_perf_indexes.sql
-- Index hỗ trợ các tool SQL CẤU TRÚC trên CRM_LEADS (>500k) — Tool 1/3/4/5.
-- Mục tiêu: tăng tốc lọc (WHERE) và xếp hạng (ORDER BY ... FETCH FIRST n).
--
-- CÁCH CHẠY: SQL Workshop > SQL Scripts > Upload > Run, hoặc SQLcl @file.
-- An toàn chạy lại: mỗi CREATE bọc trong block bỏ qua ORA-00955 (đã tồn tại).
--
-- LƯU Ý PHẠM VI:
--  * Index dưới đây phục vụ Tool 1 (lookup), Tool 3 (metrics), Tool 4 (actions),
--    Tool 5 (rank_leads). KHÔNG liên quan vector — index HNSW nằm ở
--    crm_leads_vector_rag.sql (Tool 2).
--  * Tool 5 dùng ORDER BY dạng CASE (linh hoạt) sẽ KHÔNG tận dụng được index
--    sắp xếp khi không có filter. Index score/created vẫn giúp khi:
--      - người dùng kèm filter (status/owner) -> b-tree thu nhỏ tập trước;
--      - hoặc bạn tách 1 tool top_by_score tĩnh "ORDER BY score DESC".
--  * Sau khi tạo, cân nhắc GATHER STATS để optimizer chọn đúng kế hoạch.
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON

DECLARE
  PROCEDURE mk(p_sql VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE p_sql;
    dbms_output.put_line('OK  : ' || p_sql);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE IN (-955, -1408) THEN             -- ORA-00955 tên đã dùng / ORA-01408 cột đã index
        dbms_output.put_line('SKIP: đã tồn tại — ' || p_sql);
      ELSE
        dbms_output.put_line('ERR : ' || SQLERRM || ' — ' || p_sql);
      END IF;
  END;
BEGIN
  ----------------------------------------------------------------------------
  -- Tool 5 (rank_leads) — trục xếp hạng + lọc-rồi-xếp-hạng
  ----------------------------------------------------------------------------
  mk('CREATE INDEX crm_leads_score_idx        ON CRM_LEADS (score)');
  mk('CREATE INDEX crm_leads_owner_score_idx  ON CRM_LEADS (emp_id, score)');
  -- Cột ngày-tạo: CRM_LEADS KHÔNG có 'created_date'. Tìm tên thật bằng query dò
  -- ở cuối file, rồi bỏ comment dòng dưới với đúng tên cột:
  -- mk('CREATE INDEX crm_leads_created_idx   ON CRM_LEADS (<TEN_COT_NGAY_TAO>)');

  ----------------------------------------------------------------------------
  -- Tool 4 (suggest_lead_actions) — overdue/today/cold dựa trên ngày
  ----------------------------------------------------------------------------
  mk('CREATE INDEX crm_leads_nextact_idx      ON CRM_LEADS (next_action_date)');
  mk('CREATE INDEX crm_leads_lastact_idx      ON CRM_LEADS (last_activity_date)');

  ----------------------------------------------------------------------------
  -- Tool 3 (query_lead_metrics) + Tool 5 filter — nhóm/lọc theo trạng thái, nhiệt độ
  ----------------------------------------------------------------------------
  mk('CREATE INDEX crm_leads_status_idx       ON CRM_LEADS (status)');
  mk('CREATE INDEX crm_leads_temp_idx         ON CRM_LEADS (temperature)');

  ----------------------------------------------------------------------------
  -- Tool 1 (lookup_lead_exact) — định danh. cle_code/email/tax_id thường đã UNIQUE;
  -- chỉ tạo nếu CHƯA có ràng buộc unique/index. Bỏ comment khi cần.
  ----------------------------------------------------------------------------
  -- mk('CREATE INDEX crm_leads_code_idx      ON CRM_LEADS (cle_code)');
  -- mk('CREATE INDEX crm_leads_email_idx     ON CRM_LEADS (LOWER(email))');
  -- mk('CREATE INDEX crm_leads_taxid_idx     ON CRM_LEADS (tax_id)');
END;
/

--------------------------------------------------------------------------------
-- Cập nhật thống kê để optimizer dùng index mới (chạy 1 lần sau khi tạo index).
-- Thay 'YOUR_SCHEMA' bằng schema thực tế (hoặc USER hiện tại).
--------------------------------------------------------------------------------
BEGIN
  DBMS_STATS.GATHER_TABLE_STATS(
    ownname          => USER,
    tabname          => 'CRM_LEADS',
    cascade          => TRUE,                      -- gather luôn index
    estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE);
  dbms_output.put_line('Đã gather stats cho CRM_LEADS.');
END;
/

--------------------------------------------------------------------------------
-- KIỂM TRA: xác nhận index đã tạo + theo dõi index có được dùng không.
--------------------------------------------------------------------------------
-- SELECT index_name, column_name, column_position
-- FROM   user_ind_columns
-- WHERE  table_name = 'CRM_LEADS'
-- ORDER  BY index_name, column_position;

-- DÒ TÊN CỘT NGÀY-TẠO thật của CRM_LEADS (chạy để biết tên thay cho created_date):
-- SELECT column_name, data_type
-- FROM   user_tab_columns
-- WHERE  table_name = 'CRM_LEADS'
--   AND  (data_type IN ('DATE','TIMESTAMP') OR column_name LIKE '%DATE%'
--                                           OR column_name LIKE '%CREAT%')
-- ORDER  BY column_id;

-- Đo kế hoạch thực thi 1 truy vấn rank điển hình:
-- EXPLAIN PLAN FOR
--   SELECT cle_code, score FROM CRM_LEADS WHERE emp_id = 1001
--   ORDER BY score DESC FETCH FIRST 10 ROWS ONLY;
-- SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
--------------------------------------------------------------------------------
