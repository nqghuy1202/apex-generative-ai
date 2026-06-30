---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments: []
workflowType: 'research'
lastStep: 6
research_type: 'technical'
research_topic: 'CRM_LEADS AI Agent setup (Oracle APEX 26.1 + DB 26ai + Ollama vector RAG/tool-calling)'
research_goals: 'Xác định cách thiết lập bảng CRM_LEADS (>500k dòng) để xây dựng AI Agent tối ưu cho sale + quản lý: tra cứu lead, thống kê pipeline, tìm ngữ nghĩa, gợi ý hành động bán hàng'
user_name: 'Gia Huy'
date: '2026-06-30'
web_research_enabled: true
source_verification: true
---

# Research Report: technical

**Date:** 2026-06-30
**Author:** Gia Huy
**Research Type:** technical

---

## Research Overview

Nghiên cứu này xác định cách thiết lập bảng `CRM_LEADS` (khách hàng tiềm năng, module CRM, quy mô >500k dòng) để xây dựng một AI Agent tối ưu trên Oracle APEX 26.1 + DB 26ai + Ollama, phục vụ cả nhân viên sale lẫn quản lý qua bốn năng lực: tra cứu lead, thống kê pipeline, tìm kiếm ngữ nghĩa và gợi ý hành động bán hàng.

Kết quả chính (web-verified, 2026): (1) phân loại 40+ cột thành ba nhóm Semantic/Structured/Identity với chỉ nhóm Semantic được đưa vào câu văn embedding tiếng Việt có dấu; (2) kiến trúc **4 tool hẹp theo việc** (`lookup_lead_exact`, `search_leads_semantic`, `query_lead_metrics`, `suggest_lead_actions`) — nằm trong ngưỡng an toàn ≤8 tool và giảm rủi ro chọn sai tool của qwen2.5; (3) ở quy mô >500k, **pre-filter trước RAG** (Oracle 26ai `PRE_W` trên Local Partitioned HNSW) là đòn bẩy hiệu năng quyết định; (4) chuẩn hóa MLE cho lookup nhưng giữ dấu cho embedding; (5) bộ rủi ro & gotcha (ORA-20960, hallucinate tool-call, NULL embedding, phân quyền theo owner) kèm cách giảm thiểu.

Chi tiết đầy đủ ở Executive Summary và các phần phân tích bên dưới (Technology Stack, Tool Architecture & RAG Flow, Architectural Patterns, Implementation). Đầu ra giới hạn ở báo cáo nghiên cứu — triển khai SQL/PLSQL là giai đoạn kế tiếp.

---

<!-- Content will be appended sequentially through research workflow steps -->

## Technical Research Scope Confirmation

**Research Topic:** CRM_LEADS AI Agent setup (Oracle APEX 26.1 + DB 26ai + Ollama vector RAG/tool-calling)
**Research Goals:** Thiết lập bảng CRM_LEADS (>500k dòng) để xây AI Agent tối ưu cho sale + quản lý — tra cứu lead, thống kê pipeline, tìm ngữ nghĩa, gợi ý hành động bán hàng.

**Technical Research Scope (6 parts):**

1. Column classification — Semantic (embedding) vs Structured (filter/aggregate)
2. Tool architecture — 4 tools: lookup_lead_exact, search_leads_semantic (pre-filter), query_lead_metrics, suggest_lead_actions
3. Data normalization (MLE) — diacritics, phone, email, enum status/temperature
4. Index & performance at >500k — HNSW, b-tree, pre-filter before RAG, partition, incremental embedding
5. User question space — sale & manager questions mapped to tools
6. Risks & gotchas — ORA-20960, NULL embedding, wrong tool selection, CPU latency

**Research Methodology:**

- Current web data with rigorous source verification
- Multi-source validation for critical technical claims
- Confidence level framework for uncertain information
- Output: research report only (no SQL generation)

**Scope Confirmed:** 2026-06-30

---

## Technology Stack Analysis

Stack đã cố định trong dự án; phần này **xác minh năng lực hiện hành** của từng lớp công nghệ so với yêu cầu CRM_LEADS >500k dòng (web-verified, 2026).

### Database & Vector layer — Oracle AI Database 26ai

