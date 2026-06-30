--------------------------------------------------------------------------------
-- crm_leads_vector_rag.sql
-- RAG pipeline ngữ nghĩa cho bảng CRM_LEADS (APEX 26.1 / DB 26ai), quy mô >500k.
--
-- Luồng: CRM_LEADS (đã có) -> sinh profile_text (CHỈ cột Nhóm A - ngữ nghĩa)
--        -> embedding bge-m3 qua service 'apex-embed' -> Local Partitioned HNSW
--        -> similarity search APPROX có PRE-FILTER (status/emp_id/temperature).
--
-- Mô hình dữ liệu: mỗi DÒNG CRM_LEADS = một "tài liệu" -> KHÔNG cần chunk.
--   Bảng embedding 1-1 mang THEM các cột filter (status, emp_id, temperature, co_id)
--   để vector search + WHERE chạy trên CÙNG 1 bảng => bật được PRE-FILTER ở >500k.
--
-- Phân loại cột (xem báo cáo research crm-leads-ai-agent-setup):
--   Nhóm A (Semantic, đưa vào embedding): cle_name, customer, source, cle_type,
--     introduce_type, introduce_person, introduce_company, introduce_note,
--     next_action, contact_name, contact_position, contact_department, owner,
--     disqualify_reason.
--   Nhóm B (Structured, filter/aggregate): status, temperature, score, *_id, dates.
--   Nhóm C (Identity, lookup b-tree): cle_code, phone, email, contact_phone, tax_id.
--
-- Yêu cầu trước khi chạy:
--   * Bảng CRM_LEADS + dữ liệu đã tồn tại.
--   * Generative AI Service static id = 'apex-embed' trỏ Ollama bge-m3:latest
--     (Base URL host:port, dimension 1024, COSINE).
--   * Quyền chạy APEX_AI trong schema hiện tại.
--   * (khuyến nghị) đã chạy mle_text_normalize.sql nếu dùng kèm agent tools.
--
-- !!! CÁCH CHẠY: SQL Workshop > SQL Scripts > Upload > Run, HOẶC SQLcl/SQL
--     Developer (chạy cả file). KHÔNG dán cả file vào SQL Commands (1 lệnh/lần).
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON
SET DEFINE OFF

--------------------------------------------------------------------------------
-- BƯỚC 0: Dọn dẹp (idempotent — bỏ qua lỗi "không tồn tại")
--------------------------------------------------------------------------------
BEGIN EXECUTE IMMEDIATE 'DROP INDEX crm_lead_emb_hnsw_idx';
EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE crm_lead_embeddings CASCADE CONSTRAINTS PURGE';
EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP SEQUENCE crm_lead_emb_seq';
EXCEPTION WHEN OTHERS THEN NULL; END;
/

--------------------------------------------------------------------------------
-- BƯỚC 1: Bảng embedding (1-1 với CRM_LEADS). PK cấp bằng SEQUENCE (quy ước dự án).
--   Mang theo cột FILTER (status/emp_id/temperature/co_id) để pre-filter ở >500k.
--   profile_text lưu lại nội dung đã embed (debug + hiển thị).
--------------------------------------------------------------------------------
CREATE SEQUENCE crm_lead_emb_seq START WITH 1 INCREMENT BY 1 NOCACHE;

CREATE TABLE crm_lead_embeddings (
  emb_id        NUMBER PRIMARY KEY,
  cle_id        NUMBER(15) NOT NULL
                  CONSTRAINT crm_lead_emb_fk REFERENCES CRM_LEADS(cle_id),
  -- cột filter denormalized (đồng bộ từ CRM_LEADS để PRE-FILTER trên 1 bảng):
  status        VARCHAR2(30),
  temperature   VARCHAR2(10),
  emp_id        NUMBER(15),
  co_id         NUMBER(15),
  profile_text  VARCHAR2(4000),
  embedding     VECTOR(1024, FLOAT32),       -- khớp bge-m3 (1024 chiều)
  CONSTRAINT crm_lead_emb_uk UNIQUE (cle_id)
);

-- B-tree cho cột pre-filter (giúp lọc trước khi quét vector ở >500k)
CREATE INDEX crm_lead_emb_status_idx ON crm_lead_embeddings (status);
CREATE INDEX crm_lead_emb_emp_idx    ON crm_lead_embeddings (emp_id);

