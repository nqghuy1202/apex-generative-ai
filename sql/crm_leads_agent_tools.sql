--------------------------------------------------------------------------------
-- crm_leads_agent_tools.sql
-- 4 truy vấn tool cho APEX AI Assistant trên bảng CRM_LEADS (APEX 26.1 / DB 26ai).
--
-- Mỗi khối /* ... */ = SQL DÁN VÀO App Builder > Generative AI > AI Assistant >
-- Tools (APEX tự truyền bind :p_* từ model — bind chạy tốt trong APEX).
--
-- Các SELECT KHÔNG nằm trong /* */ = test cục bộ dùng GIÁ TRỊ LITERAL trực tiếp
-- (SQL Workshop kén VARIABLE/BEGIN -> ORA-06502; literal chạy mọi nơi).
--
-- Phụ thuộc: CRM_LEADS (data), crm_leads_vector_rag.sql (crm_lead_embeddings),
--            bodau.sql (hàm bodau — bỏ dấu TRANSLATE, thay mle_norm).
-- Quy ước: AD-1 SQL set-based; AD-2 bind-only trong APEX (chống injection);
--          AD-3 không filter ngầm (GROUP BY động, không ép nhóm).
-- Mô tả tool (description) cho model: xem crm_leads_agent_prompts.md.
--
-- CÁCH CHẠY TEST: SQL Workshop > SQL Scripts > Upload > Run, hoặc SQLcl @file.
--------------------------------------------------------------------------------

SET DEFINE OFF

--==============================================================================
-- TOOL 1: lookup_lead_exact  — Tra cứu CHÍNH XÁC theo định danh (Nhóm C)
--   Dùng khi người dùng cung cấp mã/SĐT/email/MST CỤ THỂ. KHÔNG dùng vector.
--   Tham số APEX: p_code, p_phone, p_email, p_tax_id, p_name (tất cả optional)
--==============================================================================

-- >>> SQL DÁN VÀO APEX (Tool query):
/*
SELECT cle_id, cle_code, cle_name, customer, status, temperature, score,
       owner, phone, email, contact_name, contact_phone,
       next_action, next_action_date, last_activity_date
FROM   CRM_LEADS
WHERE  (:p_code   IS NULL OR UPPER(cle_code) = UPPER(:p_code))
  AND  (:p_phone  IS NULL OR REGEXP_REPLACE(phone,'[^0-9]','') =
                             REGEXP_REPLACE(:p_phone,'[^0-9]','')
                          OR REGEXP_REPLACE(contact_phone,'[^0-9]','') =
                             REGEXP_REPLACE(:p_phone,'[^0-9]',''))
  AND  (:p_email  IS NULL OR LOWER(email) = LOWER(:p_email))
  AND  (:p_tax_id IS NULL OR UPPER(tax_id) = UPPER(:p_tax_id))
  AND  (:p_name   IS NULL OR bodau(cle_name) LIKE '%' || bodau(:p_name) || '%'
                          OR bodau(customer) LIKE '%' || bodau(:p_name) || '%')
ORDER  BY cle_name
FETCH  FIRST 50 ROWS ONLY;
*/

-- --- TEST 1a: tra theo mã lead (thay literal cho phù hợp dữ liệu)
SELECT cle_code, cle_name, customer, status, owner
FROM   CRM_LEADS
WHERE  UPPER(cle_code) = UPPER('CL00001')
FETCH  FIRST 50 ROWS ONLY;

-- --- TEST 1b: tra theo SĐT (chuẩn hoá chỉ-số, khớp cả phone & contact_phone)
SELECT cle_code, cle_name, phone, contact_phone, status
FROM   CRM_LEADS
WHERE  REGEXP_REPLACE(phone,'[^0-9]','')        = REGEXP_REPLACE('0901234567','[^0-9]','')
   OR  REGEXP_REPLACE(contact_phone,'[^0-9]','')= REGEXP_REPLACE('0901234567','[^0-9]','')
FETCH  FIRST 50 ROWS ONLY;

