--------------------------------------------------------------------------------
-- customers_vector_rag.sql
-- RAG pipeline ngữ nghĩa cho bảng customers (APEX 26.1 / DB 26ai)
--
-- Luồng: customers (đã có) -> sinh profile_text cho mỗi khách -> embedding
--        bge-m3 qua service 'apex-embed' -> HNSW index -> similarity search APPROX.
--
-- Mô hình dữ liệu: mỗi DÒNG customers = một "tài liệu" -> KHÔNG cần chunk.
--   Ghép các cột nghiệp vụ thành 1 câu profile rồi embed cả câu đó.
--
-- Yêu cầu trước khi chạy:
--   * Đã chạy customers_sample.sql (bảng customers + data mẫu tồn tại).
--   * Generative AI Service static id = 'apex-embed' trỏ Ollama bge-m3:latest
--     (Base URL host:port, dimension 1024, COSINE).
--   * Quyền chạy APEX_AI trong schema hiện tại.
--
-- !!! CÁCH CHẠY: dùng SQL Workshop > SQL Scripts > Upload > Run, HOẶC SQLcl/SQL
--     Developer (chạy cả file). KHÔNG dán cả file vào SQL Commands (chỉ 1 lệnh/lần).
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON
SET DEFINE OFF

--------------------------------------------------------------------------------
-- BƯỚC 0: Dọn dẹp (idempotent — bỏ qua lỗi "không tồn tại")
--------------------------------------------------------------------------------
BEGIN EXECUTE IMMEDIATE 'DROP INDEX cust_emb_hnsw_idx';
EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE customer_embeddings CASCADE CONSTRAINTS PURGE';
EXCEPTION WHEN OTHERS THEN NULL; END;
/

--------------------------------------------------------------------------------
-- BƯỚC 1: Bảng embedding (1–1 với customers). PK cấp bằng SEQUENCE (quy ước dự án).
--   Lưu cả profile_text để biết đã embed nội dung gì (debug + hiển thị).
--------------------------------------------------------------------------------
BEGIN EXECUTE IMMEDIATE 'DROP SEQUENCE cust_emb_seq';
EXCEPTION WHEN OTHERS THEN NULL; END;
/
CREATE SEQUENCE cust_emb_seq START WITH 1 INCREMENT BY 1 NOCACHE;

CREATE TABLE customer_embeddings (
  emb_id        NUMBER PRIMARY KEY,
  customer_id   NUMBER NOT NULL
                  CONSTRAINT cust_emb_fk REFERENCES customers(customer_id),
  profile_text  VARCHAR2(2000),
  embedding     VECTOR(1024, FLOAT32),       -- khớp bge-m3 (1024 chiều)
  CONSTRAINT cust_emb_uk UNIQUE (customer_id)
);

--------------------------------------------------------------------------------
-- BƯỚC 2: Sinh profile_text cho mỗi khách hàng
--   Ghép các cột thành câu mô tả tự nhiên (song ngữ-friendly) để embed.
--   NVL để tránh chuỗi NULL làm hỏng câu; chỉ lấy khách chưa có embedding.
--------------------------------------------------------------------------------
INSERT INTO customer_embeddings (emb_id, customer_id, profile_text)
SELECT cust_emb_seq.NEXTVAL,
       c.customer_id,
       'Khách hàng: ' || c.full_name
         || '. Công ty: '    || NVL(c.company, 'cá nhân (không có công ty)')
         || '. Thành phố: '  || NVL(c.city, 'không rõ')
         || ', Quốc gia: '   || NVL(c.country, 'không rõ')
         || '. Phân khúc: '  || NVL(c.segment, 'không rõ')
         || '. Trạng thái: ' || NVL(c.status, 'không rõ')
         || '. Hạn mức tín dụng: '
         || NVL(TO_CHAR(c.credit_limit), 'chưa thiết lập')
         || '. Email: '      || NVL(c.email, 'không có')
         || '. Điện thoại: ' || NVL(c.phone, 'không có') || '.'
FROM   customers c
WHERE  NOT EXISTS (SELECT 1 FROM customer_embeddings e
                    WHERE e.customer_id = c.customer_id);