--------------------------------------------------------------------------------
-- BƯỚC 2: Sinh profile_text — GHÉP CHỈ CỘT NHÓM A thành câu mô tả tự nhiên.
--   Tiếng Việt CÓ DẤU (quy ước dự án: model embed/đọc tốt hơn khi có dấu).
--   NVL tránh chuỗi NULL; SUBSTR cap 4000; chỉ lấy lead chưa có embedding.
--   Đồng bộ luôn cột filter (status/temperature/emp_id/co_id).
--
--   >>> QUY MÔ >500k: lần đầu nên backfill theo lô. Bỏ comment dòng ROWNUM để
--       chạy thử 1000 dòng trước, rồi gỡ ra chạy full (hoặc dùng job nền).
--------------------------------------------------------------------------------
INSERT INTO crm_lead_embeddings
  (emb_id, cle_id, status, temperature, emp_id, co_id, profile_text)
SELECT crm_lead_emb_seq.NEXTVAL,
       l.cle_id, l.status, l.temperature, l.emp_id, l.co_id,
       SUBSTR(
         'Khách hàng tiềm năng: ' || NVL(l.cle_name, NVL(l.customer, 'không rõ'))
         || '. Công ty: '       || NVL(l.customer, 'không rõ')
         || '. Loại: '          || NVL(l.cle_type, 'không rõ')
         || '. Nguồn: '         || NVL(l.source, 'không rõ')
         || '. Người liên hệ: ' || NVL(l.contact_name, 'không rõ')
         || ' - '               || NVL(l.contact_position, 'không rõ')
         || ', phòng '          || NVL(l.contact_department, 'không rõ')
         || '. Giới thiệu bởi: '|| NVL(l.introduce_person, 'không có')
         || ' ('                || NVL(l.introduce_company, 'không có') || ')'
         || ', kiểu giới thiệu '|| NVL(l.introduce_type, 'không rõ')
         || '. Phụ trách: '     || NVL(l.owner, 'chưa phân công')
         || '. Hành động tiếp theo: ' || NVL(l.next_action, 'chưa có')
         || '. Ghi chú giới thiệu: '  || NVL(l.introduce_note, 'không có')
         || '. Lý do loại: '    || NVL(l.disqualify_reason, 'không có') || '.'
       , 1, 4000)
FROM   CRM_LEADS l
WHERE  NOT EXISTS (SELECT 1 FROM crm_lead_embeddings e WHERE e.cle_id = l.cle_id)
-- AND  ROWNUM <= 1000      -- <<< bỏ comment để chạy thử lô nhỏ trước
;
COMMIT;

--------------------------------------------------------------------------------
-- BƯỚC 3: Sinh embedding cho từng profile_text qua service 'apex-embed'.
--   >500k: tốn nhiều thời gian trên CPU -> chạy incremental (WHERE embedding IS NULL)
--   nhiều lần / job nền. Nếu lỗi kiểu (ORA-00932), bọc TO_VECTOR(...).
--------------------------------------------------------------------------------
BEGIN
  FOR e IN (SELECT emb_id, profile_text
              FROM crm_lead_embeddings
             WHERE embedding IS NULL
               AND profile_text IS NOT NULL) LOOP
    UPDATE crm_lead_embeddings
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
    || (SELECT COUNT(*) FROM crm_lead_embeddings WHERE embedding IS NOT NULL)
    || ' / ' || (SELECT COUNT(*) FROM crm_lead_embeddings) || ' lead.');
END;
/

--------------------------------------------------------------------------------
-- BƯỚC 4: Vector Index — Local Partitioned HNSW (khuyến nghị cho >500k).
--   Partition pruning + pre-filter => giữ độ trễ thấp. Chuyển IVF nếu vượt ~50tr
--   dòng hoặc thiếu Vector Memory Pool.
--
--   LƯU Ý: để PARTITION được, bảng crm_lead_embeddings cần là bảng partitioned
--   (vd PARTITION BY LIST(status)). Bản dựng nhanh dưới đây dùng HNSW global —
--   vẫn chạy tốt ở mức vài trăm nghìn dòng. Xem khối ALTER/partition ở cuối file
--   nếu muốn nâng cấp lên local partitioned.
--------------------------------------------------------------------------------
CREATE VECTOR INDEX crm_lead_emb_hnsw_idx ON crm_lead_embeddings (embedding)
ORGANIZATION INMEMORY NEIGHBOR GRAPH
DISTANCE COSINE
WITH TARGET ACCURACY 95
PARAMETERS (type HNSW, neighbors 40, efconstruction 500);

