--------------------------------------------------------------------------------
-- customer_agent_tools.sql
-- 4 truy vấn tool cho APEX AI Assistant trên bảng `customers` (APEX 26.1 / DB 26ai)
--
-- Mỗi khối /* ... */ = SQL DÁN VÀO App Builder > Generative AI > AI Assistant >
-- Tools (APEX tự truyền bind :p_* từ model — bind chạy tốt trong APEX).
--
-- Các SELECT KHÔNG nằm trong /* */ = test cục bộ dùng GIÁ TRỊ LITERAL trực tiếp
-- (SQL Workshop kén VARIABLE/BEGIN -> ORA-06502; literal chạy mọi nơi).
--
-- Phụ thuộc: customers_sample.sql, customers_vector_rag.sql, mle_text_normalize.sql
-- Quy ước: AD-1 SQL set-based; AD-2 bind-only trong APEX (chống injection); AD-3 không filter ngầm.
--
-- CÁCH CHẠY TEST: SQL Workshop > SQL Scripts > Upload > Run, hoặc SQLcl @file.
--------------------------------------------------------------------------------

SET DEFINE OFF

--==============================================================================
-- TOOL 1: lookup_customer_exact  — phủ Q1, Q2, Q3, Q6
--   Tham số APEX: p_name, p_email, p_company, p_city, p_country, p_segment,
--                 p_status, p_credit_min, p_credit_max  (tất cả optional, NULL=bỏ qua)
--==============================================================================

-- >>> SQL DÁN VÀO APEX (Tool query):
/*
SELECT customer_id, full_name, email, phone, company,
       city, country, segment, status, credit_limit
FROM   customers
WHERE  (:p_name      IS NULL OR mle_norm(full_name) LIKE '%' || mle_norm(:p_name) || '%')
  AND  (:p_email     IS NULL OR UPPER(email)   = UPPER(:p_email))
  AND  (:p_company   IS NULL OR mle_norm(company)  LIKE '%' || mle_norm(:p_company) || '%')
  AND  (:p_city      IS NULL OR mle_norm(city)     = mle_norm(:p_city))
  AND  (:p_country   IS NULL OR mle_norm(country)  = mle_norm(:p_country))
  AND  (:p_segment   IS NULL OR UPPER(segment) = UPPER(:p_segment))
  AND  (:p_status    IS NULL OR UPPER(status)  = UPPER(:p_status))
  AND  (:p_credit_min IS NULL OR credit_limit >= :p_credit_min)
  AND  (:p_credit_max IS NULL OR credit_limit <= :p_credit_max)
ORDER  BY full_name
FETCH  FIRST 50 ROWS ONLY;
*/

-- --- TEST 1a (Q1): Email Nguyễn Văn An, gõ KHÔNG dấu -> 1 dòng: an.nguyen@vietsoft.vn
SELECT full_name, email, city
FROM   customers
WHERE  mle_norm(full_name) LIKE '%' || mle_norm('nguyen van an') || '%'
ORDER  BY full_name;

-- --- TEST 1b (Q2): KH ở Hà Nội, gõ "ha noi" -> 3 dòng: An, Đức, Lan
SELECT full_name, city, segment, status
FROM   customers
WHERE  mle_norm(city) = mle_norm('ha noi')
ORDER  BY full_name;

-- --- TEST 1c (Q3): Enterprise ACTIVE ở Vietnam -> 3 dòng: An, Bình, Lan
SELECT full_name, segment, status, country, credit_limit
FROM   customers
WHERE  UPPER(segment) = UPPER('Enterprise')
  AND  UPPER(status)  = UPPER('ACTIVE')
  AND  mle_norm(country) = mle_norm('Vietnam')
ORDER  BY full_name;

-- --- TEST 1d (Q6): credit_limit 100tr–500tr -> Dung(120tr), Khánh(150tr), Hoa(300tr), An(500tr)
SELECT full_name, credit_limit
FROM   customers
WHERE  credit_limit >= 100000000
  AND  credit_limit <= 500000000
ORDER  BY credit_limit;


--==============================================================================
-- TOOL 2: query_customer_metrics  — phủ Q4 (VÁ BUG H4: GROUP BY động, không ép nhóm)
--   Tham số APEX: p_segment, p_status, p_country (optional), p_group_by
--==============================================================================

