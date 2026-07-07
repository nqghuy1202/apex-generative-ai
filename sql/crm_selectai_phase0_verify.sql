--------------------------------------------------------------------------------
-- crm_selectai_phase0_verify.sql
--------------------------------------------------------------------------------
-- MỤC ĐÍCH (Phase 0 — Verify): Kiểm chứng trên DB THẬT (Oracle 26ai + APEX 26.1)
-- xem Oracle **Select AI (DBMS_CLOUD_AI)** có DÙNG ĐƯỢC trên bản on-prem
-- (non-Autonomous) này với **Ollama local** làm LLM hay không — để quyết định:
--   • Backend NL→SQL chính = Select AI (Option A)  HAY
--   • Tự build metadata-RAG bằng uc_ai + bge-m3 (Option B, đã có trong repo).
--
-- Tham chiếu báo cáo:
--   _bmad-output/planning-artifacts/research/
--       technical-metadata-driven-nl2sql-architecture-research-2026-07-07.md
--   (mục "⚠️ Live-DB Verification Checklist (Phase 0)")
--
-- ⚠️ CHẠY Ở ĐÂU: đây là script chạy **phía DB server** (server 172.25.10.38),
--   nơi Ollama nghe ở localhost:11434. Chạy bằng user có quyền (thường cần
--   EXECUTE trên DBMS_CLOUD_AI + DBMS_CLOUD + DBMS_NETWORK_ACL_ADMIN, hoặc nhờ DBA).
--   KHÔNG chạy từ máy Windows client — Select AI gọi LLM từ trong DB, không phải PC.
--
-- CÁCH DÙNG: chạy **từng STEP một** trong SQL Developer / SQLcl / SQL*Plus với
--   SET SERVEROUTPUT ON. Mỗi STEP độc lập, in chẩn đoán qua DBMS_OUTPUT; một STEP
--   lỗi KHÔNG làm hỏng các STEP khác (đều bọc EXCEPTION).
--
-- QUY ƯỚC (theo repo):
--   • Câu lệnh KHÔNG comment = chạy trực tiếp với GIÁ TRỊ LITERAL (SQL Workshop
--     nghẽn với bind/VARIABLE → ORA-06502). KHÔNG dùng bind ở đây.
--   • Khối trong /* ... */ = mẫu để DÁN chỗ khác hoặc chỉ chạy khi bạn tự điền.
--   • [XÁC NHẬN API] = chi tiết API 26.1/26ai CHƯA chắc chắn, phải đối chiếu tài
--     liệu / DESC trên DB thật trước khi tin. Các blog/doc Select AI phần lớn viết
--     cho Autonomous DB; on-prem có thể khác tên tham số/provider.
--
-- BẢO MẬT: KHÔNG hardcode secret. Mọi credential dùng placeholder — bạn tự thay.
--   Nếu Ollama không cần auth, vẫn phải tạo 1 credential "giả" (nhiều API bắt buộc).
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET PAGESIZE 200
WHENEVER SQLERROR CONTINUE

PROMPT ================================================================
PROMPT  PHASE 0 — SELECT AI / OLLAMA VERIFICATION
PROMPT  Chạy từng STEP; đọc kỹ dòng KẾT LUẬN của mỗi STEP.
PROMPT ================================================================


--------------------------------------------------------------------------------
-- STEP 1 — DBMS_CLOUD_AI có tồn tại & dùng được trên bản DB này không?
--------------------------------------------------------------------------------
-- Nếu package không tồn tại / không có quyền EXECUTE => Select AI KHÔNG khả dụng
-- trên build này => bỏ Option A, đi thẳng Option B (uc_ai metadata-RAG).
PROMPT
PROMPT >>> STEP 1: Kiem tra DBMS_CLOUD_AI (ton tai / quyen EXECUTE)

-- 1a. Package có tồn tại trong DB không (bất kể schema nào sở hữu)?
SELECT owner, object_name, object_type, status
FROM   all_objects
WHERE  object_name IN ('DBMS_CLOUD_AI', 'DBMS_CLOUD')
ORDER  BY object_name, owner;

-- 1b. User hiện tại có quyền EXECUTE trên DBMS_CLOUD_AI không?
SELECT table_name AS object_granted, privilege, grantable
FROM   user_tab_privs
WHERE  table_name IN ('DBMS_CLOUD_AI', 'DBMS_CLOUD')
ORDER  BY table_name;

