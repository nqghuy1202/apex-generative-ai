--------------------------------------------------------------------------------
-- crm_leads_agent_generate_poc.sql
-- PoC đòn bẩy #1 (report round 3 §2): CẮT lượt-2 LLM bằng APEX_AI.GENERATE + hard-exit.
--
-- MỤC TIÊU: chứng minh 1 câu-dùng-tool chỉ còn **1 lượt LLM** (thay vì 2), xoá hẳn
--   ~35-71s prefill lượt-2 không-cache-được (marker UNTRUSTED-DATA). Đo bằng tcpdump
--   port 11434: chỉ 1 request /api/chat cho câu "có bao nhiêu khách hàng tiềm năng?".
--
-- Ý TƯỞNG:
--   Luồng AI Assistant hiện tại = 2 lượt: (1) LLM chọn tool -> (2) APEX gửi KẾT QUẢ
--   tool + marker UNTRUSTED về LLM để nó "đọc & soạn lời". Lượt-2 LUÔN cache-miss.
--   Luồng PoC = 1 lượt: (1) LLM chọn tool + tham số -> tool PL/SQL chạy SQL VÀ TỰ
--   FORMAT kết quả thành câu tiếng Việt -> response handler HARD-EXIT trả thẳng chuỗi
--   đó cho người dùng, KHÔNG gọi LLM lần 2.
--
-- PHẠM VI PoC: CHỈ 1 tool inline = query_lead_metrics (đếm/tổng theo nhóm). Mở rộng
--   6 tool sau khi PoC xác nhận đúng 1 lượt (report §7 bước 5).
--
-- ⚠️ ‹XÁC NHẬN API› — Các dòng đánh dấu ‹XÁC NHẬN› dùng tên type/tham số của
--   APEX_AI 26.1 (t_tools/t_tool, callback, p_response_handler_procedure). Bản 24.2
--   CHƯA có p_tools; blog "Build Ad-hoc AI Agents Entirely in PL/SQL" (26.1) là nguồn
--   gốc nhưng chặn fetch tự động. Trước khi chạy, đối chiếu tên chính xác trong:
--   App Builder > Help, hoặc `DESC APEX_AI` / `SELECT text FROM all_source
--   WHERE name='APEX_AI' AND type='PACKAGE'` trên DB 26ai của bạn. Phần LOGIC
--   (SQL tool + format tiếng Việt + hard-exit) đúng bất kể tên API.
--
-- Phụ thuộc: CRM_LEADS, bodau.sql (hàm bodau — bỏ dấu TRANSLATE), service 'apex-embed'
--   (không cần cho tool này — query_lead_metrics là SQL thuần, không vector).
--------------------------------------------------------------------------------

SET DEFINE OFF
SET SERVEROUTPUT ON

--==============================================================================
-- PHẦN 1: Package chứa (a) hàm chạy+format tool, (b) response handler hard-exit.
--   Đóng gói để trang APEX chỉ gọi 1 dòng (né giới hạn 4000 ký tự) + tái dùng.
--==============================================================================

CREATE OR REPLACE PACKAGE crm_agent_gen_pkg AS

  -- (a) Chạy query_lead_metrics VÀ format kết quả thành câu tiếng Việt CÓ DẤU.
  --     Tham số = đúng các tham số model trích được (khai đủ, không thừa -> tránh
  --     ORA-20960). Trả VARCHAR2 = câu trả lời cuối cùng cho người dùng.
  FUNCTION run_query_lead_metrics(
    p_group_by    IN VARCHAR2 DEFAULT NULL,   -- status|temperature|source|owner|NULL(tổng)
    p_status      IN VARCHAR2 DEFAULT NULL,
    p_temperature IN VARCHAR2 DEFAULT NULL,
    p_source      IN VARCHAR2 DEFAULT NULL
  ) RETURN VARCHAR2;

END crm_agent_gen_pkg;
/