- **HNSW index** là index vector nhanh nhất trong 26ai (in-memory multi-layer graph). Điểm mới quan trọng của 26ai: **cho phép DML trên bảng có HNSW index** và truy vấn vector cho **kết quả nhất quán giao dịch (transactionally consistent)** theo read snapshot — phù hợp bảng CRM_LEADS biến động liên tục.
- **Pre-filter (lọc trước RAG)** được hỗ trợ chính thức qua trường `FILTER_BY` / filter types: **`PRE_W`** (pre-filter có join-back, **chỉ HNSW**) và **`PRE_WO`** (pre-filter không join-back, cả HNSW lẫn IVF). Đây là nền tảng kỹ thuật cho yêu cầu "lọc status/owner trước khi vector search" ở quy mô lớn.
- **Included columns** trong Neighbor Partition (IVF) index: nhúng cột không-vector vào index để lọc thuộc tính **không cần truy cập bảng gốc** qua join đắt đỏ.
- **Local Partitioned HNSW Vector Index**: tăng scalability + tăng tốc nhờ **partition pruning** — khuyến nghị cho enterprise workload lớn.
- **Hybrid Vector Index** + `DBMS_HYBRID_VECTOR.SEARCH`: kết hợp vector-distance và full-text trong một truy vấn, cho phép thêm `WHERE` trên cột ngoài cột index.
- Quy tắc quy mô (web): khởi điểm số partition ≈ **căn bậc hai tổng số dòng**; cân nhắc **IVF khi bảng > 50 triệu dòng** hoặc khi Vector Memory Pool bị giới hạn. → Với ~500k–vài triệu dòng, **HNSW (local partitioned) vẫn phù hợp**; IVF là phương án dự phòng khi RAM pool căng.
_Confidence: High. Sources below._

### Application layer — Oracle APEX 26.1

- APEX 26.1 chuyển từ "prompt screen thụ động" sang **AI Agents chủ động** reason qua yêu cầu người dùng và hành động qua **AI Tools đã được duyệt**, dùng native **Function/Tool Calling** của LLM.
- **Generative AI Tool plug-in type** (mới): xây tool tùy biến tái sử dụng. APEX quản lý execution flow: chuẩn bị context → dispatch tool call → thực thi tool → xử lý kết quả → soạn câu trả lời. → Khớp trực tiếp kiến trúc 4 tool ở Phần 2.
- Hỗ trợ nhiều provider out-of-the-box (OCI GenAI, OpenAI, Cohere, Gemini) — nhưng dự án dùng **Ollama (CPU server B)** qua Generative AI Service.
_Confidence: High._

### Generation model layer — Ollama + Qwen2.5-instruct (CPU)

- Qwen2.5 / Qwen2.5-coder **native tool calling** được Ollama hỗ trợ; **bắt buộc bản instruct** (không dùng base) — khớp quyết định dự án (`qwen2.5:3b-instruct`, đặt tên `qwen3-erp`).
- ⚠️ **Rủi ro đã ghi nhận trên cộng đồng:** Qwen2.5 tool-call có thể **hallucinate (mẫu "Maybe")** không theo đúng JSON schema, đặc biệt khi có **nhiều tool**. Đây là rủi ro trực tiếp cho kiến trúc 4 tool → xử lý ở Phần 6 (escalate 3b→7b-instruct, mô tả tool rõ ràng, giảm số tool đồng thời).
- Khuyến nghị cộng đồng: model lớn hơn / Gemma cho độ tin cậy tool-call tối đa — **đối chiếu** với ràng buộc CPU-only của dự án (tốc độ vs độ chính xác).
_Confidence: Medium-High (issue tool-call mang tính giai thoại nhưng nhất quán nhiều nguồn)._

### Embedding layer — bge-m3 (1024, COSINE) qua Ollama

- Giữ nguyên theo milestone đã verify (`apex-embed` static id). Không thay đổi ở nghiên cứu này; chỉ lưu ý chi phí embedding lại khi >500k dòng (Phần 4).

