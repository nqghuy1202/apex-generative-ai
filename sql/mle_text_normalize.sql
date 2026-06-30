--------------------------------------------------------------------------------
-- mle_text_normalize.sql
-- MLE (Multilingual Engine) JavaScript module — chuẩn hoá chuỗi tiếng Việt
-- APEX 26.1 / DB 26ai. Bỏ dấu + lowercase + trim để so khớp không phân biệt dấu.
--
-- Mục đích: vá lỗ hổng Q8 (Phase 0) — "khach hang o tokyo" / "ha noi" vẫn khớp.
-- Quy ước (AD-1): MLE CHỈ xử lý chuỗi; KHÔNG chứa truy vấn set-based.
--
-- CÁCH CHẠY: SQLcl / SQL Developer (cả file), hoặc SQL Workshop > SQL Scripts.
-- Quyền: schema cần EXECUTE ON JAVASCRIPT (DB 26ai bật MLE mặc định).
--        Nếu thiếu: DBA chạy  GRANT EXECUTE ON JAVASCRIPT TO <schema>;
--------------------------------------------------------------------------------

SET DEFINE OFF

--------------------------------------------------------------------------------
-- MLE module: hàm norm() bỏ dấu tiếng Việt
--   "Hà Nội" / "ha noi" / "HA NOI"  ->  "ha noi"
--   "NGUYỄN Văn An"                 ->  "nguyen van an"
--   Dùng ̀-ͯ (combining diacritics) để không phụ thuộc encoding file.
--------------------------------------------------------------------------------
CREATE OR REPLACE MLE MODULE text_norm_mod LANGUAGE JAVASCRIPT AS

export function norm(s) {
  if (s === null || s === undefined) return null;
  return String(s)
    .normalize('NFD')                       // tách ký tự gốc + dấu
    .replace(/[̀-ͯ]/g, '')        // xoá toàn bộ dấu thanh/dấu mũ
    .replace(/đ/g, 'd')                // đ -> d
    .replace(/Đ/g, 'd')                // Đ -> d
    .toLowerCase()
    .trim()
    .replace(/\s+/g, ' ');                  // gộp khoảng trắng thừa
}
/

--------------------------------------------------------------------------------
-- Call spec: expose hàm JS norm() cho SQL với tên mle_norm()
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mle_norm(p_in IN VARCHAR2) RETURN VARCHAR2
AS MLE MODULE text_norm_mod SIGNATURE 'norm(string)';
/

--------------------------------------------------------------------------------
-- Kiểm tra nhanh (kỳ vọng: 'ha noi', 'nguyen van an', 'tokyo', NULL)
--------------------------------------------------------------------------------
SELECT mle_norm('Hà Nội')        AS t1,
       mle_norm('NGUYỄN Văn An') AS t2,
       mle_norm('  Tokyo  ')     AS t3,
       mle_norm(NULL)            AS t4
FROM   dual;