CREATE OR REPLACE PACKAGE BODY crm_agent_gen_pkg AS

  FUNCTION run_query_lead_metrics(
    p_group_by    IN VARCHAR2 DEFAULT NULL,
    p_status      IN VARCHAR2 DEFAULT NULL,
    p_temperature IN VARCHAR2 DEFAULT NULL,
    p_source      IN VARCHAR2 DEFAULT NULL
  ) RETURN VARCHAR2 IS
    l_out   VARCHAR2(4000);
    l_rows  PLS_INTEGER := 0;
    l_total PLS_INTEGER := 0;
  BEGIN
    -- Không nhóm -> trả 1 con số tổng gọn (đường nhanh, câu phổ biến nhất).
    IF p_group_by IS NULL THEN
      SELECT COUNT(*) INTO l_total
      FROM   CRM_LEADS
      WHERE  (p_status      IS NULL OR UPPER(status)      = UPPER(p_status))
        AND  (p_temperature IS NULL OR UPPER(temperature) = UPPER(p_temperature))
        AND  (p_source      IS NULL OR bodau(source)   = bodau(p_source));

      l_out := 'Có ' || l_total || ' khách hàng tiềm năng';
      IF p_status      IS NOT NULL THEN l_out := l_out || ' ở trạng thái ' || p_status; END IF;
      IF p_temperature IS NOT NULL THEN l_out := l_out || ' mức ' || p_temperature; END IF;
      IF p_source      IS NOT NULL THEN l_out := l_out || ' nguồn ' || p_source; END IF;
      RETURN l_out || '.';
    END IF;

    -- Có nhóm -> liệt kê từng nhóm (TO_CHAR đồng nhất kiểu -> fix owner ORA-00932).
    l_out := 'Thống kê theo ' || p_group_by || ':' || CHR(10);
    FOR r IN (
      SELECT NVL(
               CASE p_group_by
                 WHEN 'status'      THEN TO_CHAR(status)
                 WHEN 'temperature' THEN TO_CHAR(temperature)
                 WHEN 'source'      THEN TO_CHAR(source)
                 WHEN 'owner'       THEN TO_CHAR(owner)
               END, '(khác)')        AS group_value,
             COUNT(*)                AS cnt,
             ROUND(AVG(score), 1)    AS avg_score
      FROM   CRM_LEADS
      WHERE  (p_status      IS NULL OR UPPER(status)      = UPPER(p_status))
        AND  (p_temperature IS NULL OR UPPER(temperature) = UPPER(p_temperature))
        AND  (p_source      IS NULL OR bodau(source)   = bodau(p_source))
      GROUP  BY CASE p_group_by
                  WHEN 'status'      THEN TO_CHAR(status)
                  WHEN 'temperature' THEN TO_CHAR(temperature)
                  WHEN 'source'      THEN TO_CHAR(source)
                  WHEN 'owner'       THEN TO_CHAR(owner)
                END
      ORDER  BY cnt DESC
      FETCH  FIRST 20 ROWS ONLY
    ) LOOP
      l_rows := l_rows + 1;
      l_out  := l_out || '- ' || r.group_value || ': ' || r.cnt
                || ' lead (điểm TB ' || NVL(TO_CHAR(r.avg_score), 'n/a') || ')' || CHR(10);
    END LOOP;

    IF l_rows = 0 THEN
      RETURN 'Không tìm thấy lead nào khớp điều kiện.';
    END IF;
    RETURN RTRIM(l_out, CHR(10));
  EXCEPTION
    WHEN OTHERS THEN
      RETURN 'Lỗi khi thống kê: ' || SQLERRM;
  END run_query_lead_metrics;

END crm_agent_gen_pkg;
/

--==============================================================================
-- PHẦN 2: Test PL/SQL THUẦN (không qua LLM) — xác nhận format tiếng Việt đúng
--   TRƯỚC khi cắm vào APEX_AI.GENERATE. Chạy được ngay trong SQL Workshop.
--==============================================================================
BEGIN
  DBMS_OUTPUT.PUT_LINE('== Tổng: ==');
  DBMS_OUTPUT.PUT_LINE(crm_agent_gen_pkg.run_query_lead_metrics());
  DBMS_OUTPUT.PUT_LINE('== Nhóm theo status: ==');
  DBMS_OUTPUT.PUT_LINE(crm_agent_gen_pkg.run_query_lead_metrics(p_group_by => 'status'));
  DBMS_OUTPUT.PUT_LINE('== Nhóm theo owner (fix ORA-00932): ==');
  DBMS_OUTPUT.PUT_LINE(crm_agent_gen_pkg.run_query_lead_metrics(p_group_by => 'owner'));
  DBMS_OUTPUT.PUT_LINE('== Đếm lead HOT: ==');
  DBMS_OUTPUT.PUT_LINE(crm_agent_gen_pkg.run_query_lead_metrics(p_temperature => 'HOT'));