**Sources:**
- [Oracle AI Database 26ai — Vector Indexes (New Features)](https://docs.oracle.com/en/database/oracle/oracle-database/26/nfcoa/vector-indexes.html)
- [Oracle AI Vector Search User's Guide 26ai](https://docs.oracle.com/en/database/oracle/oracle-database/26/vecse/ai-vector-search-users-guide.pdf)
- [CREATE VECTOR INDEX (26ai SQL Ref)](https://docs.oracle.com/en/database/oracle/oracle-database/26/sqlrf/create-vector-index.html)
- [Included columns for IVF indexes](https://docs.oracle.com/en/database/oracle/oracle-database/26/vecse/included-columns-ivf-indexes.html)
- [Hybrid Vector Index — full-text + semantic (Oracle Coretec)](https://blogs.oracle.com/coretec/hybrid-vector-index-the-combination-of-full-text-and-semantic-vector-search)
- [Vector Indexes in 26ai — HNSW & IVF under the hood](https://dbadataverse.com/tech/letstalkoracle/2026/03/vector-indexes-in-oracle-ai-database-26ai-how-hnsw-and-ivf-work-under-the-hood)
- [Announcing Oracle APEX 26.1 GA](https://blogs.oracle.com/apex/announcing-oracle-apex-261)
- [Build Ad-hoc AI Agents Entirely in PL/SQL (APEX 26.1)](https://blogs.oracle.com/apex/build-ad-hoc-ai-agents-entirely-in-pl-sql)
- [Qwen Function Calling docs](https://qwen.readthedocs.io/en/latest/framework/function_call.html)
- [Ollama issue #7051 — Qwen2.5 tool-call hallucination](https://github.com/ollama/ollama/issues/7051)

---

## Integration Patterns Analysis — Tool Architecture & RAG Flow

Trong dự án, "integration patterns" = cách AI Agent (APEX) **tích hợp với DB qua các Tool** và **với Ollama qua tool-calling**. Phần này định nghĩa **4 tool** (Phần 2 lộ trình) dựa trên best practice 2026.

### Nguyên tắc thiết kế tool (web-verified)

- **Tool hẹp, theo từng việc (job-specific) > wrapper API rộng.** Nếu agent đăng ký >8 tool là dấu hiệu lỗi thiết kế. → **4 tool** là vùng an toàn.
- **Mô tả tool rõ ràng, chính xác** giúp giảm tới **70% số lần gọi sai** (tối ưu joint instruction + tool description). → Đầu tư mạnh vào `description` của mỗi tool, viết **tiếng Việt có dấu** (theo quy ước dự án).
- **Đặt budget rõ ràng** (số step, thời gian, token, số tool-call); vượt budget thì dừng & escalate thay vì lặp vô hạn.
- **Log mọi tool-call** (input, output, latency, success) để eval và debug.
_Confidence: High._

### Chiến lược lọc RAG — Pre-filter (web-verified)

- **Pre-filter chính xác hơn** post-filter vì vector search chỉ xét ứng viên trong "allow list"; **HNSW là một trong số ít thuật toán tương thích filtering** — trùng khớp với `PRE_W`/`PRE_WO` của Oracle 26ai.
- Post-filter rủi ro **kết quả rỗng/thiếu** khi tương quan thấp.
- **Best practice:** kết hợp — pre-filter rộng theo metadata (status/owner/ngày) rồi vector search. → Áp dụng trực tiếp cho `search_leads_semantic` ở quy mô >500k.
_Confidence: High._

### Bộ 4 Tool đề xuất (chữ ký + mô tả)

| Tool | Mục đích | Loại truy vấn | Cột dùng |
|------|----------|---------------|----------|
| `lookup_lead_exact` | Tra cứu chính xác 1 lead | B-tree equality trên cột chuẩn hóa | `cle_code`, `phone`, `email`, `contact_phone`, `tax_id` |
| `search_leads_semantic` | Tìm lead theo mô tả tự do | Vector RAG **+ pre-filter** | embedding text + filter `status/temperature/emp_id/co_id` |
| `query_lead_metrics` | Thống kê pipeline | GROUP BY aggregate | `status`, `temperature`, `source`, `owner`, `score`, ngày |
| `suggest_lead_actions` | Gợi ý ưu tiên chăm sóc | SQL điều kiện + ranking | `next_action_date`, `last_activity_date`, `temperature`, `score`, `status` |

**1) `lookup_lead_exact`** — tra cứu định danh, KHÔNG dùng vector (tránh lỗi exact-lookup đã gặp ở customers agent — xem `customers-agent-tool-architecture`).
```
lookup_lead_exact(
  p_search_type  IN VARCHAR2,  -- 'code'|'phone'|'email'|'tax_id'
  p_search_value IN VARCHAR2   -- giá trị (sẽ được normalize trước khi so khớp)
) → bản ghi lead đầy đủ (status, owner, next_action, last_activity_date...)
```
Mô tả cho LLM: *"Dùng khi người dùng cung cấp mã lead, số điện thoại, email hoặc mã số thuế CỤ THỂ để tra cứu chính xác một khách hàng tiềm năng. KHÔNG dùng cho câu hỏi mô tả chung chung."*

**2) `search_leads_semantic`** — vector RAG có pre-filter bắt buộc ở quy mô lớn.
```
search_leads_semantic(
  p_query        IN VARCHAR2,             -- mô tả tự do của người dùng
  p_status       IN VARCHAR2 DEFAULT NULL,-- pre-filter (PRE_W/PRE_WO)
  p_owner_emp_id IN NUMBER   DEFAULT NULL,
  p_top_n        IN NUMBER   DEFAULT 10
) → danh sách lead xếp theo vector_distance (FETCH APPROX FIRST n ROWS ONLY)
```
Mô tả cho LLM: *"Dùng khi người dùng mô tả nhu cầu/đặc điểm lead bằng ngôn ngữ tự nhiên (ngành nghề, nguồn, ghi chú giới thiệu) thay vì định danh chính xác. Có thể lọc trước theo trạng thái và người phụ trách."*

**3) `query_lead_metrics`** — aggregate, tránh bug GROUP BY ép buộc (xem `query-customer-metrics-groupby-bug`).
```
query_lead_metrics(
  p_group_by   IN VARCHAR2,  -- 'status'|'temperature'|'source'|'owner'
  p_metric     IN VARCHAR2 DEFAULT 'count', -- 'count'|'sum_score'|'avg_score'
  p_filter_col IN VARCHAR2 DEFAULT NULL,
  p_filter_val IN VARCHAR2 DEFAULT NULL
) → bảng tổng hợp
```
Mô tả cho LLM: *"Dùng khi người dùng hỏi SỐ LƯỢNG, TỔNG, TRUNG BÌNH hoặc phân bố lead theo nhóm (trạng thái, nhiệt độ, nguồn, người phụ trách). Đây là câu hỏi thống kê, KHÔNG phải tra cứu từng lead."*

**4) `suggest_lead_actions`** — đặc thù bán hàng, phục vụ cả sale lẫn quản lý.
```
suggest_lead_actions(
  p_owner_emp_id IN NUMBER  DEFAULT NULL,  -- sale: của tôi; quản lý: theo team
  p_mode         IN VARCHAR2 DEFAULT 'overdue', -- 'overdue'|'hot'|'cold'|'today'
  p_top_n        IN NUMBER   DEFAULT 10
) → danh sách lead cần hành động + lý do ưu tiên
```
Mô tả cho LLM: *"Dùng khi người dùng hỏi 'nên chăm sóc lead nào trước', 'lead nào quá hạn next action', 'lead nóng/nguội', 'việc hôm nay'. Xếp ưu tiên theo ngày hành động kế tiếp, lần chăm sóc gần nhất, nhiệt độ và điểm số."*

### Luồng tích hợp end-to-end

```
User (APEX) → AI Agent (APEX 26.1 GenAI Tool plug-in)
   → Ollama qwen3-erp (tool-calling, chọn 1 trong 4 tool)
   → APEX dispatch tool → PL/SQL thực thi trên DB 26ai
        • lookup/metrics/suggest: SQL thuần (b-tree/aggregate)
        • semantic: apex_ai.get_vector_embeddings(p_query,'apex-embed')
          → VECTOR_DISTANCE + FILTER_BY (PRE_W) trên HNSW
   → kết quả trả về Agent → soạn câu trả lời tiếng Việt
```

**Sources:**
- [Tool Calling Explained: Core of AI Agents (2026) — Composio](https://composio.dev/content/ai-agent-tool-calling-guide)
- [AI Agent Tool Use Best Practices — MLflow](https://mlflow.org/articles/ai-agent-tool-use-best-practices-for-practitioners/)
- [LLM Agent Evaluation Metrics 2026 — Confident AI](https://www.confident-ai.com/blog/llm-agent-evaluation-complete-guide)
- [Pre and Post Filtering in Vector Search with Metadata & RAG](https://ai.plainenglish.io/pre-and-post-filtering-in-vector-search-with-metadata-and-rag-pipelines-fc4c58fff2be)
- [Filtering in Vector Search with Metadata and RAG Pipelines — Turso](https://turso.tech/blog/filtering-in-vector-search-with-metadata-and-rag-pipelines)

---

## Architectural Patterns and Design

### Data Architecture — Phân loại cột Semantic vs Structured

**Nguyên tắc (web-verified):** KHÔNG embed dữ liệu cấu trúc thô (số, mã, cột rỗng dịch kém sang vector). Phải **dựng câu văn có nghĩa** từ các cột đã chọn rồi mới embed; có thể làm giàu bằng giá trị mẫu/nhãn cột.

Phân loại 40+ cột của `CRM_LEADS`:

**Nhóm A — Semantic (đưa vào văn bản embedding):** mô tả định tính, ngôn ngữ tự nhiên.
- `cle_name`, `customer`, `owner` (tên), `source`, `cle_type`, `introduce_type`, `introduce_person`, `introduce_company`, `introduce_note`, `next_action`, `contact_name`, `contact_position`, `contact_department`, `disqualify_reason`.

**Nhóm B — Structured (filter / aggregate / pre-filter, KHÔNG embed):** giá trị rời rạc, số, ngày, khóa.
- Enum: `status`, `temperature`, `cle_type`, `introduce_type`.
- Số/điểm: `score`, `cle_id`, `ven_id`, `emp_id`, `co_id`, `oun_id`, `copp_id`.
- Ngày: `create_date`, `modify_date`, `last_activity_date`, `next_action_date`.

**Nhóm C — Identity (lookup chính xác, chuẩn hóa, KHÔNG embed):**
- `cle_code`, `phone`, `email`, `contact_phone`, `intro_person_phone`, `tax_id`.

**Mẫu câu văn embedding đề xuất (tiếng Việt có dấu):**
> *"Khách hàng tiềm năng [cle_name] thuộc công ty [customer], loại [cle_type], nguồn [source]. Người liên hệ [contact_name] - [contact_position], phòng [contact_department]. Giới thiệu bởi [introduce_person] ([introduce_company]). Hành động tiếp theo: [next_action]. Ghi chú: [introduce_note]."*

→ Chỉ embed Nhóm A; gắn Nhóm B làm **included columns / filter predicate**; Nhóm C tra cứu b-tree.
_Confidence: High._

### Chuẩn hóa dữ liệu (MLE) — Phần 3

Tái dùng pattern MLE `text_normalize` (đã có ở `sql/mle_text_normalize.sql`, xem `customers-agent-tool-architecture`):

- **Diacritics:** tạo cột/biểu thức chuẩn hóa bỏ dấu + lowercase cho `cle_name`, `customer`, `contact_name` để `lookup_lead_exact` và pre-filter khớp bất kể người dùng gõ có dấu hay không. **Lưu ý:** văn bản EMBEDDING vẫn giữ dấu (model hiểu tốt hơn — quy ước dự án), chỉ chuẩn hóa cho LOOKUP.
- **Phone:** chuẩn hóa 3 cột phone (`phone`, `contact_phone`, `intro_person_phone`) về dạng chỉ-số (strip khoảng trắng, `+84`→`0`, bỏ ký tự đặc biệt). Lưu ý `intro_person_phone` chỉ `VARCHAR2(11)`.
- **Email:** lowercase + trim.
- **Enum:** chuẩn hóa `status`, `temperature` về tập giá trị canonical (tránh "Hot"/"hot"/"HOT" / "nóng"); cân nhắc bảng tra cứu giá trị hợp lệ để `query_lead_metrics` GROUP BY sạch.
_Confidence: High (dựa pattern đã verify trong dự án)._

### Scalability & Performance — Index ở quy mô >500k (Phần 4)

**Vector index:**
- Dùng **Local Partitioned HNSW** trên cột `VECTOR(1024, FLOAT32)` (COSINE) — partition pruning tăng tốc; số partition khởi điểm ≈ √(số dòng) (~700 với 500k là quá nhiều → thực tế partition theo cột nghiệp vụ như `status` hoặc `co_id`).
- HNSW phù hợp tới hàng triệu dòng; **chuyển IVF nếu vượt ~50 triệu** hoặc Vector Memory Pool căng.
- **Pre-filter `PRE_W`** (HNSW, có join-back) để lọc `status`/`emp_id` trước khi ANN — giảm mạnh không gian tìm kiếm ở >500k.

**B-tree index (cho lookup & aggregate):**
- Cột chuẩn hóa: `cle_code`, `phone_normalized`, `email_normalized`, `tax_id` (unique nếu hợp lệ).
- Cột aggregate/filter: composite trên `(status, temperature)`, `(emp_id)`, `(source)`, `(co_id, status)`.
- Cột ranking cho `suggest_lead_actions`: `(emp_id, next_action_date)`, `(temperature, score)`.

**Embedding ở quy mô lớn:**
- Embed lại 500k dòng tốn kém trên CPU → **incremental**: chỉ embed dòng mới/đổi (trigger hoặc cột `embedding_hash`/`modify_date` so sánh). KHÔNG re-embed toàn bảng mỗi lần.
- Cảnh báo: NULL `embedding` làm `VECTOR_DISTANCE` trả NULL → dòng chưa embed bị loại; cần job nền backfill.

**Partition strategy:**
- Partition bảng theo `status` (list) hoặc `co_id` (nếu đa công ty) để pre-filter + partition pruning cộng hưởng.

_Confidence: High._

**Sources:**
- [Ways To Embed Structural Data — Murat Evcil (Medium)](https://medium.com/@muratevcilf/ways-to-embed-structural-data-finding-meaning-in-messy-tables-db68efdcba3f)
- [Develop a RAG Solution — Generate Embeddings (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/rag/rag-generate-embeddings)
- [Oracle 26ai Vector Indexes — Local Partitioned HNSW / IVF](https://docs.oracle.com/en/database/oracle/oracle-database/26/nfcoa/vector-indexes.html)
- [Included columns for IVF indexes (26ai)](https://docs.oracle.com/en/database/oracle/oracle-database/26/vecse/included-columns-ivf-indexes.html)

---

## Implementation Approaches and Technology Adoption

### User Question Space — Không gian câu hỏi người dùng (Phần 5)

Ánh xạ câu hỏi thực tế → tool. Phục vụ **cả sale lẫn quản lý**.

**Nhóm Sale (tra cứu + hành động):**
| Câu hỏi mẫu | Tool |
|-------------|------|
| "Lead mã CL00123 đang ở trạng thái nào?" | `lookup_lead_exact` (code) |
| "Tìm khách hàng có SĐT 0901234567" | `lookup_lead_exact` (phone) |
| "Có lead nào trong ngành sản xuất thép giới thiệu bởi anh Minh không?" | `search_leads_semantic` |
| "Hôm nay tôi cần chăm sóc lead nào?" | `suggest_lead_actions` (today) |
| "Lead nào của tôi quá hạn next action?" | `suggest_lead_actions` (overdue) |
| "Lead nóng nào tôi chưa liên hệ lâu rồi?" | `suggest_lead_actions` (hot/cold) |

**Nhóm Quản lý (thống kê + giám sát):**
| Câu hỏi mẫu | Tool |
|-------------|------|
| "Có bao nhiêu lead theo từng trạng thái?" | `query_lead_metrics` (status) |
| "Phân bố lead theo nguồn?" | `query_lead_metrics` (source) |
| "Điểm số trung bình lead theo từng nhân viên?" | `query_lead_metrics` (owner, avg_score) |
| "Nhân viên nào có nhiều lead nóng nhất?" | `query_lead_metrics` (owner + filter temperature) |
| "Team của tôi có bao nhiêu lead quá hạn?" | `suggest_lead_actions` (overdue, theo team) |

**Khoảng trống cần lưu ý:** câu hỏi lai (vd "Top 5 lead nóng ngành bán lẻ chưa chăm sóc") cần kết hợp semantic + filter + ranking → agent có thể phải gọi ≥2 tool; cân nhắc một tool tổng hợp nếu xảy ra thường xuyên (nhưng giữ ≤8 tool).
_Confidence: High._

### Risk Assessment and Mitigation — Rủi ro & Gotcha (Phần 6)

| Rủi ro | Nguyên nhân | Giảm thiểu |
|--------|-------------|-----------|
| **ORA-20960** | Model emit tool-call sai schema (model yếu/embedding-only) | Dùng `qwen2.5:3b-instruct`; tail `journalctl -u ollama -f` khi reproduce; escalate 3b→7b-instruct nếu chọn sai |
| **Qwen2.5 hallucinate tool-call** khi nhiều tool | Issue #7051 (mẫu "Maybe") | Giữ 4 tool, mô tả rõ ràng (giảm 70% gọi sai), few-shot trong system prompt, num_predict đủ |
| **NULL embedding** → VECTOR_DISTANCE NULL | Dòng mới chưa embed | Job nền backfill; loại dòng NULL khỏi search; chạy đúng thứ tự seq→insert→chunk→embed→commit |
| **Độ trễ CPU cao** ở >500k | Vector pool, không pre-filter | PRE_W pre-filter; partition pruning; `keep_alive 24h`; num_ctx 2048 |
| **Pre-filter quá hẹp → 0 kết quả** | Filter + low correlation | Fallback nới filter; cảnh báo người dùng |
| **Chọn sai tool (semantic vs exact)** | Mô tả tool mơ hồ | Mô tả phân định rõ "định danh cụ thể" vs "mô tả chung"; đã gặp ở customers agent |
| **Prompt không dấu gây nhiễu model** | Quy ước dự án | System prompt + embedding text tiếng Việt CÓ dấu |
| **Phân quyền dữ liệu** | Sale thấy lead người khác | Filter `emp_id`/`owner` theo người đăng nhập APEX (VPD/context) |

**Budget an toàn (web best practice):** đặt giới hạn số tool-call, thời gian, token; vượt thì dừng & escalate. Log mọi tool-call (input/output/latency/success) để eval.
_Confidence: High._

## Technical Research Recommendations

### Implementation Roadmap (đề xuất giai đoạn sau)
1. **Chuẩn hóa & schema:** thêm cột normalized (phone/email/name), SEQUENCE + .NEXTVAL cho PK, enum canonical.
2. **Embedding:** cột `VECTOR(1024, FLOAT32)`; hàm dựng câu văn Nhóm A; backfill + incremental.
3. **Index:** Local Partitioned HNSW + b-tree composite; partition theo `status`/`co_id`.
4. **Tools:** 4 PL/SQL tool + Generative AI Tool plug-in (APEX 26.1); mô tả tiếng Việt có dấu.
5. **Agent:** system prompt VI có dấu, `qwen3-erp` (qwen2.5:3b-instruct), budget + logging.
6. **Eval:** bộ câu hỏi Phần 5 làm reference dataset; đo tool-selection accuracy.

### Technology Stack Recommendations
- DB 26ai HNSW (local partitioned) + PRE_W; APEX 26.1 GenAI Tool plug-in; Ollama qwen2.5-instruct (escalate 7b nếu cần); bge-m3 embedding giữ nguyên.

### Success Metrics and KPIs
- Tool-selection accuracy ≥ 90% trên bộ câu hỏi Phần 5.
- Semantic search: lead đúng nằm trong top-N (precision@5).
- Độ trễ/request mục tiêu (CPU): theo dõi & so baseline customers agent (~2s eval đã đạt).
- Tỷ lệ ORA-20960 ≈ 0 sau khi chốt model + mô tả tool.

**Sources:**
- [Ollama issue #7051 — Qwen2.5 tool-call hallucination](https://github.com/ollama/ollama/issues/7051)
- [AI Agent Tool Use Best Practices — MLflow](https://mlflow.org/articles/ai-agent-tool-use-best-practices-for-practitioners/)
- [LLM Agent Evaluation Metrics 2026 — Confident AI](https://www.confident-ai.com/blog/llm-agent-evaluation-complete-guide)
- [Pre and Post Filtering in Vector Search — RAG Pipelines](https://ai.plainenglish.io/pre-and-post-filtering-in-vector-search-with-metadata-and-rag-pipelines-fc4c58fff2be)

---

# CRM_LEADS AI Agent — Comprehensive Technical Research (Synthesis)

## Executive Summary

CRM_LEADS là bảng nghiệp vụ "nóng" với hơn 500.000 dòng và 40+ cột trải từ định danh (mã, SĐT, email, MST) đến mô tả định tính (nguồn, người giới thiệu, ghi chú, hành động tiếp theo) và chỉ số định lượng (status, temperature, score, ngày). Thách thức cốt lõi của một AI Agent tối ưu trên dữ liệu này không phải là "bật vector search" mà là **phân tách đúng đâu là dữ liệu ngữ nghĩa cần embedding, đâu là dữ liệu cấu trúc cần lọc/aggregate, và đâu là định danh cần tra cứu chính xác** — rồi ghép chúng lại qua một bộ tool gọn, đáng tin trên một mô hình LLM CPU-only.

Nghiên cứu xác nhận Oracle AI Database 26ai cung cấp sẵn các trụ cột kỹ thuật cần thiết cho quy mô này: HNSW cho phép DML + nhất quán giao dịch, **pre-filter `PRE_W`/`PRE_WO`** và **Local Partitioned HNSW** với partition pruning. Kết hợp với APEX 26.1 (Generative AI Tool plug-in, tool-calling native) và Ollama qwen2.5-instruct, kiến trúc khả thi là **4 tool job-specific** + **pre-filter trước RAG** + **embedding tiếng Việt có dấu chỉ trên cột ngữ nghĩa**. Rủi ro lớn nhất mang tính mô hình (qwen2.5 hallucinate tool-call khi nhiều tool) và vận hành (NULL embedding, độ trễ CPU, phân quyền theo owner) — tất cả đều có biện pháp giảm thiểu đã biết.

**Key Technical Findings:**
- Oracle 26ai hỗ trợ pre-filter chính thức trên HNSW (`PRE_W`) — nền tảng để RAG chịu tải >500k.
- Tool hẹp theo việc + mô tả tốt giảm tới 70% gọi sai; 4 tool nằm trong ngưỡng an toàn ≤8.
- Không embed dữ liệu thô — phải dựng câu văn có nghĩa từ ~14 cột Nhóm A.
- qwen2.5 tool-call kém ổn định khi nhiều tool (Ollama #7051) → mô tả rõ + escalate 7b nếu cần.
- Pre-filter chính xác hơn post-filter và HNSW tương thích filtering.

**Technical Recommendations:**
1. Phân loại cột theo 3 nhóm A/B/C; chỉ embed Nhóm A (câu văn VI có dấu).
2. Triển khai 4 tool với mô tả phân định rõ "định danh cụ thể" vs "mô tả chung".
3. Local Partitioned HNSW + `PRE_W` pre-filter theo status/owner; incremental embedding + backfill NULL.
4. Chuẩn hóa MLE cho lookup (bỏ dấu/phone/email/enum), giữ dấu cho embedding.
5. Áp budget + logging tool-call; phân quyền dữ liệu theo `emp_id`/`owner`.

## Table of Contents

1. **Technical Research Scope Confirmation** — phạm vi & phương pháp
2. **Technology Stack Analysis** — DB 26ai · APEX 26.1 · Ollama/qwen2.5 · bge-m3
3. **Integration Patterns — Tool Architecture & RAG Flow** — 4 tool + luồng end-to-end
4. **Architectural Patterns** — phân loại cột · chuẩn hóa MLE · index & hiệu năng >500k
5. **Implementation** — không gian câu hỏi · rủi ro & gotcha · roadmap · KPI
6. **Synthesis** (phần này) — executive summary & kết luận

> Nội dung chi tiết của mỗi mục nằm ở các Level-2 section tương ứng phía trên báo cáo.

## Technical Research Conclusion

### Summary of Key Technical Findings
Một AI Agent CRM_LEADS tối ưu ở quy mô >500k được quyết định bởi ba lựa chọn kiến trúc: (a) phân tách dữ liệu ngữ nghĩa/cấu trúc/định danh, (b) bộ 4 tool hẹp với mô tả rõ ràng để mô hình CPU chọn đúng, và (c) pre-filter trước RAG trên HNSW để giữ độ trễ và độ chính xác. Stack hiện tại (26ai + APEX 26.1 + Ollama) đã đủ năng lực; không cần thành phần mới.

### Strategic Technical Impact Assessment
Cách tiếp cận này tái dùng trực tiếp pattern đã verify của bộ `customers` agent, nâng cấp cho quy mô lớn và đặc thù pipeline bán hàng. Rủi ro tập trung ở lớp mô hình và vận hành, đều có đường lui (escalate 7b, backfill, VPD).

### Next Steps Technical Recommendations
Chuyển sang giai đoạn triển khai SQL/PLSQL theo roadmap 6 bước (schema chuẩn hóa → embedding → index → 4 tool → agent → eval). Dùng bộ câu hỏi ở Phần 5 làm reference dataset để đo tool-selection accuracy trước khi go-live.

---

**Technical Research Completion Date:** 2026-06-30
**Source Verification:** Tất cả phát hiện then chốt đều có citation hiện hành (2026).
**Technical Confidence Level:** High — đối chiếu nhiều nguồn Oracle docs + cộng đồng.

_Báo cáo này là tham chiếu kỹ thuật cho việc thiết lập CRM_LEADS phục vụ AI Agent; phần triển khai mã nguồn là giai đoạn kế tiếp theo lựa chọn của người dùng._
