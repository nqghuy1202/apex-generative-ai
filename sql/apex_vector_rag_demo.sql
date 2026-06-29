--------------------------------------------------------------------------------
-- apex_vector_rag_demo.sql
-- End-to-end demo: Vector RAG search trên Oracle APEX 26.1 / Oracle DB 26ai
--
-- Luồng: tạo bảng (2 bảng RAG) -> nạp tài liệu mẫu tiếng Việt -> chunk
--        -> sinh embedding (bge-m3 qua service 'apex-embed') -> tạo vector index
--        -> truy vấn similarity search (APPROX).
--
-- Yêu cầu trước khi chạy:
--   * Generative AI Service static id = 'apex-embed' đã trỏ tới Ollama bge-m3:latest
--     (Base URL host:port, dimension 1024, COSINE).
--   * Quyền chạy DBMS_VECTOR_CHAIN và APEX_AI trong schema hiện tại.
--   * Chạy trong SQL Workshop > SQL Commands (hoặc SQLcl). Bật DBMS_OUTPUT.
--
-- Lưu ý: phần [chưa xác minh] đã ghi chú inline. Nếu lỗi kiểu dữ liệu ở embedding,
--        xem ghi chú TO_VECTOR ở Bước 4.
--
-- !!! CÁCH CHẠY (QUAN TRỌNG) !!!
--   * KHÔNG dán cả file vào "SQL Workshop > SQL Commands" — nơi đó chỉ chạy MỘT
--     statement/lần và không hiểu lệnh SET, nên sẽ lỗi ORA-00980 / cascade.
--   * Chạy cả file bằng MỘT trong hai cách hỗ trợ nhiều statement:
--       (A) SQL Workshop > SQL Scripts > Upload file này > Run; hoặc
--       (B) SQLcl / SQL Developer (kết nối tới schema), chạy như script.
--   * Nếu vẫn muốn dùng SQL Commands: chạy LẦN LƯỢT từng block (mỗi block kết thúc
--     bằng dấu / hoặc ; ), bỏ qua các lệnh SET ở đầu.
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON
SET DEFINE OFF

--------------------------------------------------------------------------------
-- BƯỚC 0: Dọn dẹp (idempotent — drop trực tiếp, KHÔNG query data dictionary
--         để tránh ORA-00980 trong môi trường APEX). Lỗi "không tồn tại" được bỏ qua.
--------------------------------------------------------------------------------
BEGIN EXECUTE IMMEDIATE 'DROP INDEX doc_chunks_hnsw_idx';
EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP INDEX doc_chunks_ivf_idx';
EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE doc_chunks CASCADE CONSTRAINTS PURGE';
EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE documents CASCADE CONSTRAINTS PURGE';
EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP SEQUENCE doc_seq';
EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP SEQUENCE dch_seq';
EXCEPTION WHEN OTHERS THEN NULL; END;
/

--------------------------------------------------------------------------------
-- BƯỚC 1: Tạo schema 2 bảng (parent–child, RAG-ready)
--------------------------------------------------------------------------------
CREATE TABLE documents (
  doc_id     NUMBER PRIMARY KEY,
  title      VARCHAR2(500),
  source     VARCHAR2(1000),
  doc_text   CLOB,
  created_at TIMESTAMP DEFAULT SYSTIMESTAMP
);

CREATE TABLE doc_chunks (
  chunk_id   NUMBER PRIMARY KEY,
  doc_id     NUMBER NOT NULL REFERENCES documents(doc_id),
  chunk_seq  NUMBER,
  chunk_text VARCHAR2(4000),
  embedding  VECTOR(1024, FLOAT32)        -- khớp bge-m3 (1024 chiều) để index được
);

-- Sequence cấp khoá chính
CREATE SEQUENCE doc_seq START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE dch_seq START WITH 1 INCREMENT BY 1 NOCACHE;