-- --- TEST 1c: tra theo tên gõ KHÔNG dấu (bodau bỏ dấu 2 phía)
SELECT cle_code, cle_name, customer, status
FROM   CRM_LEADS
WHERE  bodau(cle_name) LIKE '%' || bodau('cong ty thep') || '%'
    OR bodau(customer) LIKE '%' || bodau('cong ty thep') || '%'
FETCH  FIRST 50 ROWS ONLY;


--==============================================================================
-- TOOL 2: search_leads_semantic  — Tìm NGỮ NGHĨA có PRE-FILTER (>500k)
--   Dùng khi người dùng MÔ TẢ nhu cầu/đặc điểm bằng ngôn ngữ tự nhiên.
--   PRE-FILTER theo status/emp_id chạy TRÊN CÙNG bảng embeddings (PRE_W trên HNSW).
--   Tham số APEX: p_search_text (bắt buộc), p_status, p_owner_emp_id (optional)
--==============================================================================

-- >>> SQL DÁN VÀO APEX (Tool query):
/*
SELECT l.cle_code, l.cle_name, l.customer, e.status, e.temperature,
       l.owner, l.next_action,
       ROUND(VECTOR_DISTANCE(
               e.embedding,
               apex_ai.get_vector_embeddings(
                 p_value             => :p_search_text,
                 p_service_static_id => 'apex-embed'),
               COSINE), 4) AS distance
FROM   crm_lead_embeddings e
JOIN   CRM_LEADS l ON l.cle_id = e.cle_id
WHERE  e.embedding IS NOT NULL
  AND  (:p_status        IS NULL OR e.status = :p_status)
  AND  (:p_owner_emp_id  IS NULL OR e.emp_id = :p_owner_emp_id)
ORDER  BY distance
FETCH  APPROX FIRST 10 ROWS ONLY;
*/

-- --- TEST 2: literal search_text (KHÔNG để NULL — NULL gây ORA-20954 HTTP-400)
SELECT l.cle_code, l.cle_name, l.customer, e.status, e.temperature,
       ROUND(VECTOR_DISTANCE(
               e.embedding,
               apex_ai.get_vector_embeddings(
                 p_value             => 'lead ngành sản xuất thép được giới thiệu',
                 p_service_static_id => 'apex-embed'),
               COSINE), 4) AS distance
FROM   crm_lead_embeddings e
JOIN   CRM_LEADS l ON l.cle_id = e.cle_id
WHERE  e.embedding IS NOT NULL
  AND  e.status = 'NEW'                         -- pre-filter (đổi/bỏ tùy nhu cầu)
ORDER  BY distance
FETCH  APPROX FIRST 10 ROWS ONLY;


--==============================================================================
-- TOOL 3: query_lead_metrics  — THỐNG KÊ pipeline (GROUP BY động, KHÔNG ép nhóm)
--   Dùng khi người dùng hỏi SỐ LƯỢNG/TỔNG/TB/phân bố lead theo nhóm.
--   Tham số APEX: p_group_by (status|temperature|source|owner),
--                 p_status, p_temperature, p_source (filter optional)
--==============================================================================

-- >>> SQL DÁN VÀO APEX (Tool query):
/*
-- LƯU Ý (fix bug p_group_by='owner'): MỌI nhánh CASE phải CÙNG kiểu dữ liệu, nếu
-- không -> ORA-00932 "inconsistent datatypes". owner/emp_id có thể là NUMBER còn
-- status/temperature/source là VARCHAR2 -> ép TO_CHAR toàn bộ để đồng nhất kiểu.
SELECT NVL(
         CASE :p_group_by
           WHEN 'status'      THEN TO_CHAR(status)
           WHEN 'temperature' THEN TO_CHAR(temperature)
           WHEN 'source'      THEN TO_CHAR(source)
           WHEN 'owner'       THEN TO_CHAR(owner)
         END, '(tat ca / all)')   AS group_value,
       COUNT(*)                    AS cnt,
       ROUND(AVG(score), 2)        AS avg_score,
       SUM(score)                  AS sum_score
FROM   CRM_LEADS
WHERE  (:p_status      IS NULL OR UPPER(status)      = UPPER(:p_status))
  AND  (:p_temperature IS NULL OR UPPER(temperature) = UPPER(:p_temperature))
  AND  (:p_source      IS NULL OR bodau(source)   = bodau(:p_source))
GROUP  BY CASE :p_group_by
            WHEN 'status'      THEN TO_CHAR(status)
            WHEN 'temperature' THEN TO_CHAR(temperature)
            WHEN 'source'      THEN TO_CHAR(source)
            WHEN 'owner'       THEN TO_CHAR(owner)
          END
ORDER  BY cnt DESC;
*/

