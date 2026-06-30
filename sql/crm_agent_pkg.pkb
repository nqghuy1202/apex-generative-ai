--------------------------------------------------------------------------------
-- crm_agent_pkg.pkb — PACKAGE BODY
-- Chạy SAU crm_agent_pkg.pks. Xem spec để biết quy ước + khung mở rộng.
--
-- DÁN VÀO TOOL APEX (create_lead, Type = PL/SQL, function body trả VARCHAR2),
-- chỉ 1 dòng (bật Requires Confirmation cho write-tool):
--   RETURN crm_agent_pkg.create_lead(
--     p_name => :p_name, p_company => :p_company, p_phone => :p_phone,
--     p_email => :p_email, p_source => :p_source, p_note => :p_note);
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY crm_agent_pkg AS

  FUNCTION create_lead(
    p_name    IN VARCHAR2,
    p_company IN VARCHAR2 DEFAULT NULL,
    p_phone   IN VARCHAR2 DEFAULT NULL,
    p_email   IN VARCHAR2 DEFAULT NULL,
    p_source  IN VARCHAR2 DEFAULT NULL,
    p_note    IN VARCHAR2 DEFAULT NULL
  ) RETURN VARCHAR2
  IS
    v_cle_id  CRM_LEADS.cle_id%TYPE;
    v_code    CRM_LEADS.cle_code%TYPE;
    v_ym      VARCHAR2(6) := TO_CHAR(SYSDATE, 'YYYYMM');
    v_seq     NUMBER;
    v_emp_id  CRM_LEADS.emp_id%TYPE := NULL;   -- không map APP_USER -> để NULL
    v_dup     CRM_LEADS.cle_code%TYPE;
    v_profile VARCHAR2(4000);
  BEGIN
    -- 0) Bắt buộc có tên
    IF p_name IS NULL OR TRIM(p_name) IS NULL THEN
      RETURN 'Chưa đủ thông tin: thiếu tên lead. Hãy hỏi lại người dùng tên lead.';
    END IF;

    -- 1) Chống trùng theo SĐT (chỉ-số) hoặc email (lower)
    BEGIN
      SELECT cle_code INTO v_dup
      FROM   CRM_LEADS
      WHERE  ( p_phone IS NOT NULL
               AND ( REGEXP_REPLACE(phone,'[^0-9]','')         = REGEXP_REPLACE(p_phone,'[^0-9]','')
                  OR REGEXP_REPLACE(contact_phone,'[^0-9]','') = REGEXP_REPLACE(p_phone,'[^0-9]','') ) )
         OR  ( p_email IS NOT NULL AND LOWER(email) = LOWER(p_email) )
      FETCH FIRST 1 ROWS ONLY;
      RETURN 'Lead đã tồn tại với mã ' || v_dup ||
             ' (trùng SĐT/email). KHÔNG tạo mới. Báo người dùng dùng mã này để tra cứu.';
    EXCEPTION WHEN NO_DATA_FOUND THEN
      NULL;  -- không trùng -> tạo mới
    END;

    -- 2) Sinh khoá: cle_id (sequence) + cle_code = LEAD-YYYYMM-####
    v_cle_id := cle_seq.NEXTVAL;
    SELECT COUNT(*) + 1 INTO v_seq
    FROM   CRM_LEADS
    WHERE  cle_code LIKE 'LEAD-' || v_ym || '-%';
    v_code := 'LEAD-' || v_ym || '-' || LPAD(v_seq, 4, '0');

    -- 3) INSERT CRM_LEADS (chỉnh cột cho khớp NOT NULL của bảng nếu cần)
    INSERT INTO CRM_LEADS (cle_id, cle_code, cle_name, customer, phone, email,
                           source, introduce_note, status, temperature, emp_id,
                           last_activity_date)
    VALUES (v_cle_id, v_code, p_name, p_company, p_phone, p_email,
            p_source, p_note, 'NEW', 'WARM', v_emp_id, SYSDATE);

    -- 4) Xếp hàng embedding (NULL) — job nền sinh sau, ngoài luồng chat
    v_profile := SUBSTR(
        'Khách hàng tiềm năng: ' || NVL(p_name, NVL(p_company,'không rõ'))
        || '. Công ty: ' || NVL(p_company,'không rõ')
        || '. Nguồn: '   || NVL(p_source,'không rõ')
        || '. Ghi chú: ' || NVL(p_note,'không có') || '.', 1, 4000);

    INSERT INTO crm_lead_embeddings
      (emb_id, cle_id, status, temperature, emp_id, profile_text, embedding)
    VALUES
      (crm_lead_emb_seq.NEXTVAL, v_cle_id, 'NEW', 'WARM', v_emp_id, v_profile, NULL);

    -- 5) COMMIT + trả chuỗi thành công
    COMMIT;
    RETURN 'Đã tạo lead ' || v_code || ' cho "' || p_name ||
           '". Báo người dùng mã lead này.';

  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RETURN 'Lỗi khi tạo lead: ' || SQLERRM || '. KHÔNG báo là đã tạo thành công.';
  END create_lead;

END crm_agent_pkg;
/