--------------------------------------------------------------------------------
-- BƯỚC 2: Nạp tài liệu mẫu tiếng Việt (dài, nhiều đoạn)
--------------------------------------------------------------------------------
INSERT INTO documents (doc_id, title, source, doc_text) VALUES (
  doc_seq.NEXTVAL,
  'Giới thiệu Oracle AI Vector Search',
  'demo/oracle-ai-vector-search.txt',
  q'[Oracle AI Vector Search là tính năng tích hợp sẵn trong Oracle Database, cho phép lưu trữ và tìm kiếm dữ liệu dưới dạng vector ngay bên trong cơ sở dữ liệu. Thay vì phải dùng một vector database riêng biệt, người dùng có thể lưu embedding cùng với dữ liệu nghiệp vụ và truy vấn bằng SQL quen thuộc.

Embedding là biểu diễn số học của văn bản. Một mô hình embedding như bge-m3 sẽ chuyển một đoạn văn bản thành một danh sách số thực gọi là vector. Hai đoạn văn bản có ý nghĩa gần nhau sẽ tạo ra hai vector gần nhau trong không gian nhiều chiều. Nhờ đó, ta có thể tìm kiếm theo ngữ nghĩa thay vì chỉ so khớp từ khoá.

Để tìm kiếm tương đồng, Oracle cung cấp hàm VECTOR_DISTANCE với nhiều thước đo như COSINE, EUCLIDEAN và DOT. Khoảng cách càng nhỏ thì hai vector càng giống nhau. Truy vấn thường sắp xếp theo khoảng cách tăng dần và lấy ra một số dòng gần nhất.

Khi dữ liệu lớn, việc quét toàn bộ bảng sẽ chậm. Oracle hỗ trợ vector index gồm hai loại chính là HNSW và IVF. HNSW là chỉ mục dạng đồ thị nằm trong bộ nhớ, cho tốc độ và độ chính xác cao. IVF là chỉ mục dạng phân vùng, tiết kiệm bộ nhớ hơn và phù hợp với tập dữ liệu rất lớn. Khi dùng chỉ mục, ta thêm từ khoá APPROX vào truy vấn để thực hiện tìm kiếm gần đúng nhanh hơn.

Một quy trình RAG điển hình gồm các bước: chia nhỏ tài liệu dài thành nhiều đoạn, sinh embedding cho từng đoạn, lưu vào bảng có cột vector, rồi khi người dùng đặt câu hỏi thì sinh embedding cho câu hỏi và tìm các đoạn gần nhất để làm ngữ cảnh cho mô hình ngôn ngữ trả lời.]'
);

INSERT INTO documents (doc_id, title, source, doc_text) VALUES (
  doc_seq.NEXTVAL,
  'Hướng dẫn pha cà phê phin',
  'demo/ca-phe-phin.txt',
  q'[Cà phê phin là cách pha cà phê truyền thống của Việt Nam. Đầu tiên, cho khoảng hai muỗng cà phê bột vào phin rồi lắc nhẹ cho phẳng mặt. Đặt nắp gài lên trên và ấn nhẹ để nén bột vừa phải, không quá chặt cũng không quá lỏng.

Tiếp theo, rót một ít nước sôi để ủ cho cà phê nở trong khoảng ba mươi giây. Sau đó rót thêm nước sôi đầy phin và đậy nắp lại. Cà phê sẽ nhỏ giọt từ từ xuống ly bên dưới trong vài phút.

Bạn có thể thưởng thức cà phê phin nóng, hoặc thêm đá và sữa đặc để có ly cà phê sữa đá mát lạnh. Hương vị đậm đà và cách pha chậm rãi là nét đặc trưng của văn hoá cà phê Việt Nam.]'
);

COMMIT;

--------------------------------------------------------------------------------
-- BƯỚC 3: Chunking — cắt doc_text thành nhiều đoạn ≤ 4000 ký tự
--   Dùng by:"characters" (an toàn cho tiếng Việt vì không phụ thuộc NLS language).
--   max 3000 ký tự, overlap 300 (~10%) để giữ ngữ cảnh giữa các chunk.
--------------------------------------------------------------------------------
BEGIN
  FOR d IN (SELECT doc_id, doc_text FROM documents) LOOP
    INSERT INTO doc_chunks (chunk_id, doc_id, chunk_seq, chunk_text)
    SELECT dch_seq.NEXTVAL,
           d.doc_id,
           JSON_VALUE(c.column_value, '$.chunk_id'   RETURNING NUMBER),
           JSON_VALUE(c.column_value, '$.chunk_data')
    FROM   dbms_vector_chain.utl_to_chunks(
             d.doc_text,
             JSON('{ "by":"characters", "max":"3000", "overlap":"300",
                     "split":"recursively", "normalize":"all" }')
           ) c;
  END LOOP;
  COMMIT;
  dbms_output.put_line('Đã tạo ' || (SELECT COUNT(*) FROM doc_chunks) || ' chunk.');