-- --- TEST 3a: đếm theo trạng thái
SELECT status AS group_value, COUNT(*) AS cnt, ROUND(AVG(score),2) AS avg_score
FROM   CRM_LEADS
GROUP  BY status
ORDER  BY cnt DESC;

-- --- TEST 3b: đếm lead nóng (temperature='HOT'), KHÔNG nhóm -> 1 dòng tổng
SELECT '(tat ca / all)' AS group_value, COUNT(*) AS cnt
FROM   CRM_LEADS
WHERE  UPPER(temperature) = UPPER('HOT');

-- --- TEST 3c: nhóm theo owner (câu gây ORA-00932 trước đây) — TO_CHAR đồng nhất kiểu
SELECT TO_CHAR(owner) AS group_value, COUNT(*) AS cnt, ROUND(AVG(score),2) AS avg_score
FROM   CRM_LEADS
GROUP  BY TO_CHAR(owner)
ORDER  BY cnt DESC;


--==============================================================================
-- TOOL 4: suggest_lead_actions  — GỢI Ý ưu tiên chăm sóc (đặc thù bán hàng)
--   Dùng khi hỏi "chăm sóc lead nào trước", "quá hạn", "nóng/nguội", "việc hôm nay".
--   Xếp ưu tiên theo next_action_date / last_activity_date / temperature / score.
--   Tham số APEX: p_mode (overdue|hot|cold|today), p_owner_emp_id (optional), p_n
--==============================================================================

-- >>> SQL DÁN VÀO APEX (Tool query):
/*
SELECT cle_code, cle_name, customer, status, temperature, score, owner,
       next_action, next_action_date, last_activity_date,
       CASE
         WHEN :p_mode = 'overdue' THEN 'Quá hạn hành động'
         WHEN :p_mode = 'today'   THEN 'Cần làm hôm nay'
         WHEN :p_mode = 'hot'     THEN 'Lead nóng ưu tiên'
         WHEN :p_mode = 'cold'    THEN 'Lead nguội lâu chưa chăm sóc'
       END AS reason
FROM   CRM_LEADS
WHERE  (:p_owner_emp_id IS NULL OR emp_id = :p_owner_emp_id)
  AND  (
        (:p_mode = 'overdue' AND next_action_date < TRUNC(SYSDATE))
     OR (:p_mode = 'today'   AND TRUNC(next_action_date) = TRUNC(SYSDATE))
     OR (:p_mode = 'hot'     AND UPPER(temperature) = 'HOT')
     OR (:p_mode = 'cold'    AND last_activity_date < TRUNC(SYSDATE) - 30)
       )
  AND  UPPER(NVL(status,'X')) NOT IN ('WON','LOST','DISQUALIFIED')
ORDER  BY CASE WHEN :p_mode IN ('overdue','today') THEN next_action_date END ASC NULLS LAST,
          CASE WHEN :p_mode = 'cold' THEN last_activity_date END ASC NULLS FIRST,
          score DESC NULLS LAST
FETCH  FIRST :p_n ROWS ONLY;
*/

-- --- TEST 4a: lead quá hạn next action (ưu tiên ngày gần nhất)
SELECT cle_code, cle_name, next_action, next_action_date, score
FROM   CRM_LEADS
WHERE  next_action_date < TRUNC(SYSDATE)
  AND  UPPER(NVL(status,'X')) NOT IN ('WON','LOST','DISQUALIFIED')