-- 1c. Liệt kê các thủ tục trong package (DESC-style) để xác nhận có CREATE_PROFILE,
--     SET_PROFILE, GENERATE, DROP_PROFILE... và tên tham số thực tế.
--     [XÁC NHẬN API] So các tham số bên dưới (STEP 3) với kết quả cột này.
SELECT procedure_name
FROM   all_procedures
WHERE  object_name = 'DBMS_CLOUD_AI'
ORDER  BY procedure_name;

-- 1d. Tổng kết STEP 1 bằng PL/SQL (in KẾT LUẬN rõ ràng).
--     Quyền EXECUTE thực tế đã thể hiện ở 1b (user_tab_privs). Khối này chỉ tổng
--     hợp sự tồn tại + gợi ý bước kế; KHÔNG tự chế "test quyền" gây hiểu nhầm.
DECLARE
  l_cnt   PLS_INTEGER;
  l_priv  PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM all_objects
   WHERE object_name = 'DBMS_CLOUD_AI' AND object_type LIKE 'PACKAGE%';

  -- Đếm quyền EXECUTE thực tế (trực tiếp hoặc qua role) — nguồn tin cậy hơn no-op.
  SELECT COUNT(*) INTO l_priv FROM user_tab_privs
   WHERE table_name = 'DBMS_CLOUD_AI' AND privilege = 'EXECUTE';

  DBMS_OUTPUT.PUT_LINE('--- STEP 1 KET LUAN ---');
  IF l_cnt = 0 THEN
    DBMS_OUTPUT.PUT_LINE('  KHONG thay DBMS_CLOUD_AI => Select AI KHONG kha dung.');
    DBMS_OUTPUT.PUT_LINE('  => Ket luan som: DUNG Option B (uc_ai metadata-RAG). Bo qua STEP 2-4.');
  ELSE
    DBMS_OUTPUT.PUT_LINE('  DBMS_CLOUD_AI TON TAI ('||l_cnt||' package object).');
    IF l_priv = 0 THEN
      DBMS_OUTPUT.PUT_LINE('  NHUNG user hien tai CHUA co EXECUTE truc tiep tren DBMS_CLOUD_AI.');
      DBMS_OUTPUT.PUT_LINE('  (Co the van chay neu cap qua role; neu STEP 3 loi quyen => xin DBA GRANT EXECUTE.)');
    ELSE
      DBMS_OUTPUT.PUT_LINE('  User co EXECUTE tren DBMS_CLOUD_AI => tiep tuc STEP 2.');
    END IF;
  END IF;
END;
/


--------------------------------------------------------------------------------
-- STEP 2 — Tiền đề mạng: ACL để DB gọi ra Ollama + Web Credential
--------------------------------------------------------------------------------
-- DB muốn gọi HTTP ra ngoài (kể cả localhost) cần:
--   (a) Network ACL cho host:port đích.
--   (b) Một credential để Select AI/DBMS_CLOUD tham chiếu (dù Ollama không auth).
-- Điền placeholder rồi chạy. KHÔNG để secret thật trong file này.
PROMPT
PROMPT >>> STEP 2: ACL mang + Web Credential (dien placeholder truoc khi chay)

-- 2a. Cấp ACL cho user hiện tại gọi tới Ollama.
--     Ollama nghe localhost trên chinh server DB => host 'localhost' hoac '127.0.0.1'.
--     Neu Ollama da mo 0.0.0.0 thi dung '172.25.10.38'. Chay ca hai cho chac.
DECLARE
  PROCEDURE grant_acl(p_host VARCHAR2) IS
  BEGIN
    DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
      host => p_host,
      ace  => xs$ace_type(
                privilege_list => xs$name_list('http'),
                principal_name => SYS_CONTEXT('USERENV','CURRENT_USER'),
                principal_type => xs_acl.ptype_db));
    DBMS_OUTPUT.PUT_LINE('  ACL http OK cho host: '||p_host);
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('  ACL loi cho '||p_host||': '||SQLERRM);
  END;
BEGIN
  grant_acl('localhost');
  grant_acl('127.0.0.1');
  grant_acl('172.25.10.38');
  COMMIT;
END;
/

-- 2b. Kiểm tra ACL đã có cho user hiện tại.
SELECT host, lower_port, upper_port, ace_order, privilege, principal
FROM   dba_host_aces
WHERE  principal = SYS_CONTEXT('USERENV','CURRENT_USER')
ORDER  BY host, ace_order;
-- (Neu khong co quyen doc DBA_HOST_ACES, bo qua — 2a da co in ket qua.)