END;
/

--------------------------------------------------------------------------------
-- BƯỚC 4: Sinh embedding cho từng chunk qua service 'apex-embed' (bge-m3)
--   Nếu gặp lỗi kiểu dữ liệu (ORA-00932/ORA-21560...), bọc TO_VECTOR(...) như
--   dòng đã ghi chú bên dưới.
--------------------------------------------------------------------------------
BEGIN
  FOR ch IN (SELECT chunk_id, chunk_text
               FROM doc_chunks
              WHERE embedding IS NULL
                AND chunk_text IS NOT NULL) LOOP

    UPDATE doc_chunks
       SET embedding = apex_ai.get_vector_embeddings(
                         p_value             => ch.chunk_text,
                         p_service_static_id => 'apex-embed')
       -- NẾU lỗi kiểu, thay bằng:
       -- SET embedding = TO_VECTOR(apex_ai.get_vector_embeddings(
       --                   p_value => ch.chunk_text,
       --                   p_service_static_id => 'apex-embed'))
     WHERE chunk_id = ch.chunk_id;
  END LOOP;
  COMMIT;
  dbms_output.put_line('Đã sinh embedding cho '
    || (SELECT COUNT(*) FROM doc_chunks WHERE embedding IS NOT NULL)
    || ' chunk.');
END;
/

--------------------------------------------------------------------------------
-- BƯỚC 5: Tạo Vector Index (HNSW — mặc định cho test)
--   Nếu môi trường thiếu vector pool memory cho HNSW, dùng khối IVF bên dưới.
--------------------------------------------------------------------------------
CREATE VECTOR INDEX doc_chunks_hnsw_idx ON doc_chunks (embedding)
ORGANIZATION INMEMORY NEIGHBOR GRAPH
DISTANCE COSINE
WITH TARGET ACCURACY 95
PARAMETERS (type HNSW, neighbors 40, efconstruction 500);

-- -- Phương án IVF (bỏ comment nếu không dùng HNSW):
-- CREATE VECTOR INDEX doc_chunks_ivf_idx ON doc_chunks (embedding)
-- ORGANIZATION NEIGHBOR PARTITIONS
-- DISTANCE COSINE
-- WITH TARGET ACCURACY 95
-- PARAMETERS (type IVF, neighbor partitions 10);

--------------------------------------------------------------------------------
-- BƯỚC 6: Truy vấn similarity search (APPROX) — RAG retrieval
--   Sinh embedding cho câu hỏi rồi lấy 5 chunk gần nhất, JOIN ngược documents.
--------------------------------------------------------------------------------
DECLARE
  l_qvec   VECTOR;
  l_count  PLS_INTEGER := 0;
BEGIN
  l_qvec := apex_ai.get_vector_embeddings(
              p_value             => 'Làm sao để tìm kiếm theo ngữ nghĩa trong cơ sở dữ liệu?',
              p_service_static_id => 'apex-embed');

  dbms_output.put_line('--- Top 5 chunk gần nhất ---');
  FOR r IN (
    SELECT d.title,
           dc.chunk_text,
           VECTOR_DISTANCE(dc.embedding, l_qvec, COSINE) AS dist
    FROM   doc_chunks dc
    JOIN   documents  d ON d.doc_id = dc.doc_id
    ORDER  BY dist
    FETCH  APPROX FIRST 5 ROWS ONLY        -- bỏ APPROX => exact full-scan
  ) LOOP
    l_count := l_count + 1;
    dbms_output.put_line(
      l_count || '. [dist=' || ROUND(r.dist, 4) || '] '
      || r.title || ' :: '
      || SUBSTR(r.chunk_text, 1, 100) || '...');
  END LOOP;
END;
/

--------------------------------------------------------------------------------
-- BƯỚC 7 (tuỳ chọn): Kiểm tra index có được dùng không (tránh rơi về exact scan)
--------------------------------------------------------------------------------
-- EXPLAIN PLAN FOR
-- SELECT dc.chunk_id
-- FROM   doc_chunks dc
-- ORDER  BY VECTOR_DISTANCE(dc.embedding,
--             apex_ai.get_vector_embeddings(p_value=>'test', p_service_static_id=>'apex-embed'),
--             COSINE)
-- FETCH  APPROX FIRST 5 ROWS ONLY;
-- SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
--------------------------------------------------------------------------------