ORDER  BY next_action_date ASC NULLS LAST, score DESC NULLS LAST
FETCH  FIRST 10 ROWS ONLY;

-- --- TEST 4b: lead nóng chưa chăm sóc > 30 ngày
SELECT cle_code, cle_name, temperature, last_activity_date, score
FROM   CRM_LEADS
WHERE  UPPER(temperature) = 'HOT'
  AND  last_activity_date < TRUNC(SYSDATE) - 30
ORDER  BY last_activity_date ASC NULLS FIRST, score DESC NULLS LAST
FETCH  FIRST 10 ROWS ONLY;

--==============================================================================
-- TOOL 5: rank_leads  — XẾP HẠNG / TOP-N TỪNG LEAD theo trường sắp xếp được
--   LẤP GAP: câu "lead nào điểm cao nhất / thấp nhất / mới nhất / cũ nhất",
--   "top 10 lead điểm cao của nhân viên X". query_lead_metrics chỉ GROUP BY
--   (trả số tổng hợp), suggest_lead_actions chỉ có mode cố định -> KHÔNG trả
--   được từng lead xếp hạng. Tool này trả DANH SÁCH lead đã sắp xếp + filter.
--   KHÔNG dùng vector (rẻ + nhanh trên CPU). Chỉ đọc cột cấu trúc/định danh.
--   Tham số APEX: p_order_by (score|next_action_date|last_activity_date),
--                 p_direction (desc=cao/mới nhất | asc=thấp/cũ nhất),
--                 p_status, p_temperature, p_owner_emp_id, p_source (filter optional),
--                 p_n (số dòng; "cao nhất"=1, "top 10"=10).
--==============================================================================

-- >>> SQL DÁN VÀO APEX (Tool query):
/*
SELECT cle_code, cle_name, customer, status, temperature, score, owner,
       next_action, next_action_date, last_activity_date
FROM   CRM_LEADS
WHERE  (:p_status       IS NULL OR UPPER(status)      = UPPER(:p_status))
  AND  (:p_temperature  IS NULL OR UPPER(temperature) = UPPER(:p_temperature))
  AND  (:p_owner_emp_id IS NULL OR emp_id             = :p_owner_emp_id)
  AND  (:p_source       IS NULL OR bodau(source)   = bodau(:p_source))
ORDER  BY
  CASE WHEN :p_order_by='score'              AND :p_direction='desc' THEN score              END DESC NULLS LAST,
  CASE WHEN :p_order_by='score'              AND :p_direction='asc'  THEN score              END ASC  NULLS LAST,
  CASE WHEN :p_order_by='next_action_date'   AND :p_direction='desc' THEN next_action_date   END DESC NULLS LAST,
  CASE WHEN :p_order_by='next_action_date'   AND :p_direction='asc'  THEN next_action_date   END ASC  NULLS LAST,
  CASE WHEN :p_order_by='last_activity_date' AND :p_direction='desc' THEN last_activity_date END DESC NULLS LAST,
  CASE WHEN :p_order_by='last_activity_date' AND :p_direction='asc'  THEN last_activity_date END ASC  NULLS LAST,
  score DESC NULLS LAST          -- tie-break mặc định
FETCH  FIRST :p_n ROWS ONLY;
-- GHI CHÚ: bỏ trục 'created_date' vì CRM_LEADS không có cột này. Nếu bảng của bạn
-- CÓ cột ngày-tạo (dò bằng query trong crm_leads_perf_indexes.sql), thêm lại 2 dòng:
--   CASE WHEN :p_order_by='created_date' AND :p_direction='desc' THEN <COT_NGAY_TAO> END DESC NULLS LAST,
--   CASE WHEN :p_order_by='created_date' AND :p_direction='asc'  THEN <COT_NGAY_TAO> END ASC  NULLS LAST,
*/

-- --- TEST 5a: LEAD ĐIỂM CAO NHẤT (câu hỏi gây lỗi trước đây) — n=1, desc
SELECT cle_code, cle_name, customer, status, temperature, score, owner
FROM   CRM_LEADS
ORDER  BY score DESC NULLS LAST
FETCH  FIRST 1 ROWS ONLY;

