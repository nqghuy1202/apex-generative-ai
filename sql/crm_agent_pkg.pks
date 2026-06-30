--------------------------------------------------------------------------------
-- crm_agent_pkg.pks — PACKAGE SPEC
-- Đóng gói các hàm phục vụ APEX AI Agent tools trên CRM_LEADS.
-- MỖI tool trong APEX chỉ gọi 1 DÒNG -> né giới hạn 4000 ký tự + tập trung logic.
--
-- Quy ước: trả VARCHAR2 chuỗi TIẾNG VIỆT CÓ DẤU (model đọc & báo lại trực tiếp);
--   tham số là tham số HÀM (bind-only trong APEX) -> chống injection;
--   PK dùng SEQUENCE (cle_seq), KHÔNG IDENTITY;
--   KHÔNG sinh embedding inline (để job nền crm_leads_embed_backfill — tránh ORA-29276).
--
-- Triển khai: chạy file này (spec) TRƯỚC, rồi crm_agent_pkg.pkb (body).
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE crm_agent_pkg AS

  -- Tạo khách hàng tiềm năng mới từ ngôn ngữ tự nhiên (tool APEX: create_lead).
  -- Chống trùng theo SĐT/email; tự sinh cle_code = LEAD-YYYYMM-####.
  -- Trả: chuỗi thông báo (đã tạo mã.../đã tồn tại.../thiếu tên/lỗi).
  FUNCTION create_lead(
    p_name    IN VARCHAR2,
    p_company IN VARCHAR2 DEFAULT NULL,
    p_phone   IN VARCHAR2 DEFAULT NULL,
    p_email   IN VARCHAR2 DEFAULT NULL,
    p_source  IN VARCHAR2 DEFAULT NULL,
    p_note    IN VARCHAR2 DEFAULT NULL
  ) RETURN VARCHAR2;

  ------------------------------------------------------------------------------
  -- KHUNG MỞ RỘNG — hàm action tương lai (CHƯA hiện thực; thêm body khi cần).
  -- Giữ cùng quy ước: trả VARCHAR2 tiếng Việt, bind-only, COMMIT/ROLLBACK nội bộ.
  --   FUNCTION update_lead   (p_code IN VARCHAR2, p_phone IN VARCHAR2 DEFAULT NULL,
  --                           p_email IN VARCHAR2 DEFAULT NULL, ...) RETURN VARCHAR2;
  --   FUNCTION change_status (p_code IN VARCHAR2, p_status IN VARCHAR2) RETURN VARCHAR2;
  --   FUNCTION log_activity  (p_code IN VARCHAR2, p_note   IN VARCHAR2) RETURN VARCHAR2;
  ------------------------------------------------------------------------------

END crm_agent_pkg;
/