-- 2c. Tạo credential cho Ollama.
--     Ollama KHONG yeu cau auth => username/password bat ky (placeholder).
--     [XÁC NHẬN API] Ten credential dung lai o STEP 3 (p_credential_name/credential_name).
/*  === DÁN & ĐIỀN — chay 1 lan ===
BEGIN
  DBMS_CLOUD.CREATE_CREDENTIAL(
    credential_name => 'OLLAMA_CRED',
    username        => 'ollama',                 -- placeholder (Ollama bo qua)
    password        => 'not-used-but-required'   -- placeholder — KHONG phai secret that
  );
END;
/
*/

-- 2d. Xác nhận credential tồn tại.
SELECT credential_name, username, enabled
FROM   user_credentials
WHERE  credential_name = 'OLLAMA_CRED';

PROMPT --- STEP 2 KET LUAN: neu 2b co ACL 'http' va 2d thay OLLAMA_CRED => san sang STEP 3.


--------------------------------------------------------------------------------
-- STEP 3 — Tạo AI Profile trỏ vào Ollama (thử 2 kiểu provider)
--------------------------------------------------------------------------------
-- Đây là điểm RỦI RO #1: on-prem + Ollama. Thử 2 đường, mỗi đường bọc EXCEPTION:
--   (A) provider => 'ollama'                (nếu build ho tro truc tiep)
--   (B) provider => 'openai' + endpoint OpenAI-compatible cua Ollama (.../v1)
-- object_list chi mo CRM_LEADS (bien bao mat = LLM chi thay bang nay).
-- [XÁC NHẬN API] Tên attribute JSON (provider/credential_name/object_list/model/
--   comments/constraints/annotations/host/base_url) phải khớp doc 26ai on-prem.
--   Doi chieu: DBMS_CLOUD_AI CREATE_PROFILE trong all_procedures (STEP 1c) + doc.
PROMPT
PROMPT >>> STEP 3: CREATE_PROFILE (thu provider ollama, roi fallback openai/v1)

-- 3a. Thử provider = 'ollama'.
DECLARE
  l_attrs CLOB;
BEGIN
  BEGIN
    -- Dọn profile cũ nếu chạy lại (bỏ qua lỗi nếu chưa có).
    DBMS_CLOUD_AI.DROP_PROFILE(profile_name => 'CRM_SAI_OLLAMA');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  l_attrs :=
    '{'||
      '"provider": "ollama",'||
      '"credential_name": "OLLAMA_CRED",'||
      -- [XÁC NHẬN API] on-prem Ollama: host localhost, port 11434.
      '"host": "localhost",'||
      '"port": 11434,'||
      '"model": "qwen2.5:3b-instruct",'||   -- hoac "qwen3-erp" neu da build
      '"comments": true,'||
      '"constraints": true,'||
      '"annotations": true,'||
      '"object_list": [ {"owner": "'||SYS_CONTEXT('USERENV','CURRENT_SCHEMA')||'", "name": "CRM_LEADS"} ]'||
    '}';

  DBMS_CLOUD_AI.CREATE_PROFILE(
    profile_name => 'CRM_SAI_OLLAMA',
    attributes   => l_attrs);

  DBMS_OUTPUT.PUT_LINE('  [A] provider=ollama: CREATE_PROFILE OK (CRM_SAI_OLLAMA).');
EXCEPTION WHEN OTHERS THEN
  DBMS_OUTPUT.PUT_LINE('  [A] provider=ollama: LOI => '||SQLERRM);
  DBMS_OUTPUT.PUT_LINE('      (Neu bao provider khong hop le => build nay chua ho tro "ollama" native. Xem [B].)');
END;
/

-- 3b. Fallback provider = 'openai' trỏ vào endpoint OpenAI-compat cua Ollama (.../v1).
DECLARE
  l_attrs CLOB;
BEGIN
  BEGIN
    DBMS_CLOUD_AI.DROP_PROFILE(profile_name => 'CRM_SAI_OPENAI');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  -- [XÁC NHẬN API] Cách trỏ base URL tuỳ phiên bản: co the la "provider_endpoint",
  --   "host", hoac "base_url". Thu "provider_endpoint" truoc; neu loi, doi sang key khac.
  l_attrs :=
    '{'||
      '"provider": "openai",'||
      '"credential_name": "OLLAMA_CRED",'||
      '"provider_endpoint": "172.25.10.38:11434/v1",'||   -- [XÁC NHẬN API]
      '"model": "qwen2.5:3b-instruct",'||
      '"comments": true,'||
      '"constraints": true,'||
      '"annotations": true,'||
      '"object_list": [ {"owner": "'||SYS_CONTEXT('USERENV','CURRENT_SCHEMA')||'", "name": "CRM_LEADS"} ]'||
    '}';

  DBMS_CLOUD_AI.CREATE_PROFILE(
    profile_name => 'CRM_SAI_OPENAI',
    attributes   => l_attrs);

  DBMS_OUTPUT.PUT_LINE('  [B] provider=openai (Ollama /v1): CREATE_PROFILE OK (CRM_SAI_OPENAI).');