-- --- TEST 5b: TOP 10 lead điểm cao của 1 nhân viên (đổi literal emp_id)
SELECT cle_code, cle_name, status, score, owner
FROM   CRM_LEADS
WHERE  emp_id = 1001
ORDER  BY score DESC NULLS LAST
FETCH  FIRST 10 ROWS ONLY;

-- --- TEST 5c: lead có hoạt động GẦN NHẤT (last_activity_date desc)
SELECT cle_code, cle_name, status, score, last_activity_date
FROM   CRM_LEADS
ORDER  BY last_activity_date DESC NULLS LAST
FETCH  FIRST 5 ROWS ONLY;

-- --- INDEX khuyến nghị cho Tool 5: dùng file riêng crm_leads_perf_indexes.sql.


--------------------------------------------------------------------------------
-- HẾT. Test OK -> đăng ký 5 SQL (phần trong /* */) vào APEX AI Assistant,
-- dán mô tả tool + system prompt từ crm_leads_agent_prompts.md.
--
-- LƯU Ý:
--  * Trong APEX, model truyền bind :p_* nên KHÔNG gặp ORA-06502 (lỗi đó chỉ
--    xảy ra khi gán bind thủ công trong SQL Workshop khi test).
--  * Phân quyền dữ liệu: với người dùng là SALE, ép p_owner_emp_id = nhân viên
--    đăng nhập (qua APEX context / VPD) để chỉ thấy lead của mình; QUẢN LÝ để NULL.
--  * Chuẩn hoá enum (status/temperature) về tập canonical trước khi go-live để
--    GROUP BY (Tool 3) và pre-filter (Tool 2) không bị phân mảnh giá trị.
--
-- PERFORMANCE (toàn bộ 5 tool — mục tiêu phản hồi nhanh trên >500k + LLM CPU):
--  1) ĐỊNH TUYẾN TOOL ĐÚNG là đòn bẩy lớn nhất: chỉ Tool 2 dùng vector (đắt trên
--     CPU). Tool 1/3/4/5 là SQL cấu trúc thuần -> nhanh hơn nhiều. System prompt
--     phải đẩy câu xếp hạng/đếm/lookup sang tool SQL, KHÔNG để rơi vào vector.
--  2) INDEX cột sắp xếp/lọc: score, next_action_date, last_activity_date,
--     status, temperature, emp_id (xem file crm_leads_perf_indexes.sql).
--  3) Tool 5 ORDER BY dạng CASE rất LINH HOẠT nhưng VÔ HIỆU HOÁ index (sort toàn
--     tập đã lọc). Giảm tải bằng: (a) luôn truyền p_n nhỏ (1-20); (b) khuyến khích
--     model kèm filter (status/owner) để thu nhỏ tập trước khi sort. Nếu một trục
--     xếp hạng (vd score) bị hỏi rất nhiều, tách riêng 1 tool top_by_score với
--     ORDER BY score DESC tĩnh để DÙNG ĐƯỢC index crm_leads_score_idx.
--  4) GIỚI HẠN SỐ DÒNG TRẢ VỀ (FETCH FIRST n) -> ít token vào LLM -> sinh nhanh
--     hơn trên CPU. Chỉ SELECT cột cần hiển thị, tránh SELECT *.
--  5) bodau() là SQL thuần + DETERMINISTIC nên bọc quanh cột KHÔNG tắt index NẾU
--     có FUNCTION-BASED INDEX bodau(cột) (xem bodau.sql). Khác hẳn mle_norm (MLE/JS
--     per-row không index được). ĐIỀU KIỆN: WHERE viết đúng dạng bodau(cột)=bodau(:p)
--     hoặc bodau(cột) LIKE 'X%' (LIKE '%X%' vẫn full-scan vì leading %). Tạo FBI cho
--     cle_name/customer/source trước go-live (memory mle-normalize-at-write-not-query).
--------------------------------------------------------------------------------
