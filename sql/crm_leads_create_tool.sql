--------------------------------------------------------------------------------
-- crm_leads_create_tool.sql
-- TOOL 6 (WRITE): create_lead — TẠO khách hàng tiềm năng mới từ ngôn ngữ tự nhiên
-- qua APEX 26.1 AI Assistant (kiểu "Support Ticket"). Đây là tool PL/SQL (DML),
-- KHÁC 5 read-tool (SQL SELECT) trong crm_leads_agent_tools.sql.
--
-- CẤU HÌNH APEX: Shared Components > AI Agents > <agent> > Tools > Add Tool
--   Name: create_lead | Execution Point: On Demand | Type: PL/SQL
--   >>> BẬT "Requires Confirmation" (human-in-the-loop) — bắt buộc cho write-tool.
--   Parameters (Data Type / Required):
--     p_name    VARCHAR2  REQUIRED  — tên lead hoặc người liên hệ
--     p_company VARCHAR2            — tên công ty
--     p_phone   VARCHAR2            — số điện thoại
--     p_email   VARCHAR2            — email
--     p_source  VARCHAR2            — nguồn (hội chợ, giới thiệu, web...)
--     p_note    VARCHAR2            — ghi chú thêm
--   (cần >=1 trong p_phone/p_email để chống trùng có ý nghĩa)
--
-- AN TOÀN: APEX gán giá trị model trích xuất vào BIND (:p_*) — KHÔNG nối chuỗi,
--   chống injection theo thiết kế. Mô tả tool + system prompt: crm_leads_agent_prompts.md.
--
-- !!! CHỈNH TRƯỚC KHI DÙNG:
--   * <CRM_LEADS_SEQ>: thay bằng tên SEQUENCE PK thật của CRM_LEADS.
--   * v_emp_id: thay bằng cách map :APP_USER -> emp_id của bạn (VPD/context/bảng).
--   * Tập cột INSERT: bỏ/thêm cột cho khớp NOT NULL constraint thực tế của bảng.
--------------------------------------------------------------------------------

-- >>> KHỐI DÁN VÀO APEX — Tool type = PL/SQL (FUNCTION BODY trả VARCHAR2).
--     APEX biên dịch body như HÀM phải RETURN giá trị (chuỗi kết quả model đọc).
--     => MỌI nhánh phải RETURN '<chuỗi>'. KHÔNG dùng apex_ai.set_tool_result và
--        KHÔNG dùng RETURN; trống (gây PLS-00503).
-- (Bản COMPACT comment-free < 4000 ký tự cho ô code APEX. Dán từ DECLARE đến END;)
/*
DECLARE
  v_cle_id  CRM_LEADS.cle_id%TYPE;
  v_code    CRM_LEADS.cle_code%TYPE;
  v_ym      VARCHAR2(6) := TO_CHAR(SYSDATE,'YYYYMM');
  v_seq     NUMBER;
  v_emp_id  CRM_LEADS.emp_id%TYPE := NULL;
  v_dup     CRM_LEADS.cle_code%TYPE;
  v_profile VARCHAR2(4000);
BEGIN
  IF :p_name IS NULL OR TRIM(:p_name) IS NULL THEN
    RETURN 'Chưa đủ thông tin: thiếu tên lead. Hãy hỏi lại người dùng tên lead.';
  END IF;
  BEGIN
    SELECT cle_code INTO v_dup FROM CRM_LEADS
    WHERE (:p_phone IS NOT NULL
           AND (REGEXP_REPLACE(phone,'[^0-9]','')=REGEXP_REPLACE(:p_phone,'[^0-9]','')
             OR REGEXP_REPLACE(contact_phone,'[^0-9]','')=REGEXP_REPLACE(:p_phone,'[^0-9]','')))
       OR (:p_email IS NOT NULL AND LOWER(email)=LOWER(:p_email))
    FETCH FIRST 1 ROWS ONLY;
    RETURN 'Lead đã tồn tại với mã '||v_dup||' (trùng SĐT/email). KHÔNG tạo mới.';
  EXCEPTION WHEN NO_DATA_FOUND THEN NULL;
  END;
  v_cle_id := cle_seq.NEXTVAL;
  SELECT COUNT(*)+1 INTO v_seq FROM CRM_LEADS WHERE cle_code LIKE 'LEAD-'||v_ym||'-%';
  v_code := 'LEAD-'||v_ym||'-'||LPAD(v_seq,4,'0');
  INSERT INTO CRM_LEADS (cle_id,cle_code,cle_name,customer,phone,email,source,
                         introduce_note,status,temperature,emp_id,last_activity_date)
  VALUES (v_cle_id,v_code,:p_name,:p_company,:p_phone,:p_email,:p_source,
          :p_note,'NEW','WARM',v_emp_id,SYSDATE);
  v_profile := SUBSTR('Khách hàng tiềm năng: '||NVL(:p_name,NVL(:p_company,'không rõ'))
    ||'. Công ty: '||NVL(:p_company,'không rõ')||'. Nguồn: '||NVL(:p_source,'không rõ')
    ||'. Ghi chú: '||NVL(:p_note,'không có')||'.',1,4000);
  INSERT INTO crm_lead_embeddings (emb_id,cle_id,status,temperature,emp_id,profile_text,embedding)
  VALUES (crm_lead_emb_seq.NEXTVAL,v_cle_id,'NEW','WARM',v_emp_id,v_profile,NULL);
  COMMIT;
  RETURN 'Đã tạo lead '||v_code||' cho "'||:p_name||'". Báo người dùng mã lead này.';
EXCEPTION WHEN OTHERS THEN
  ROLLBACK;
  RETURN 'Lỗi khi tạo lead: '||SQLERRM;
END;
*/

--------------------------------------------------------------------------------
-- TEST CỤC BỘ (SQL Workshop) — dùng GIÁ TRỊ LITERAL thay cho :p_* (bind chỉ chạy
-- trong APEX). Chạy thử logic chống trùng + sinh mã, KHÔNG gọi apex_ai/COMMIT thật.
--------------------------------------------------------------------------------

-- --- TEST 6a: xem mã LEAD-YYYYMM-#### kế tiếp sẽ là gì
SELECT 'LEAD-' || TO_CHAR(SYSDATE,'YYYYMM') || '-' ||
       LPAD((SELECT COUNT(*)+1 FROM CRM_LEADS
              WHERE cle_code LIKE 'LEAD-'||TO_CHAR(SYSDATE,'YYYYMM')||'-%'), 4, '0')
       AS next_code
FROM dual;

-- --- TEST 6b: kiểm tra 1 SĐT có trùng không (thay literal)
SELECT cle_code, cle_name, phone, email
FROM   CRM_LEADS
WHERE  REGEXP_REPLACE(phone,'[^0-9]','')         = REGEXP_REPLACE('0901234567','[^0-9]','')
   OR  REGEXP_REPLACE(contact_phone,'[^0-9]','') = REGEXP_REPLACE('0901234567','[^0-9]','')
   OR  LOWER(email) = LOWER('minh@thepviet.vn')
FETCH FIRST 5 ROWS ONLY;

--------------------------------------------------------------------------------
-- HẾT. Test OK -> tạo tool PL/SQL create_lead trong APEX, BẬT Requires Confirmation,
-- dán mô tả Tool 6 + cập nhật System Prompt (crm_leads_agent_prompts.md).
--------------------------------------------------------------------------------
