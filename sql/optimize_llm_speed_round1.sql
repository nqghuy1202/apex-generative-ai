--------------------------------------------------------------------------------
-- optimize_llm_speed_round1.sql
-- Vòng 1 (Quick wins) — tối ưu tốc độ phản hồi AI Assistant trên CPU
-- Bối cảnh: qwen3.5:latest (5.8GB, CPU-only) phản hồi 80–153s/câu.
-- Mục tiêu: 5–15s/câu. Xem báo cáo:
--   _bmad-output/planning-artifacts/research/technical-cpu-llm-speed-optimization-research-2026-06-29.md
--
-- File này chứa THAY ĐỔI SQL cho tool RAG (giảm top-k).
-- Các bước ngoài DB (đổi model, Modelfile, biến môi trường) xem README_llm_speed_round1.md
--------------------------------------------------------------------------------

-- ĐÒN BẨY #3: Giảm RAG top-k 5 -> 3 trong tool search_customers_semantic
-- Cắt ~40% độ dài context nhồi vào prompt => giảm mạnh thời gian "prompt eval" (~60s).
-- => Cập nhật SQL query của tool search_customers_semantic trong APEX thành:

select c.full_name, c.company, c.city, c.country, c.segment, c.status,
       round(vector_distance(
               e.embedding,
               apex_ai.get_vector_embeddings(
                 p_value             => :search_text,
                 p_service_static_id => 'apex-embed'),
               cosine), 4) as distance
from   customer_embeddings e
join   customers c on c.customer_id = e.customer_id
order  by distance
fetch  approx first 3 rows only;   -- ĐÃ ĐỔI: 5 -> 3

--------------------------------------------------------------------------------
-- Ghi chú: tool query_customer_metrics đã gom nhóm (GROUP BY) nên kết quả nhỏ gọn,
-- KHÔNG cần đổi. Nếu kết quả nhiều dòng, cân nhắc thêm 'fetch first N rows only'
-- để tránh nhồi quá nhiều dữ liệu vào context của model.
--------------------------------------------------------------------------------