-- >>> SQL DÁN VÀO APEX:
/*
SELECT NVL(
         CASE :p_group_by
           WHEN 'segment' THEN segment
           WHEN 'status'  THEN status
           WHEN 'country' THEN country
           WHEN 'city'    THEN city
           WHEN 'company' THEN company
         END, '(tat ca / all)') AS group_value,
       COUNT(*)                 AS cnt,
       SUM(credit_limit)        AS sum_credit,
       ROUND(AVG(credit_limit)) AS avg_credit,
       MIN(credit_limit)        AS min_credit,
       MAX(credit_limit)        AS max_credit
FROM   customers
WHERE  (:p_segment IS NULL OR UPPER(segment) = UPPER(:p_segment))
  AND  (:p_status  IS NULL OR UPPER(status)  = UPPER(:p_status))
  AND  (:p_country IS NULL OR mle_norm(country) = mle_norm(:p_country))
GROUP  BY CASE :p_group_by
            WHEN 'segment' THEN segment
            WHEN 'status'  THEN status
            WHEN 'country' THEN country
            WHEN 'city'    THEN city
            WHEN 'company' THEN company
          END
ORDER  BY cnt DESC;
*/

-- --- TEST 2a (Q4): Đếm Enterprise, KHÔNG nhóm -> 1 dòng, cnt = 6 (bug cũ = 4)
SELECT '(tat ca / all)' AS group_value,
       COUNT(*)         AS cnt,
       SUM(credit_limit) AS sum_credit
FROM   customers
WHERE  UPPER(segment) = UPPER('Enterprise');

-- --- TEST 2b (Q4): Đếm theo segment (p_group_by='segment') -> Enterprise=6, SMB=4, Individual=2
SELECT segment AS group_value, COUNT(*) AS cnt, SUM(credit_limit) AS sum_credit
FROM   customers
GROUP  BY segment
ORDER  BY cnt DESC;


--==============================================================================
-- TOOL 3: rank_customers  — phủ Q5 (FETCH FIRST thường, KHÔNG APPROX)
--   Tham số APEX: p_order_col (credit_limit|created_at), p_dir (DESC|ASC), p_n
--==============================================================================

-- >>> SQL DÁN VÀO APEX:
/*
SELECT full_name, company, country, segment, credit_limit, created_at
FROM   customers
ORDER  BY CASE WHEN :p_order_col='credit_limit' AND :p_dir='DESC' THEN credit_limit END DESC NULLS LAST,
          CASE WHEN :p_order_col='credit_limit' AND :p_dir='ASC'  THEN credit_limit END ASC  NULLS LAST,
          CASE WHEN :p_order_col='created_at'   AND :p_dir='DESC' THEN created_at   END DESC,
          CASE WHEN :p_order_col='created_at'   AND :p_dir='ASC'  THEN created_at   END ASC
FETCH  FIRST :p_n ROWS ONLY;
*/

-- --- TEST 3 (Q5): Top 3 credit cao nhất -> Lan (2 tỷ), Bình (750tr), An (500tr)
SELECT full_name, company, country, segment, credit_limit
FROM   customers
ORDER  BY credit_limit DESC NULLS LAST
FETCH  FIRST 3 ROWS ONLY;


--==============================================================================
-- TOOL 4: search_customers_semantic  — phủ Q7 (hardened: top-k 5, tên nguyên văn)
--   Tham số APEX: p_search_text
--==============================================================================

-- >>> SQL DÁN VÀO APEX:
/*
SELECT c.full_name, c.company, c.city, c.country, c.segment, c.status,
       ROUND(VECTOR_DISTANCE(
               e.embedding,
               apex_ai.get_vector_embeddings(
                 p_value             => :p_search_text,
                 p_service_static_id => 'apex-embed'),
               COSINE), 4) AS distance
FROM   customer_embeddings e
JOIN   customers c ON c.customer_id = e.customer_id
WHERE  e.embedding IS NOT NULL
ORDER  BY distance
FETCH  APPROX FIRST 5 ROWS ONLY;
*/

-- --- TEST 4 (Q7): literal search_text (KHÔNG để NULL — NULL gây ORA-20954 HTTP-400)
SELECT c.full_name, c.company, c.country, c.segment,
       ROUND(VECTOR_DISTANCE(
               e.embedding,
               apex_ai.get_vector_embeddings(
                 p_value             => 'khách hàng doanh nghiệp lớn ở Việt Nam',
                 p_service_static_id => 'apex-embed'),
               COSINE), 4) AS distance
FROM   customer_embeddings e
JOIN   customers c ON c.customer_id = e.customer_id
WHERE  e.embedding IS NOT NULL
ORDER  BY distance
FETCH  APPROX FIRST 5 ROWS ONLY;

--------------------------------------------------------------------------------
-- HẾT. Test OK -> đăng ký 4 SQL (phần trong /* */) vào APEX AI Assistant,
-- cập nhật system prompt (solution-design-customers-agent-tools-mle.md mục 5).
--
-- LƯU Ý: trong APEX, model truyền bind :p_* nên KHÔNG gặp ORA-06502.
--        ORA-06502 chỉ xảy ra khi gán bind thủ công trong SQL Workshop (test).
--------------------------------------------------------------------------------
