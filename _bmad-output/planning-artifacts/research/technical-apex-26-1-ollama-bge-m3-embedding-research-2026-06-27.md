# Technical Research — APEX 26.1 gọi embedding bge-m3:latest qua Ollama

**Date:** 2026-06-27 · **Researcher:** Claude (bmad-technical-research) · **For:** Gia Huy
**Stack:** Oracle APEX 26.1 + Oracle Database 26ai · Ollama @ http://172.25.10.38:11434 · model bge-m3:latest (dim 1024)

---

## Phần A — Chẩn đoán gốc rễ

- **APEX 26.1 CÓ hỗ trợ embedding native qua Generative AI Service** (provider "Ollama" và "OpenAI-Compatible"). Vector Provider có thể là *Local Database ONNX Model* hoặc *Generative AI Service*. → Giả thuyết ban đầu "GenAI Service chỉ là chat" **SAI với 26.1**; embedding đi qua chính GenAI Service.
- **Smoking gun (tcpdump) là kết quả của nút "Test Connection", KHÔNG phải lời gọi embedding thật.** Cả hai lần test (`/v1/embeddings` và `/api/embed`) đều nhận **cùng một payload chat** `{"model":...,"messages":[{"role":"user","content":[{"type":"text","text":"Hello"}]}]}`. Việc cùng một body chat được gửi tới hai endpoint khác nhau chứng tỏ **Test Connection luôn gửi một probe kiểu chat-completions ("Hello"), bất kể service sẽ dùng cho embedding.**
- **bge-m3 là model EMBEDDING-ONLY** — nó không phục vụ `/chat`. Khi probe chat "Hello" tới nó, Ollama trả `400 invalid input`. Đây là lỗi **đúng như mong đợi cho một probe sai loại**, không có nghĩa là embedding sẽ hỏng.
- **Base URL nhiều khả năng bị nhập sai thành full path.** tcpdump cho thấy request đập thẳng vào `/v1/embeddings`. Với APEX, Base URL phải là **gốc** (`/v1` cho OpenAI-compatible, hoặc host:port cho Ollama) — APEX **tự nối** `/chat/completions` hoặc `/embeddings` (`/api/chat` / `/api/embed`). Nhập sẵn `/v1/embeddings` làm lệch đường dẫn.
- **Kết luận:** Lỗi không chặn việc dùng embedding. Vấn đề là (1) đang đánh giá sai dựa trên Test Connection vốn chỉ kiểm tra chat, và (2) có thể nhập Base URL sai.

## Phần B — Giải pháp native khuyến nghị

1. **Workspace Utilities → Generative AI Services → Create.** [nguồn: Oracle docs 18.9.2.1]
2. **AI Provider:** chọn **Ollama** (khuyến nghị) — APEX tự nối `/api/embed` (body `{"model","input"}`) cho embedding và `/api/chat` cho chat. [docs: "Ollama … exposes /api/chat for chat and /api/embed for embeddings"]
3. **Base URL:** `http://172.25.10.38:11434` — **chỉ host:port, KHÔNG kèm `/v1/embeddings` hay `/api/embed`.** (Nếu chọn provider *OpenAI-Compatible* thì Base URL là `http://172.25.10.38:11434/v1`, cũng KHÔNG kèm `/embeddings`.) [docs: "you don't need to enter the full path … APEX automatically adds the last part"]
4. **AI Model:** `bge-m3:latest`. APEX chỉ có MỘT trường "AI Model" dùng chung chat + embedding (không có trường riêng cho embedding). [docs 18.9.2.1]
5. **Credential / API Key:** Ollama không cần auth; Bearer token `123456789huy` bạn đặt là tuỳ ý — có thể bỏ hoặc giữ, Ollama bỏ qua.
6. **Về Test Connection:** **đừng coi việc nó fail là chặn.** Vì probe là chat mà bge-m3 không chat được, nó sẽ luôn 400. Hai cách xử lý:
   - (a) Bỏ qua Test Connection, tiến thẳng tới wizard AI Vector Search và dùng service này làm **Vector/Embedding provider** — nơi APEX gửi đúng body `{"model","input"}`. [chưa xác minh: hành vi chính xác của wizard khi service test fail]
   - (b) Nếu APEX 26.1 **chặn lưu** khi test fail [chưa xác minh]: tạm thời đặt AI Model = một model chat (vd `llama3`) để pass test & lưu, sau đó đổi lại sang `bge-m3:latest`; **hoặc** tạo **2 service riêng** — một chat (để pass App Builder) và một embedding (`bge-m3`) chỉ dùng trong Vector Search.