-- -- Phương án IVF (>50tr dòng / thiếu vector pool):
-- CREATE VECTOR INDEX crm_lead_emb_ivf_idx ON crm_lead_embeddings (embedding)
-- ORGANIZATION NEIGHBOR PARTITIONS
-- DISTANCE COSINE
-- WITH TARGET ACCURACY 95
-- PARAMETERS (type IVF, neighbor partitions 100);

--------------------------------------------------------------------------------
-- BƯỚC 5: Similarity search (APPROX) CÓ PRE-FILTER — RAG retrieval.
--   Lọc trước theo status/emp_id (Nhóm B) rồi mới xếp theo vector_distance.
--   Đây là mẫu cho tool search_leads_semantic (xem crm_leads_agent_tools.sql).
--------------------------------------------------------------------------------
DECLARE
  l_qvec  VECTOR;
  l_count PLS_INTEGER := 0;
BEGIN
  l_qvec := apex_ai.get_vector_embeddings(
              p_value             => 'lead ngành sản xuất được giới thiệu, đang theo dõi',
              p_service_static_id => 'apex-embed');

  dbms_output.put_line('--- Top 5 lead gần nhất (pre-filter status=NEW) ---');
  FOR r IN (
    SELECT l.cle_code, l.cle_name, l.customer, e.status, e.temperature,
           VECTOR_DISTANCE(e.embedding, l_qvec, COSINE) AS dist
    FROM   crm_lead_embeddings e
    JOIN   CRM_LEADS l ON l.cle_id = e.cle_id
    WHERE  e.embedding IS NOT NULL
      AND  (e.status = 'NEW')                  -- PRE-FILTER (đổi/bỏ tùy nhu cầu)
    ORDER  BY dist
    FETCH  APPROX FIRST 5 ROWS ONLY
  ) LOOP
    l_count := l_count + 1;
    dbms_output.put_line(
      l_count || '. [dist=' || ROUND(r.dist, 4) || '] '
      || r.cle_code || ' — ' || NVL(r.cle_name, r.customer)
      || ' (' || r.status || '/' || r.temperature || ')');
  END LOOP;
END;
/

--------------------------------------------------------------------------------
-- ĐỒNG BỘ DỮ LIỆU (incremental — KHÔNG re-embed toàn bảng):
--   * Lead MỚI: BƯỚC 2 (INSERT … WHERE NOT EXISTS) + BƯỚC 3 (WHERE embedding IS NULL).
--   * Lead ĐỔI nội dung Nhóm A: xoá dòng tương ứng trong crm_lead_embeddings
--     rồi chạy lại BƯỚC 2 + 3. (Có thể tự động bằng trigger AFTER UPDATE.)
--   * Lead ĐỔI status/emp_id (Nhóm B): chỉ cần UPDATE cột filter denormalized:
--       UPDATE crm_lead_embeddings e
--          SET (status, temperature, emp_id, co_id) =
--              (SELECT status, temperature, emp_id, co_id FROM CRM_LEADS l
--                WHERE l.cle_id = e.cle_id)
--        WHERE … ;   -- không cần re-embed
--   * NULL embedding => VECTOR_DISTANCE trả NULL => dòng bị loại. Chạy job backfill.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- (TÙY CHỌN) Nâng cấp Local Partitioned HNSW cho quy mô rất lớn:
--   1) Tạo lại crm_lead_embeddings với:  PARTITION BY LIST (status) ( … )
--      hoặc PARTITION BY HASH (co_id) PARTITIONS N.
--   2) CREATE VECTOR INDEX … LOCAL  (index cục bộ theo partition => partition pruning).
--   Việc này nên làm ở giai đoạn tuning sau khi đo tải thực tế.
--------------------------------------------------------------------------------