EXCEPTION WHEN OTHERS THEN
  DBMS_OUTPUT.PUT_LINE('  [B] provider=openai (/v1): LOI => '||SQLERRM);
  DBMS_OUTPUT.PUT_LINE('      (Thu doi "provider_endpoint" -> "host"/"base_url" theo doc build nay.)');
END;
/

-- 3c. Liệt kê profile đã tạo được.
--     [XÁC NHẬN API] View co the ten USER_CLOUD_AI_PROFILES hoac tuong tu.
/*  === Neu view ton tai, bo comment de xem ===
SELECT profile_name, status FROM user_cloud_ai_profiles ORDER BY profile_name;
*/

PROMPT --- STEP 3 KET LUAN: ghi nho profile nao tao THANH CONG ([A] hay [B]) de dung o STEP 4.


--------------------------------------------------------------------------------
-- STEP 4 — Chạy thử NL→SQL qua Select AI + đo thời gian
--------------------------------------------------------------------------------
-- Đổi tên profile bên dưới cho khớp profile TẠO THÀNH CÔNG ở STEP 3
-- (CRM_SAI_OLLAMA hoac CRM_SAI_OPENAI).
-- showsql = chi sinh SQL (nhe, an toan). narrate = chay + dien giai.
-- [XÁC NHẬN API] Cu phap "SELECT AI <action> <prompt>" la cu phap Autonomous.
--   Tren on-prem co the phai goi DBMS_CLOUD_AI.GENERATE(prompt, profile, action).
--   Duoi day dung GENERATE (chac chan chay duoc trong PL/SQL) + note cu phap SQL.
PROMPT
PROMPT >>> STEP 4: NL->SQL test (showsql, roi narrate) + do latency

DECLARE
  l_profile   VARCHAR2(30) := 'CRM_SAI_OPENAI';   -- <== SUA cho khop STEP 3
  l_question  VARCHAR2(400) := 'có bao nhiêu dòng trong crm_leads?';
  l_out       CLOB;
  l_t0        TIMESTAMP;
  l_secs      NUMBER;

  FUNCTION run_action(p_action VARCHAR2) RETURN CLOB IS
    l_r CLOB;
  BEGIN
    -- [XÁC NHẬN API] chu ky GENERATE: (prompt, profile_name, action). Doi chieu STEP 1c.
    l_r := DBMS_CLOUD_AI.GENERATE(
             prompt       => l_question,
             profile_name => l_profile,
             action       => p_action);
    RETURN l_r;
  END;
BEGIN
  DBMS_OUTPUT.PUT_LINE('  Profile dung: '||l_profile);
  DBMS_OUTPUT.PUT_LINE('  Cau hoi     : '||l_question);

  -- 4a. showsql — chỉ xem SQL sinh ra (khong chay).
  BEGIN
    l_t0   := SYSTIMESTAMP;
    l_out  := run_action('showsql');
    l_secs := EXTRACT(SECOND FROM (SYSTIMESTAMP - l_t0))
            + EXTRACT(MINUTE FROM (SYSTIMESTAMP - l_t0)) * 60;
    DBMS_OUTPUT.PUT_LINE('  [showsql] '||ROUND(l_secs,1)||'s => SQL sinh ra:');
    DBMS_OUTPUT.PUT_LINE('  '||SUBSTR(l_out,1,3900));
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('  [showsql] LOI => '||SQLERRM);
  END;

  -- 4b. narrate — chay va dien giai ket qua bang ngon ngu tu nhien.
  BEGIN
    l_t0   := SYSTIMESTAMP;
    l_out  := run_action('narrate');
    l_secs := EXTRACT(SECOND FROM (SYSTIMESTAMP - l_t0))
            + EXTRACT(MINUTE FROM (SYSTIMESTAMP - l_t0)) * 60;
    DBMS_OUTPUT.PUT_LINE('  [narrate] '||ROUND(l_secs,1)||'s => Tra loi:');
    DBMS_OUTPUT.PUT_LINE('  '||SUBSTR(l_out,1,3900));
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('  [narrate] LOI => '||SQLERRM);
  END;

  DBMS_OUTPUT.PUT_LINE('--- STEP 4 KET LUAN ---');
  DBMS_OUTPUT.PUT_LINE('  So sanh latency narrate voi crm_nl2sql_pkg.ask (~1.8-2.4s WARM).');
  DBMS_OUTPUT.PUT_LINE('  Neu >> nhieu => auto table-detection co the them 1 luot LLM (xem STEP 5).');
