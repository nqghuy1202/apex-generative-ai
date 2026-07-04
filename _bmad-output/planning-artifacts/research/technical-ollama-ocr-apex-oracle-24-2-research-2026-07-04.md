---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments: []
workflowType: 'research'
lastStep: 6
research_type: 'technical'
research_topic: 'Ollama-OCR fit for APEX Oracle 24.2 + Ollama RAG stack'
research_goals: 'Decide (optimal/conditional/not recommended) whether Ollama-OCR is an optimal way to add OCR (as pre-processing feeding the existing bge-m3 vector-RAG pipeline) to APEX 24.2, comparing (1) direct PL/SQL->Ollama vision HTTP calls vs (2) wrapping Ollama-OCR as a REST microservice, under a hard CPU-only server B constraint.'
user_name: 'Gia Huy'
date: '2026-07-04'
web_research_enabled: true
source_verification: true
---

# Research Report: technical

**Date:** 2026-07-04
**Author:** Gia Huy
**Research Type:** technical

---

## Research Overview

**EN —** This report answers one decision: is **Ollama-OCR** the optimal way to add OCR to the existing APEX 24.2 + Ollama RAG stack, where OCR is a pre-processing stage feeding the bge-m3 vector-RAG pipeline, and everything must run on the CPU-only, non-AVX2 server B. Verdict: **CONDITIONAL / partial** — the *pattern* (VLM-based OCR feeding RAG) is sound and worth doing, but the **Ollama-OCR library specifically is only sometimes the right tool**, and the raw single-request performance ceiling on this 2013 CPU means OCR must be run as an **asynchronous batch stage, never on a user request**.

**VI —** Báo cáo trả lời một quyết định: **Ollama-OCR** có phải cách tối ưu để thêm OCR vào stack APEX 24.2 + Ollama RAG hiện có hay không — OCR là bước tiền xử lý feed vào pipeline vector-RAG bge-m3, và mọi thứ phải chạy trên server B chỉ-CPU, không-AVX2. Kết luận: **CÓ ĐIỀU KIỆN / một phần** — *mô hình* (dùng VLM để OCR rồi feed RAG) là đúng và đáng làm, nhưng **riêng thư viện Ollama-OCR chỉ phù hợp trong một số trường hợp**, và trần hiệu năng của CPU 2013 buộc OCR phải chạy như **giai đoạn batch bất đồng bộ, không bao giờ trên request người dùng**. Xem Executive Summary & mục Synthesis bên dưới để biết chi tiết verdict, bảng so sánh 2 hướng, lựa chọn model và roadmap.

---

<!-- Content will be appended sequentially through research workflow steps -->

## Technical Research Scope Confirmation

**Research Topic:** Ollama-OCR fit for APEX Oracle 24.2 + Ollama RAG stack
**Research Goals:** Decide (optimal/conditional/not recommended) whether Ollama-OCR is an optimal way to add OCR (pre-processing feeding the existing bge-m3 vector-RAG pipeline) to APEX 24.2, comparing (1) direct PL/SQL->Ollama vision HTTP calls vs (2) wrapping Ollama-OCR as a REST microservice, under a hard CPU-only server B constraint.

**Technical Research Scope:**

- Architecture Analysis - how Ollama-OCR works, vision model options, feed into RAG
- Implementation Approaches - dev effort, failure modes, maintainability per approach
- Technology Stack - Vietnamese-capable vision models, sizes, CPU-only viability
- Integration Patterns - APEX_WEB_SERVICE/UTL_HTTP direct vs FastAPI microservice wrapper
- Performance Considerations - CPU-only vision latency, keep_alive/eviction contention

**Research Methodology:**

- Current web data with rigorous source verification
- Multi-source validation for critical technical claims
- Confidence level framework for uncertain information; unmeasured numbers marked [estimate]
- Comprehensive technical coverage with architecture-specific insights

**Scope Confirmed:** 2026-07-04

---

## Technology Stack Analysis

### What Ollama-OCR actually is / Ollama-OCR thực chất là gì

**EN —** Ollama-OCR is a thin **Python** convenience layer (`pip install ollama-ocr`, class `OCRProcessor`) over Ollama's vision models. It does not add an OCR engine of its own — it sends an image + a text prompt to a vision-language model (VLM) served by Ollama and returns the model's transcription. Value-adds over a raw API call: batch/parallel processing with progress, PDF-to-image handling, optional image preprocessing (resize/normalize), a `language` parameter, custom prompt override, and multiple output shapes (Markdown / plain text / JSON / key-value / tables). It also ships a Streamlit demo app.