END;
/

--==============================================================================
-- PHẦN 3: ‹XÁC NHẬN API› Gọi APEX_AI.GENERATE với 1 tool inline + hard-exit.
--   Đây là mảnh CẮT lượt-2. Cấu trúc dưới theo mẫu tài liệu 26.1; đối chiếu tên
--   type/tham số thực tế (xem ghi chú ‹XÁC NHẬN API› ở đầu file) rồi bỏ comment chạy.
--
--   Ba điểm cốt lõi (bất biến dù tên API đổi):
--     1) Khai 1 tool "query_lead_metrics" + JSON schema tham số cho model.
--     2) callback tool GỌI crm_agent_gen_pkg.run_query_lead_metrics(...) -> đã ra
--        câu tiếng Việt hoàn chỉnh.
--     3) response handler đặt cờ HARD-EXIT = trả chuỗi tool làm câu trả lời cuối,
--        KHÔNG đẩy kết quả về LLM (bỏ lượt-2).
--==============================================================================
/*
DECLARE
  l_tools    apex_ai.t_tools;                         -- ‹XÁC NHẬN API› tên type
  l_response CLOB;
BEGIN
  -- (1) Khai tool inline. ‹XÁC NHẬN API› cấu trúc t_tool: name/description/
  --     parameters(JSON schema)/callback. Tên trường có thể khác -> chỉnh theo DESC.
  l_tools( 1 ).name        := 'query_lead_metrics';
  l_tools( 1 ).description := 'Đếm/tổng/trung bình/phân bố lead theo nhóm. Trả CON SỐ.';
  l_tools( 1 ).parameters  := q'~{
    "type":"object",
    "properties":{
      "p_group_by":{"type":"string","enum":["status","temperature","source","owner"],
                    "description":"Trục nhóm; bỏ trống = tổng"},
      "p_status":{"type":"string"},
      "p_temperature":{"type":"string"},
      "p_source":{"type":"string"}
    }
  }~';
  -- callback: chạy khi model chọn tool này. Nhận tham số model gửi, trả chuỗi kết quả.
  -- ‹XÁC NHẬN API› cơ chế truyền tham số vào callback (bind JSON / t_tool_arguments).
  -- Ví dụ callback trỏ tới 1 procedure hoặc PL/SQL block gọi:
  --   crm_agent_gen_pkg.run_query_lead_metrics(
  --     p_group_by    => :p_group_by,
  --     p_status      => :p_status,
  --     p_temperature => :p_temperature,
  --     p_source      => :p_source );

  -- (3) response handler hard-exit: procedure theo signature APEX quy định; bên trong
  --     set biến "stop"/"final answer" = kết quả tool -> APEX KHÔNG gọi LLM lượt-2.
  --     ‹XÁC NHẬN API› tên tham số: p_response_handler_procedure (theo tài liệu 26.1).

  l_response := apex_ai.generate(
    p_prompt                      => 'Có bao nhiêu khách hàng tiềm năng?',
    p_system_prompt               => 'Bạn là trợ lý CRM. Chọn ĐÚNG MỘT công cụ cho câu hỏi. Không bịa.',
    p_service_static_id           => 'apex-embed',       -- ‹XÁC NHẬN› service trỏ qwen3-erp (chat), KHÔNG phải bge-m3
    p_tools                       => l_tools,             -- ‹XÁC NHẬN API›
    p_response_handler_procedure  => 'CRM_AGENT_GEN_HARD_EXIT'  -- ‹XÁC NHẬN API›
  );

  DBMS_OUTPUT.PUT_LINE(l_response);
END;
/
*/

--------------------------------------------------------------------------------
-- ĐO SAU KHI CHẠY (report §7 bước 3-4):
--   * tcpdump -w poc.pcap 'tcp port 11434 and src host <apex-ip>' ; đếm số request
--     /api/chat cho 1 câu hỏi -> PHẢI = 1 (luồng cũ = 2).
--   * journalctl -u ollama -f: 1 dòng "prompt eval" duy nhất; không có lượt-2 với
--     marker UNTRUSTED-DATA.
--   * So sánh latency: baseline 2-lượt ~1m7s  vs  PoC 1-lượt (kỳ vọng 15-25s cold).
-- ĐẠT -> mở rộng 6 tool trong l_tools, tái dùng crm_agent_pkg (report §7 bước 5).
--------------------------------------------------------------------------------