END;
/

/*  === Cú pháp SQL "SELECT AI" (neu build ho tro) — DAN vao SQL Developer de thu ===
    Truoc do phai: EXEC DBMS_CLOUD_AI.SET_PROFILE('CRM_SAI_OPENAI');
    -- chi sinh SQL:
    SELECT AI showsql có bao nhiêu dòng trong crm_leads;
    -- chay + dien giai:
    SELECT AI narrate có bao nhiêu dòng trong crm_leads;
*/


--------------------------------------------------------------------------------
-- STEP 5 — Đo SỐ LƯỢT gọi LLM (không đo được từ SQL — làm trên server)
--------------------------------------------------------------------------------
-- Latency CPU bi chi phoi boi so luot goi LLM. Select AI 26ai co "auto table
-- detection" — can biet no ton 1 hay 2 luot LLM cho mot cau hoi.
-- Chay TREN SERVER 172.25.10.38 (bash), song song luc chay STEP 4:
/*
  # Xem log Ollama truc tiep, dem so dong "POST /api/chat" hoac "/v1/chat/completions":
  sudo journalctl -u ollama -f | grep -E "POST /(api|v1)"

  # Hoac bat goi qua tcpdump roi dem request (loc theo IP goi = chinh DB/localhost):
  sudo tcpdump -n -i lo -w /tmp/sai.pcap 'tcp port 11434'
  # ...chay STEP 4... roi Ctrl-C, dem so request:
  strings /tmp/sai.pcap | grep -c -E "POST /(api|v1)/"
*/
-- KET LUAN STEP 5:
--   • 1 luot / cau hoi  => Select AI dat tieu chi 1-call, uu tien Option A.
--   • >=2 luot / cau hoi => can can nhac: chi dung cho SLOW path, giu Option B cho FAST path.
PROMPT >>> STEP 5: xem huong dan comment de dem so luot LLM tren server.


--------------------------------------------------------------------------------
-- STEP 6 — Ghi chú read-only user + DỌN DẸP
--------------------------------------------------------------------------------
-- (Ghi chu) Ngoài verify, khi trien khai that, generated SQL nen chay bang MOT
-- user DB CHI-DOC (chi GRANT SELECT tren cac view expose) — DB se tu choi moi
-- DML ao. Select AI cung nen dung profile/credential cua user quyen thap.
--
-- DỌN DẸP: xoá profile + credential tao trong luc verify (bo comment de chay).
PROMPT
PROMPT >>> STEP 6: Cleanup (bo comment cac lenh duoi khi da verify xong)

/*  === CLEANUP — chay khi da lay ket qua ===
BEGIN
  BEGIN DBMS_CLOUD_AI.DROP_PROFILE(profile_name => 'CRM_SAI_OLLAMA'); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN DBMS_CLOUD_AI.DROP_PROFILE(profile_name => 'CRM_SAI_OPENAI'); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN DBMS_CLOUD.DROP_CREDENTIAL(credential_name => 'OLLAMA_CRED');  EXCEPTION WHEN OTHERS THEN NULL; END;
  DBMS_OUTPUT.PUT_LINE('  Cleanup xong.');
END;
/
*/

PROMPT
PROMPT ================================================================
PROMPT  KET LUAN PHASE 0 (tong hop tay sau khi chay):
PROMPT   1) DBMS_CLOUD_AI co dung duoc?           (STEP 1)
PROMPT   2) Provider Ollama nao chay: ollama / openai-v1?  (STEP 3)
PROMPT   3) Latency narrate vs crm_nl2sql_pkg?    (STEP 4)
PROMPT   4) So luot LLM / cau hoi = 1 hay >=2?    (STEP 5)
PROMPT  => Neu (1)=Yes, (2) co provider chay, (4)=1 luot va (3) chap nhan duoc:
PROMPT     CHON Option A (Select AI) lam backend chinh cho long-tail.
PROMPT     Neu khong: giu Option B (uc_ai metadata-RAG) — da chay tot trong repo.
PROMPT ================================================================