**VI —** Ollama-OCR chỉ là một **lớp tiện ích Python mỏng** bọc quanh các vision model của Ollama — bản thân nó **không có engine OCR riêng**. Nó gửi (ảnh + prompt) tới một Vision-Language Model (VLM) do Ollama phục vụ và nhận lại phần chữ mà model "đọc" ra. Giá trị thêm so với gọi API thô: xử lý batch/song song, chuyển PDF→ảnh, tiền xử lý ảnh tùy chọn, tham số `language`, override prompt, và nhiều định dạng output (Markdown/JSON/text/bảng). Kèm một app demo Streamlit.

- **Wrapped models (exact tags):** `llama3.2-vision:11b`, `llava`, `granite3.2-vision`, `moondream`, `minicpm-v`.
- **Inputs:** images + PDF. **Outputs:** Markdown, plain text, JSON, structured/key-value, tables.
- _Source: [github.com/imanoop7/Ollama-OCR](https://github.com/imanoop7/Ollama-OCR)_

> ⚠️ **Architecture-critical fact:** OCR quality here = the **underlying VLM**, not the library. So the "which model" question dominates the "which library" question. The library is Python — it **cannot** be called from inside APEX/PL/SQL; it only matters if we run it as a separate process (Approach 2). The models it wraps are the same models Approach 1 would call directly over HTTP.

### Vision-Language models for OCR (Vietnamese-relevant)

| Model (Ollama tag) | Approx size (Q4) | OCR strength | Vietnamese-with-diacritics | CPU-only viability on server B |
|---|---|---|---|---|
| `minicpm-v` (2.6, ~8B) | ~5–6 GB | **High** for document OCR, multilingual | Better than llava-class [estimate] | Heavy but the most realistic of the VLMs |
| `qwen2.5vl:7b` (not wrapped by lib, callable directly) | ~6 GB | **Highest** class for text/layout OCR | Strong multilingual, incl. VI [estimate] | Heavy |
| `llama3.2-vision:11b` | ~7.9 GB | High, general docs | Moderate [estimate] | Very heavy on CPU |
| `granite3.2-vision` (~2B) | ~2–3 GB | Document/table extraction focus | Weak/uncertain for VI [estimate] | Lightest "serious" option |
| `llava` (7B/13B) | ~4–8 GB | Lower OCR accuracy vs above | Weak for VI [estimate] | Medium |
| `moondream` (~1.8B) | ~1.7 GB | Basic captions, weak dense OCR | Poor for VI [estimate] | Lightest, but likely inadequate for VI docs |

_Ranking corroborated: Qwen3-VL 8B and MiniCPM-V rank highest for OCR, then Llama 3.2 Vision 11B, then LLaVA. Granite is built for visual-document understanding (tables/charts). No public source gives a Vietnamese-specific accuracy benchmark for any of these — all VI accuracy cells above are `[estimate]` and MUST be validated on your own scans._
_Sources: [Local Vision Models 2026 (promptquorum)](https://www.promptquorum.com/power-local-llm/local-vision-models-llava-ollama-2026), [Qwen2.5-VL vs LLaMA 3.2 (labellerr)](https://www.labellerr.com/blog/qwen-2-5-vl-vs-llama-3-2/), [ollama.com vision models](https://ollama.com/search?c=vision)_

### The hard platform constraint: CPU + no AVX2

- **Ollama officially requires a 64-bit CPU with AVX2**; it *can* run on AVX-only CPUs but that is non-standard and **performance degrades significantly** (older 4th-gen-class CPUs show "significant lag" even on small quantized models).
- Server B = **2× Xeon E5-2680 v2 (Ivy Bridge-EP, 2013)** → has AVX and F16C but **NOT AVX2**. This is why the existing text models already run in a degraded-but-tolerable regime.
- Reference CPU generation rates: **5–15 tok/s on a *modern* AVX2 CPU**; MiniCPM-V GGUF cited at ~**6–8 tok/s on a phone**. A non-AVX2 2013 Xeon will be at or below the low end. `[estimate]`
- **VLM-specific cost:** the expensive part of vision inference is **image-token prefill** (an image expands to hundreds–thousands of tokens before any text is generated). On a CPU with no AVX2 this prefill is the real bottleneck — consistent with your already-documented finding that *prefill*, not generation, dominates latency on this box.
- _Sources: [Ollama not detecting AVX2 (#10506)](https://github.com/ollama/ollama/issues/10506), [llama.cpp AVX2 minimum? (#7723)](https://github.com/ggml-org/llama.cpp/discussions/7723), [Ollama system requirements 2026](https://localaimaster.com/blog/ollama-system-requirements), [MiniCPM-V](https://github.com/OpenBMB/MiniCPM-V)_

### Development-tool implications for the two approaches

- **Approach 1 (direct from PL/SQL):** stack you already own — `APEX_WEB_SERVICE`/`UTL_HTTP` → Ollama `/api/generate` with `"images":["<base64>"]`. **No Python, no new runtime.** PDF→image conversion becomes your problem (Oracle-side or pre-uploaded images). Zero net-new moving parts beyond a new tool prompt.
- **Approach 2 (Ollama-OCR as REST microservice):** net-new **Python 3 + FastAPI + ollama-ocr + (poppler/pdf2image for PDFs)** service running on server B, plus process supervision (systemd), a port, and its own failure surface. You inherit the library's PDF and batch handling for free, at the cost of a second service to operate on an already-loaded host.

_Confidence: HIGH on library shape, model line-up, and the AVX2 constraint (multi-source). MEDIUM/`[estimate]` on all CPU tok/s numbers and every Vietnamese-accuracy claim — no benchmark source is Vietnamese-specific or run on Ivy-Bridge-no-AVX2 hardware._

---

## Integration Patterns Analysis

The two candidate approaches differ **only** in *where the image→text call is made*, not in what the VLM does. Below, both are traced end-to-end into the existing RAG pipeline (chunk → bge-m3 → `VECTOR(1024)` → HNSW).

### The wire protocol is identical for both approaches

Ollama vision uses one endpoint — `POST /api/generate` (or `/api/chat`) — with a base64 image array:

```json
{ "model": "minicpm-v", "prompt": "Trích xuất toàn bộ chữ trong ảnh, giữ nguyên dấu tiếng Việt.",
  "images": ["<base64-no-newlines>"], "stream": false,
  "options": { "temperature": 0 } }
```

- Supported image formats: **JPEG, PNG, WebP**. No PDF — PDF must be rasterised to page images **before** the call.
- _Sources: [Ollama Vision docs](https://docs.ollama.com/capabilities/vision), [Ollama API md](https://github.com/ollama/ollama/blob/main/docs/api.md)_

### Approach 1 — Direct from PL/SQL (APEX_WEB_SERVICE / UTL_HTTP)

- **Call path:** `BLOB2CLOBBASE64(image_blob)` → build JSON CLOB → `APEX_WEB_SERVICE.MAKE_REST_REQUEST(p_url=>'.../api/generate', p_http_method=>'POST', p_body=>clob)` → parse response CLOB with `JSON_TABLE`/`APEX_JSON` → store text → existing chunk+embed job. This is **the exact pattern already in production for bge-m3**.
- **Hard protocol limit:** `MAKE_REST_REQUEST` **`p_transfer_timeout` defaults to 180 s** — the same ceiling behind your prior `ORA-29276`. A CPU-only VLM doing image prefill can easily exceed 180 s per page; you MUST raise `p_transfer_timeout` **and** keep the call **off the interactive APEX request** (run it in `DBMS_SCHEDULER`, exactly like the embedding backfill job).
- **PDF gap (critical):** Oracle/APEX has **no native PDF→image rasteriser**. Options: (a) accept only pre-rendered page images uploaded by the user; (b) render outside the DB. This is the single biggest weakness of Approach 1.
- **Moving parts added:** essentially none — one new PL/SQL tool/proc + one scheduler job. No new runtime, no new port, no new OS service.
- _Sources: [MAKE_REST_REQUEST](https://docs.oracle.com/cd/E37097_01/doc.42/e35127/GUID-4AC0229D-85E2-439A-9485-531B7B8B6274.htm), [APEX_WEB_SERVICE definitive guide](https://blog.cloudnueva.com/apexwebservice-the-definitive-guide), [Base64 in APEX](https://medium.com/@atacanymc/use-base64-format-in-oracle-apex-restfull-service-496ff69f6ec3)_

### Approach 2 — Ollama-OCR wrapped as a REST microservice

- **Call path:** APEX → `POST http://serverB:8000/ocr` (your FastAPI) → service runs `OCRProcessor(...)` → which itself calls Ollama on localhost → returns JSON `{text, format}` → APEX stores → chunk+embed. APEX still uses `APEX_WEB_SERVICE`, so the DB-side code is *simpler* (no base64 building, no Ollama JSON shape).
- **You inherit for free:** PDF→image (library handles it via poppler/pdf2image), batch/parallel workers, output formatting (Markdown/tables), the `language` parameter, prompt presets.
- **Moving parts added:** a **new Python 3 + FastAPI + ollama-ocr + poppler** service, a systemd unit, a listening port, its own logging/health, and version-drift risk (a thin community wrapper — pin the version). It runs **on the already-loaded server B**, so it competes for the same CPU/RAM as qwen3-erp + bge-m3 + the VLM.
- **Interop note:** the service is a clean seam — you could later move it to a GPU box without touching APEX. That optionality is Approach 2's main structural advantage.

### Coexistence on one CPU (applies to BOTH)

- Both approaches ultimately load a **3rd model** (the VLM, ~2–8 GB) into the same Ollama on server B that already holds qwen3-erp + bge-m3. With `OLLAMA_MAX_LOADED_MODELS=2` today, loading the VLM will **evict** a resident model → cold reload cost on the next chat/embedding call.
- **Mitigation pattern (decisive):** keep OCR **fully asynchronous and batched** — never on the chat request path. Run VLM OCR in a dedicated `DBMS_SCHEDULER` window (or a queue the microservice drains) when the interactive agent is idle, then set embeddings to the existing deferred job. This mirrors your established `CRM_LEADS_EMBED_JOB` decision and is the same reason you already defer bge-m3.
- Raising `OLLAMA_MAX_LOADED_MODELS=3` is possible only if RAM allows all three resident (you noted ~37 GB spare) — but three models thrash one non-AVX2 CPU under concurrency; serialise instead of parallelise (`OLLAMA_NUM_PARALLEL=1`).

### Security / operational patterns

- Same-LAN HTTP (server A→B) as today; no new auth surface for Approach 1. Approach 2 adds a port to firewall/scope to the APEX host only.
- Payloads are base64 image bytes — size them down (Approach 1 must cap image resolution before base64, or the CLOB and prefill both balloon).

_Confidence: HIGH on the wire protocol, the 180 s timeout, and the PDF-rasterisation gap (all doc-sourced). MEDIUM on eviction behaviour specifics — depends on your exact `OLLAMA_*` env at deploy time._

---

## Architectural Patterns and Design

### The decisive architectural pattern: OCR is an ASYNC ingestion stage, never a query-time stage

Production OCR→RAG systems converge on the same shape: a **decoupled, queue-driven ingestion pipeline** where documents are OCR'd once, offline, and only the resulting text/embeddings are touched at query time. This maps perfectly onto your existing "defer embeddings to a background job" decision.

```
[Upload BLOB in APEX]                         ← user-facing, instant
        │  (insert row: documents, status='PENDING_OCR')
        ▼
[OCR queue / DBMS_SCHEDULER job]              ← offline, server B, slow OK
   ├─ 1. Is this a digital-native PDF with a text layer?  ──► YES ─► extract text directly, SKIP the VLM
   │                                                              (huge CPU saving — see below)
   └─ NO / it's a scan/image ─► rasterise page → base64 → Ollama VLM → text
        │  (update documents.ocr_text, status='OCR_DONE')
        ▼
[Existing chunk job]  DBMS_VECTOR_CHAIN.UTL_TO_CHUNKS
        ▼
[Existing embed job]  bge-m3 → VECTOR(1024, FLOAT32)     ← CRM_LEADS_EMBED_JOB pattern
        ▼
[HNSW index]  ← query time: pure vector search, no VLM involved
```

- _Sources: [Operationalizing Document AI microservice architecture (arXiv 2605.18818)](https://arxiv.org/html/2605.18818v1), [Definitive Guide to OCR in 2026 (VLMs)](https://slavadubrov.github.io/blog/2026/03/04/the-definitive-guide-to-ocr-in-2026-from-pipelines-to-vlms/), [Integrating OCR into RAG (Palos)](https://palospublishing.com/integrating-ocr-pipelines-into-rag-workflows/)_

### Design principle #1 — Confidence-based routing: skip the VLM whenever possible

The strongest published best practice for a CPU-constrained box: **check for an embedded text layer before rasterising.** Digital-native PDFs (exported invoices, system-generated reports) already contain perfect text — running a VLM on them is pure waste. Only true **scans/photos** need the VLM. On a non-AVX2 CPU this routing is not an optimisation, it is what makes the system viable at all: it can remove the majority of pages from the expensive path.

- Implication: your pipeline needs a cheap pre-check (text-layer extraction) *in front of* the VLM. This lives naturally in the microservice (poppler can report a text layer) — a point in Approach 2's favour — but can also be done by pre-filtering which files ever reach OCR.

### Design principle #2 — Separate CPU-rasterise work from model-inference work

Production guidance explicitly separates rasterisation/normalisation (CPU, cheap, parallel) from model inference (the scarce resource). On your single box both land on the same CPU, so the lever is **temporal separation**: rasterise/queue anytime, but **serialise VLM inference** into an idle window so it never contends with the interactive qwen3-erp agent.

### Scalability & performance patterns for THIS hardware

- **Throughput, not latency, is the right target.** OCR here is a batch/back-office job — measure "documents per night," not "seconds per request." This reframing dissolves most of the CPU-speed problem.
- **Backpressure via a status column / queue.** `documents.status` (`PENDING_OCR → OCR_DONE → EMBEDDED`) is a sufficient lightweight queue inside Oracle; no Redis/RabbitMQ needed at your scale.
- **One model resident at a time on the OCR path.** Serialise: load VLM → drain the OCR batch → let it idle-evict → chat models reload. Avoid three-way concurrency on one non-AVX2 CPU.
- **Cap image resolution** before base64 (e.g. long side ~1500 px) — VLM prefill cost scales with image tokens, which scale with resolution.

### Data architecture — reuse the existing two-table shape

The proven `documents ↔ doc_chunks` schema already in `sql/apex_vector_rag_demo.sql` extends cleanly: add `ocr_source` (`text_layer` | `vlm` | `native`), `ocr_model`, `ocr_status`, and a confidence/needs-review flag on `documents`. No new vector infrastructure — OCR only produces the *text* that feeds the identical chunk→embed→HNSW path.

### Deployment / operations architecture

- **Approach 1 deployment:** nothing new to deploy — a PL/SQL package + a scheduler job. Ops surface = your existing DB.
- **Approach 2 deployment:** one systemd-managed FastAPI service on server B, health-checked, version-pinned. Buys the text-layer pre-check, PDF handling, and a future-proof seam to move OCR to a GPU host without touching APEX.

_Confidence: HIGH — the async-ingestion + confidence-routing + separate-rasterise-from-inference patterns are consistently recommended across multiple 2026 sources and align with patterns you already run in production._

---

## Implementation Approaches and Technology Adoption

### Model selection — the real decision (bigger than library vs no-library)

| Model | Params | Why it matters for you | Ollama availability |
|---|---|---|---|
| **Vintern-1B** | ~1B | **Purpose-built for Vietnamese** OCR/doc extraction (Qwen2 + InternViT). Tiny → the **only** VLM likely to give tolerable latency on a non-AVX2 CPU. | NOT in default Ollama library / NOT wrapped by Ollama-OCR — import GGUF via a custom Modelfile [verify GGUF availability] |
| **MiniCPM-V 2.6** (~8B) | ~8B | **Best raw OCR accuracy** (SOTA on OCRBench, beats GPT-4V/Gemini 1.5 on that bench); strong dense/handwritten text. | `minicpm-v` — wrapped by Ollama-OCR ✅ |
| **Qwen2.5-VL 7B** | ~7B | Best all-rounder for invoices/layout/structured output. | `qwen2.5vl:7b` in Ollama; NOT wrapped by Ollama-OCR (callable directly) |
| granite3.2-vision (~2B) | ~2B | Light, table/doc focus, weak VI. | wrapped ✅ |

_Sources: [Local AI Vision Tasks 2026](https://localaimaster.com/blog/local-ai-vision-tasks), [Vietnamese Document OCR (TurboLens)](https://www.turbolens.io/blog/2026-05-19-vietnamese-document-ocr-from-characters-to-context-aware-extraction), [Vintern-1B (arXiv 2408.12480)](https://arxiv.org/html/2408.12480v1)_

> **Adoption implication:** the best Vietnamese model (Vintern-1B) is **NOT one of the five models Ollama-OCR wraps**. So if VI accuracy wins, Ollama-OCR's wrapper value shrinks — you'd import Vintern as a custom GGUF and call it directly (Approach-1-style) anyway. Ollama-OCR's convenience only fully applies if you settle on `minicpm-v`/`granite3.2-vision`.

### Development effort — honest comparison

| | Approach 1 (direct PL/SQL) | Approach 2 (Ollama-OCR microservice) |
|---|---|---|
| New runtimes to install/operate | None | Python3, FastAPI, ollama-ocr, poppler, systemd unit |
| PDF→image | **You build it (hard — no native Oracle rasteriser)** | Free (library) |
| Text-layer pre-check | You build it | Easier (poppler) |
| DB-side code | More (base64 build, Ollama JSON parse) | Less (call your own clean REST) |
| Batch/parallel | You build (scheduler loop) | Free (library) |
| Failure surface | Small, all in DB you already run | +1 service, +version drift on a thin community wrapper |
| Skill fit | 100% your current SQL/PLSQL skill | Adds Python ops on server B |
| Future GPU move | Rewrite the call | **Free — just repoint the service** |

### Testing & QA

- **Ground-truth harness:** assemble 20–50 representative Vietnamese docs (scans, invoices, mixed) with hand-verified text; score **Character Error Rate** per candidate model. This is the ONLY way to resolve the `[estimate]` VI-accuracy cells — no public benchmark will.
- Test the **text-layer routing** first: confirm digital-native PDFs bypass the VLM entirely.
- Load-test the **coexistence**: run OCR batch while firing a qwen3-erp chat question; measure eviction/reload cost and confirm the interactive path stays within its 180 s ceiling.

### Cost / resource management

- **RAM budget:** a 7–8B VLM at Q4 ≈ 5–6 GB; with ~37 GB spare you *can* hold it resident, but CPU is the bottleneck, not RAM. Prefer **Vintern-1B (~1 GB)** to keep all three models resident cheaply and cut prefill.
- **Zero incremental licensing** — all models are open-weight, self-hosted; marginal cost is CPU time in an idle window.

### Risk assessment & mitigation

| Risk | Severity | Mitigation |
|---|---|---|
| VLM prefill on non-AVX2 CPU too slow for interactive use | **High** | Make OCR strictly async/batch; measure docs/night, not s/req |
| Loading VLM evicts qwen3-erp/bge-m3 mid-chat | High | Serialise OCR into idle windows; `OLLAMA_NUM_PARALLEL=1` |
| Vietnamese accuracy of wrapped models unknown | High | CER harness on your own docs BEFORE committing; consider Vintern-1B |
| No native PDF rasteriser (Approach 1) | Medium | Approach 2, or pre-render pages outside DB |
| Ollama-OCR is a thin community wrapper (maintenance) | Medium | Pin version; keep logic thin so you can drop to direct calls |
| 180 s APEX HTTP timeout on OCR call | Medium | Never OCR on the request path; scheduler job only |

## Technical Research Recommendations

### Implementation Roadmap

1. **Prove the model first (1–2 days):** import Vintern-1B GGUF + pull `minicpm-v`; run the CER harness on your own Vietnamese docs. Pick the winner on accuracy-per-CPU-second.
2. **Add text-layer routing:** ensure digital PDFs skip the VLM.
3. **Build the async ingestion path** reusing `documents ↔ doc_chunks` + a `status` queue + `DBMS_SCHEDULER`, wiring OCR text into the existing chunk→bge-m3→HNSW pipeline.
4. **Choose the integration seam by the model choice:** if the winner is Vintern-1B (not wrapped) → **Approach 1**; if you need the library's PDF/batch handling and the winner is `minicpm-v` → **Approach 2** as a thin service.
5. **Load-test coexistence**, then schedule OCR into idle windows.

### Technology Stack Recommendations

- Reuse: Oracle 24.2 + APEX_WEB_SERVICE + DBMS_VECTOR_CHAIN + bge-m3 + HNSW (unchanged).
- Add: one VLM on server B (Vintern-1B preferred for CPU; minicpm-v for max accuracy) + text-layer pre-check + async OCR job. Add the FastAPI/Ollama-OCR service **only if** the library's PDF/batch handling earns its keep.

### Skill Development Requirements

- Approach 1: none new (SQL/PLSQL you already have).
- Approach 2: basic Python service ops (FastAPI + systemd) on server B.

### Success Metrics and KPIs

- Vietnamese **CER** per model on your harness (primary quality gate).
- **Documents/night** throughput in the idle window (primary perf gate).
- Interactive qwen3-erp latency **unchanged** while OCR batch runs (coexistence gate).
- % pages routed to text-layer extraction vs VLM (cost gate — higher is better).

_Confidence: HIGH on effort/risk structure and roadmap; VI-accuracy ranking is source-backed but not Vietnamese-benchmarked on your hardware → the CER harness is mandatory before committing._

---

# Ollama-OCR on APEX 24.2: Is It Optimal? — Research Synthesis

## Executive Summary

**EN —** OCR-via-vision-model is the right architectural move for turning scanned/image documents into searchable text for your bge-m3 RAG pipeline. But the specific question — *"is **Ollama-OCR** optimal?"* — resolves to **CONDITIONAL**, for two reasons. First, **Ollama-OCR is a thin Python wrapper, not an OCR engine**: its value is PDF handling + batching + output formatting around five vision models. It **cannot be called from PL/SQL**, so it only helps as a **separate REST microservice**. Second, and decisively, the **best Vietnamese OCR model (Vintern-1B) is not one of the five models it wraps** — so if Vietnamese accuracy drives your model choice, you end up importing a custom GGUF and calling Ollama directly, which makes the wrapper largely redundant.

The **hard constraint dominates everything**: server B is a 2013 Xeon E5-2680 v2 with **no AVX2**, already loaded with qwen3-erp + bge-m3, where you have proven that **prompt/image prefill on CPU is the bottleneck**. A multi-GB vision model doing image-token prefill on this CPU is **not viable for interactive, per-request OCR**. It *is* viable — and genuinely useful — as an **asynchronous, batched ingestion job** measured in *documents per night*, not seconds per request. Reframed that way, the CPU limitation stops being a blocker.

**VI —** Dùng vision-model để OCR là nước đi kiến trúc đúng để biến tài liệu scan/ảnh thành text tìm kiếm được cho pipeline bge-m3. Nhưng câu hỏi cụ thể — *"Ollama-OCR có tối ưu không?"* — cho kết quả **CÓ ĐIỀU KIỆN**, vì hai lý do. Một, **Ollama-OCR là lớp Python mỏng, không phải engine OCR**; nó không gọi được từ PL/SQL nên chỉ hữu ích khi chạy như **REST microservice riêng**. Hai (quyết định): **model OCR tiếng Việt tốt nhất (Vintern-1B) không nằm trong 5 model nó bọc** → nếu ưu tiên độ chính xác tiếng Việt, anh sẽ import GGUF tùy chỉnh và gọi Ollama trực tiếp, khiến wrapper gần như thừa. **Ràng buộc phần cứng chi phối tất cả:** CPU 2013 không AVX2, đã tải sẵn 2 model, prefill là nút thắt → VLM **không khả thi cho OCR tương tác theo-từng-request**, nhưng **rất khả thi và hữu ích như job batch bất đồng bộ** (đo bằng "tài liệu/đêm").

### Key Technical Findings

- **Library ≠ engine.** OCR quality = the underlying VLM; Ollama-OCR only adds PDF/batch/format convenience and can't run inside the DB. `[HIGH]`
- **Model choice > library choice.** Vintern-1B (~1B, Vietnamese-specialised) is the CPU-friendly VI pick but is **not** wrapped by Ollama-OCR; MiniCPM-V 2.6 (wrapped) has the best raw OCR accuracy but is ~8B/heavy. `[HIGH lineup, [estimate] on VI accuracy]`
- **Non-AVX2 CPU is the hard ceiling.** Ollama officially needs AVX2; on this CPU vision prefill is slow — interactive per-request OCR is off the table. `[HIGH]`
- **The 180 s APEX HTTP timeout** (same one behind your prior `ORA-29276`) forbids OCR on the request path. `[HIGH]`
- **No native Oracle PDF rasteriser** — a real gap for the direct-PL/SQL approach; the library (poppler) solves it. `[HIGH]`
- **Confidence-based routing** (skip the VLM for digital-native PDFs with a text layer) is the single biggest CPU-saving lever. `[HIGH]`

### Technical Recommendations (top 5)

1. **Adopt the pattern, run OCR async/batch** via `DBMS_SCHEDULER` into an idle window — never on a user request. Measure *documents/night*.
2. **Pick the model with a CER harness on your own Vietnamese docs first.** Test **Vintern-1B** (CPU-friendly, VI-specialised) vs **MiniCPM-V** (max accuracy). Model choice then decides the integration seam.
3. **If the winner is Vintern-1B → use Approach 1** (direct PL/SQL→Ollama, reuse the bge-m3 pattern); the Ollama-OCR wrapper adds little.
4. **If you need PDF+batch handling and the winner is `minicpm-v` → use Approach 2** (thin FastAPI + Ollama-OCR service) — and you also get the text-layer pre-check and a clean future-GPU seam.
5. **Add confidence-based routing** (extract embedded text layer before ever calling a VLM) to remove most pages from the expensive path.

## Verdict table — Is Ollama-OCR optimal?

| Dimension | Verdict |
|---|---|
| Pattern (VLM OCR → bge-m3 RAG) | ✅ **Optimal** — right approach, reuses your stack |
| Ollama-OCR **library** specifically | 🟡 **Conditional** — only if model = `minicpm-v`/`granite` AND you want PDF/batch for free; redundant if model = Vintern-1B/Qwen2.5-VL |
| Interactive per-request OCR on server B | ❌ **Not viable** on non-AVX2 CPU |
| Async/batch OCR on server B | ✅ **Viable & recommended** |
| Vietnamese accuracy | ⚠️ **Unproven** — no public benchmark; CER harness mandatory |

## Approach 1 vs Approach 2 — decision matrix

| Criterion | Approach 1: Direct PL/SQL→Ollama | Approach 2: Ollama-OCR REST microservice |
|---|---|---|
| Fit with current stack | ✅ Reuses bge-m3 pattern exactly | 🟡 APEX side simpler, but new service |
| New runtime/ops | ✅ None | ❌ Python+FastAPI+poppler+systemd on server B |
| PDF→image | ❌ You must solve (no native rasteriser) | ✅ Free (poppler) |
| Text-layer pre-check | 🟡 You build | ✅ Easier |
| Batch/parallel | 🟡 You build (scheduler) | ✅ Free |
| Best VI model (Vintern-1B) | ✅ Works (direct GGUF) | 🟡 Works but wrapper adds little |
| Best accuracy model (minicpm-v) | 🟡 Works, more DB code | ✅ Wrapper shines |
| Failure surface | ✅ Small (all in DB) | 🟡 +1 service, +version drift |
| Future move to GPU | ❌ Rewrite call | ✅ Repoint service, APEX untouched |
| **Best when…** | **Winner model is Vintern-1B/Qwen2.5-VL; you value fewest moving parts** | **Winner model is minicpm-v; you need PDF/batch + a GPU-ready seam** |

## Implementation Roadmap

1. **Model bake-off (1–2 days):** import Vintern-1B GGUF + pull `minicpm-v`; run a CER harness on 20–50 of your real Vietnamese docs. Winner = best accuracy-per-CPU-second.
2. **Text-layer routing:** digital PDFs bypass the VLM entirely.
3. **Async ingestion:** extend `documents ↔ doc_chunks` with `ocr_status/ocr_source/ocr_model`; `DBMS_SCHEDULER` job OCRs `PENDING_OCR` rows → feeds existing chunk→bge-m3→HNSW.
4. **Pick the seam** from step 1's winner (Approach 1 vs 2 per the matrix).
5. **Coexistence load-test:** OCR batch running must not push the interactive qwen3-erp path past 180 s; serialise VLM inference (`OLLAMA_NUM_PARALLEL=1`) into idle windows.

## Risks & Open Questions the user must validate on their own hardware

- **VI accuracy** of Vintern-1B vs minicpm-v on *your* documents — no public benchmark exists; must measure (CER harness).
- **Actual tok/s and per-page latency** of the chosen VLM on the non-AVX2 E5-2680 v2 — all latency numbers here are `[estimate]`.
- **Eviction cost** when the VLM loads alongside qwen3-erp + bge-m3 (depends on your `OLLAMA_MAX_LOADED_MODELS`/`KEEP_ALIVE` at deploy).
- **Vintern-1B GGUF availability** for a clean Ollama Modelfile import `[verify]`.
- **PDF volume & type mix** (how many are digital-native vs scans) — determines how much the text-layer router saves.

## Methodology & Source Verification

Five-stage technical research (scope → tech stack → integration → architecture → implementation), each grounded in live web sources (July 2026). Every performance figure not measured or documented is marked `[estimate]`; no benchmarks were fabricated. No Vietnamese-specific, non-AVX2 benchmark exists in public sources — hence the mandatory CER harness before commitment.

**Primary sources:**
- [Ollama-OCR repository](https://github.com/imanoop7/Ollama-OCR)
- [Ollama Vision capability docs](https://docs.ollama.com/capabilities/vision) · [Ollama API reference](https://github.com/ollama/ollama/blob/main/docs/api.md)
- [Ollama AVX2 issue #10506](https://github.com/ollama/ollama/issues/10506) · [llama.cpp AVX2 discussion #7723](https://github.com/ggml-org/llama.cpp/discussions/7723) · [Ollama system requirements 2026](https://localaimaster.com/blog/ollama-system-requirements)
- [Oracle MAKE_REST_REQUEST](https://docs.oracle.com/cd/E37097_01/doc.42/e35127/GUID-4AC0229D-85E2-439A-9485-531B7B8B6274.htm) · [APEX_WEB_SERVICE guide](https://blog.cloudnueva.com/apexwebservice-the-definitive-guide)
- [Definitive Guide to OCR in 2026](https://slavadubrov.github.io/blog/2026/03/04/the-definitive-guide-to-ocr-in-2026-from-pipelines-to-vlms/) · [Operationalizing Document AI (arXiv 2605.18818)](https://arxiv.org/html/2605.18818v1) · [Integrating OCR into RAG (Palos)](https://palospublishing.com/integrating-ocr-pipelines-into-rag-workflows/)
- [Local Vision Models 2026](https://www.promptquorum.com/power-local-llm/local-vision-models-llava-ollama-2026) · [Qwen2.5-VL vs LLaMA 3.2](https://www.labellerr.com/blog/qwen-2-5-vl-vs-llama-3-2/) · [Local AI Vision Tasks 2026](https://localaimaster.com/blog/local-ai-vision-tasks) · [Vietnamese Document OCR (TurboLens)](https://www.turbolens.io/blog/2026-05-19-vietnamese-document-ocr-from-characters-to-context-aware-extraction) · [Vintern-1B (arXiv 2408.12480)](https://arxiv.org/html/2408.12480v1)

---

**Technical Research Completion Date:** 2026-07-04
**Source Verification:** All claims cited; unmeasured performance marked `[estimate]`
**Overall Confidence:** HIGH on architecture/integration/constraints; MEDIUM on model-specific Vietnamese accuracy and CPU latency (require local validation).
