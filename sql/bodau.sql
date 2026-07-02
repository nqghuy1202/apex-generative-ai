--------------------------------------------------------------------------------
-- bodau.sql
-- Hàm BỎ DẤU tiếng Việt bằng SQL thuần (TRANSLATE) — thay cho mle_norm (MLE/JS).
-- APEX 26.1 / DB 26ai.
--
-- VÌ SAO DÙNG BODAU (thay mle_norm) Ở QUY MÔ >500k:
--   * TRANSLATE là SQL thuần -> KHÔNG tốn lời gọi JS engine từng dòng (mle_norm là
--     MLE per-value, chậm ở scan lớn).
--   * CÓ THỂ TẠO FUNCTION-BASED INDEX trên bodau(cột) -> tra cứu không-dấu vẫn dùng
--     index (xem cuối file). Đây là ưu điểm quyết định so với mle_norm.
--
-- HÀNH VI:
--   * Trả về CHỮ HOA không dấu: bodau('Hà Nội') = bodau('ha noi') = 'HA NOI'.
--   * đ/Đ -> D. Ký tự không có trong bảng map giữ nguyên.
--   * KHÁC mle_norm: KHÔNG lowercase (bodau=UPPER), KHÔNG trim/gộp khoảng trắng.
--     -> phải dùng THỐNG NHẤT bodau ở CẢ HAI VẾ so sánh (đã thay toàn bộ tool).
--
-- QUY TẮC TRANSLATE: chuỗi 'from' và 'to' map TỪNG KÝ TỰ theo vị trí -> độ dài
--   phải bằng nhau và KHÔNG được có khoảng trắng/xuống dòng thừa. Đã kiểm: 134 = 134.
--
-- CÁCH CHẠY: SQL Workshop > SQL Scripts, hoặc @sql/bodau.sql trong SQLcl.
--------------------------------------------------------------------------------

SET DEFINE OFF

CREATE OR REPLACE FUNCTION bodau(p_string IN VARCHAR2) RETURN VARCHAR2
DETERMINISTIC AS
BEGIN
  RETURN UPPER(TRANSLATE(
    p_string,
    'ăâđêôơưàảãạáằẳẵặắầẩẫậấèẻẽẹéềểễệếìỉĩịíòỏõọóồổỗộốờởỡợớùủũụúừửữựứỳỷỹỵýĂÂĐÊÔƠƯÀẢÃẠÁẰẲẴẶẮẦẨẪẬẤÈẺẼẸÉỀỂỄỆẾÌỈĨỊÍÒỎÕỌÓỒỔỖỘỐỜỞỠỢỚÙỦŨỤÚỪỬỮỰỨỲỶỸỴÝ',
    'aadeoouaaaaaaaaaaaaaaaeeeeeeeeeeiiiiiooooooooooooooouuuuuuuuuuyyyyyAADEOOUAAAAAAAAAAAAAAAEEEEEEEEEEIIIIIOOOOOOOOOOOOOOOUUUUUUUUUUYYYYY'));
END;
/

--------------------------------------------------------------------------------
-- KIỂM 1: độ dài from = to (BẮT BUỘC bằng nhau, nếu không map sẽ lệch)
--------------------------------------------------------------------------------
SELECT LENGTH('ăâđêôơưàảãạáằẳẵặắầẩẫậấèẻẽẹéềểễệếìỉĩịíòỏõọóồổỗộốờởỡợớùủũụúừửữựứỳỷỹỵýĂÂĐÊÔƠƯÀẢÃẠÁẰẲẴẶẮẦẨẪẬẤÈẺẼẸÉỀỂỄỆẾÌỈĨỊÍÒỎÕỌÓỒỔỖỘỐỜỞỠỢỚÙỦŨỤÚỪỬỮỰỨỲỶỸỴÝ') AS from_len,
       LENGTH('aadeoouaaaaaaaaaaaaaaaeeeeeeeeeeiiiiiooooooooooooooouuuuuuuuuuyyyyyAADEOOUAAAAAAAAAAAAAAAEEEEEEEEEEIIIIIOOOOOOOOOOOOOOOUUUUUUUUUUYYYYY') AS to_len
FROM dual;   -- kỳ vọng: 134 = 134

--------------------------------------------------------------------------------
-- KIỂM 2: kết quả (kỳ vọng: 'HA NOI', 'NGUYEN VAN AN', 'DA NANG', NULL)
--------------------------------------------------------------------------------
SELECT bodau('Hà Nội')         AS t1,
       bodau('NGUYỄN Văn An')  AS t2,
       bodau('Đà Nẵng')        AS t3,
       bodau(NULL)             AS t4
FROM dual;

--------------------------------------------------------------------------------
-- (KHUYẾN NGHỊ >500k) Function-based index cho tra cứu không-dấu trên CRM_LEADS.
--   Nhờ bodau là SQL thuần + DETERMINISTIC nên index này DÙNG ĐƯỢC (mle_norm không).
--   Tạo cho các cột hay tra theo tên/nguồn không dấu:
--------------------------------------------------------------------------------
-- CREATE INDEX crm_leads_name_bodau_idx     ON CRM_LEADS (bodau(cle_name));
-- CREATE INDEX crm_leads_customer_bodau_idx ON CRM_LEADS (bodau(customer));
-- CREATE INDEX crm_leads_source_bodau_idx   ON CRM_LEADS (bodau(source));
-- LƯU Ý: index chỉ được dùng khi WHERE viết ĐÚNG dạng bodau(cột) = bodau(:param)
--   hoặc bodau(cột) LIKE 'X%' (LIKE '%X%' vẫn full-scan index — bản chất leading %).
--------------------------------------------------------------------------------