COMMIT;

--------------------------------------------------------------------------------
-- BƯỚC 3: Sinh embedding cho từng profile_text qua service 'apex-embed'
--   Nếu lỗi kiểu dữ liệu (ORA-00932...), bọc TO_VECTOR(...) như dòng ghi chú.
--------------------------------------------------------------------------------
BEGIN
  FOR e IN (SELECT emb_id, profile_text
              FROM customer_embeddings
             WHERE embedding IS NULL
               AND profile_text IS NOT NULL) LOOP
    UPDATE customer_embeddings
       SET embedding = apex_ai.get_vector_embeddings(
                         p_value             => e.profile_text,
                         p_service_static_id => 'apex-embed')
       -- NẾU lỗi kiểu, thay bằng:
       -- SET embedding = TO_VECTOR(apex_ai.get_vector_embeddings(
       --                   p_value => e.profile_text,
       --                   p_service_static_id => 'apex-embed'))
     WHERE emb_id = e.emb_id;
  END LOOP;
  COMMIT;
  dbms_output.put_line('Đã sinh embedding cho '
    || (SELECT COUNT(*) FROM customer_embeddings WHERE embedding IS NOT NULL)
    || ' / ' || (SELECT COUNT(*) FROM customer_embeddings) || ' khách hàng.');
END;
/

--------------------------------------------------------------------------------
-- BƯỚC 4: Vector Index HNSW (mặc định). Dùng IVF nếu thiếu vector pool memory.
--------------------------------------------------------------------------------
CREATE VECTOR INDEX cust_emb_hnsw_idx ON customer_embeddings (embedding)
ORGANIZATION INMEMORY NEIGHBOR GRAPH
DISTANCE COSINE
WITH TARGET ACCURACY 95
PARAMETERS (type HNSW, neighbors 40, efconstruction 500);

-- -- Phương án IVF (bỏ comment nếu không dùng HNSW):
-- CREATE VECTOR INDEX cust_emb_ivf_idx ON customer_embeddings (embedding)
-- ORGANIZATION NEIGHBOR PARTITIONS
-- DISTANCE COSINE
-- WITH TARGET ACCURACY 95
-- PARAMETERS (type IVF, neighbor partitions 10);

--------------------------------------------------------------------------------
-- BƯỚC 5: Similarity search (APPROX) — RAG retrieval
--   Sinh embedding cho câu hỏi -> lấy 5 khách gần nhất -> JOIN customers.
--------------------------------------------------------------------------------
DECLARE
  l_qvec  VECTOR;
  l_count PLS_INTEGER := 0;
BEGIN
  l_qvec := apex_ai.get_vector_embeddings(
              p_value             => 'khách hàng doanh nghiệp lớn ở Việt Nam',
              p_service_static_id => 'apex-embed');

  dbms_output.put_line('--- Top 5 khách hàng gần nhất ---');
  FOR r IN (
    SELECT c.full_name, c.company, c.country, c.segment,
           VECTOR_DISTANCE(e.embedding, l_qvec, COSINE) AS dist
    FROM   customer_embeddings e
    JOIN   customers c ON c.customer_id = e.customer_id
    ORDER  BY dist
    FETCH  APPROX FIRST 5 ROWS ONLY
  ) LOOP
    l_count := l_count + 1;
    dbms_output.put_line(
      l_count || '. [dist=' || ROUND(r.dist, 4) || '] '
      || r.full_name || ' — ' || NVL(r.company, 'cá nhân')
      || ' (' || r.country || ', ' || r.segment || ')');
  END LOOP;
END;
/

--------------------------------------------------------------------------------
-- LƯU Ý đồng bộ dữ liệu:
--   Khi customers thay đổi (INSERT/UPDATE), chạy lại BƯỚC 2 + BƯỚC 3 để cập nhật
--   profile_text và embedding cho các dòng mới/đổi. Có thể xoá dòng tương ứng
--   trong customer_embeddings trước khi chạy lại nếu UPDATE nội dung khách hàng.
--------------------------------------------------------------------------------