7. **Trong AI Vector Search wizard:** chọn Embedding/Vector provider = Generative AI Service vừa tạo; **vector dimension = 1024** (đúng với bge-m3). [chưa xác minh tên trường UI chính xác trong wizard 26.1]
8. **Kiểm chứng thật:** chạy lại tcpdump khi *tạo embedding thật* (không phải Test Connection). Body đúng phải là `{"model":"bge-m3:latest","input":"..."}` tới `/api/embed`. Nếu thấy đúng dạng này và HTTP 200 → đã xong.

> ⚠️ Điểm còn [chưa xác minh] tập trung ở: liệu APEX 26.1 có cho lưu service khi Test Connection fail, và tên trường chính xác trong AI Vector Search wizard. Cần xác nhận trực tiếp trên instance.

## Phần C — Phương án dự phòng (nếu B bất khả thi)

- **(a) DBMS_VECTOR / APEX_WEB_SERVICE gọi REST tới Ollama** — kiểm soát toàn bộ body. Bài ORACLE-BASE (10/06/2026) dùng `APEX_WEB_SERVICE.make_rest_request(p_url => base||'/api/embeddings', p_body => '{"model":"...","prompt":"..."}')`. Lưu ý endpoint cũ `/api/embeddings` dùng field `prompt`; endpoint mới `/api/embed` dùng `input`.
  - ✅ Ưu: chắc chắn chạy, kiểm soát body tuyệt đối. ❌ Nhược: tự code, KHÔNG dùng wizard native (đi ngược mục tiêu).
- **(b) ONNX import in-database + `VECTOR_EMBEDDING`** — tải model ONNX vào DB 26ai, sinh vector ngay trong DB, không cần Ollama.
  - ✅ Ưu: nhanh, không phụ thuộc mạng/Ollama, tích hợp sâu Vector Search. ❌ Nhược: bge-m3 phải export sang ONNX đúng chuẩn; quy trình import nặng hơn.
- **Khuyến nghị:** Ưu tiên Phần B (Ollama provider). Nếu cần ổn định production lâu dài và chấp nhận bỏ Ollama → (b) ONNX in-DB là mượt nhất với wizard.

## Phần D — Nguồn

- [Oracle APEX 26.1 Docs — 18.9.2.1 Creating Generative AI Service Objects](https://docs.oracle.com/en/database/oracle/apex/26.1/htmdb/creating-generative-ai-service-objects.html)
- [Oracle Blog — Expanding AI Choice / Out-of-the-Box AI Providers in APEX 26.1](https://blogs.oracle.com/apex/expanding-ai-choice-with-out-of-the-box-support-for-major-ai-providers-in-oracle-apex-26-1)
- [Oracle AI Vector Search User's Guide — Generate Embeddings (26)](https://docs.oracle.com/en/database/oracle/oracle-database/26/vecse/generate-embeddings.html)
- [ORACLE-BASE — AI Vector Search: Generating vectors outside the DB using Ollama (10/06/2026)](https://oracle-base.com/blog/2026/06/10/ai-vector-search-generating-vectors-outside-of-the-database-using-ollama-and-embeddinggemma/)
- [APEX App Lab — When APEX meets Open source LLMs (base URL /v1 behavior)](https://blog.apexapplab.dev/apex-in-the-ai-era)
- [Ollama Docs — OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility)
