---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments: []
workflowType: 'research'
lastStep: 6
research_type: 'technical'
research_topic: 'AI plug-ins and open-source projects for Oracle APEX (26.1)'
research_goals: 'Find and rank plug-ins/packages/open-source projects that add or extend AI capability on Oracle APEX 26.1 across four categories (embedded chat/RAG assistant, LLM/provider connectivity, vector search/embeddings tooling, AI UI components), scored on three weighted criteria (works with local/self-hosted LLM, genuinely open-source license, APEX 26.1 compatibility + active maintenance), with adopt/watch/skip calls relative to APEX 26.1 native AI, and gaps where building it ourselves is the answer.'
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

**EN —** This report surveys plug-ins / packages / open-source projects for adding AI to Oracle APEX 26.1 across four categories (embedded chat/RAG, LLM connectivity, vector/embeddings, AI UI components), scored on three weighted criteria (local-LLM support, genuine OSS, 26.1 compatibility + maintenance). **Bottom line: there is no rich third-party "AI plug-in" market — APEX AI is native + configuration-driven, and on 26.1 the native stack (APEX_AI, RAG Sources over your own vectors, native chat/generate DAs, native multi-provider incl. Ollama) already covers all four categories.** The one genuine open-source contender is **UC AI** (LGPL-3.0, Ollama-capable, active) — good, but largely redundant on your 26.1 + 26ai stack; keep it on a watch-list against a named gap. Your latency-critical CRM path should stay hand-built. See the Synthesis section for the ranked shortlist, adopt/watch/skip calls, and self-build gaps.

**VI —** Báo cáo khảo sát plug-in / package / dự án open-source thêm AI vào Oracle APEX 26.1 theo 4 nhóm, chấm theo 3 tiêu chí có trọng số. **Kết luận: không có chợ "plug-in AI" bên thứ ba phong phú — AI trên APEX là native + cấu hình; trên 26.1, stack native (APEX_AI, RAG Sources cắm vào vector của anh, DA chat/generate, đa-provider gồm Ollama) đã phủ cả 4 nhóm.** Ứng viên open-source thật sự duy nhất là **UC AI** (LGPL-3.0, chạy Ollama, còn bảo trì) — tốt nhưng phần lớn trùng lặp trên stack 26.1+26ai; để watch-list. Hot path CRM giữ tự xây. Xem mục Synthesis để có bảng xếp hạng, adopt/watch/skip và các gap phải tự xây.

---

<!-- Content will be appended sequentially through research workflow steps -->

## Technical Research Scope Confirmation

**Research Topic:** AI plug-ins and open-source projects for Oracle APEX 26.1
**Research Goals:** Find/rank plug-ins/packages/open-source projects adding or extending AI on APEX 26.1 across 4 categories (embedded chat/RAG assistant, LLM/provider connectivity, vector/embeddings tooling, AI UI components), scored on 3 weighted criteria (local/self-host LLM support, genuine open-source, APEX 26.1 compatibility + maintenance), with adopt/watch/skip calls vs native AI and gaps to self-build.

**Note on version:** original ask referenced APEX 24.2; user confirmed the live target is **APEX 26.1**. Flag tools that are 24.2-only or 26.1+.

**Research Methodology:**

- Current web data with rigorous source verification
- Every unverified license/version/maintenance fact marked [verify]; no invented plug-in names or repos
- Confidence levels applied; three-criteria weighted ranking

**Scope Confirmed:** 2026-07-04

---

## Technology Stack Analysis — the APEX AI landscape

### Headline finding (be honest up front)

**EN —** There is **no thriving third-party "AI plug-in" marketplace** for Oracle APEX the way there is for, say, charts or item types. The overwhelming pattern in 2026 is: **AI on APEX is native + configuration-driven**, supplemented by **community reference implementations (blog code you copy), not installable packages.** The most respected community voice for open-source LLMs on APEX (APEX App Lab) **explicitly recommends configuring Ollama through the native Generative AI Service — and building no custom plug-in at all.** So for your four categories, the real comparison is mostly *native feature vs. your own PL/SQL*, with a thin layer of genuinely optional plug-ins on top.

**VI —** **Không có một "chợ plug-in AI" bên thứ ba sôi động** cho Oracle APEX như với chart hay item type. Xu hướng áp đảo năm 2026: **AI trên APEX là native + cấu hình**, bổ sung bằng **code mẫu từ blog cộng đồng (copy về), không phải package cài đặt.** Tiếng nói cộng đồng uy tín nhất về LLM mã nguồn mở trên APEX (APEX App Lab) **khuyến nghị thẳng: cấu hình Ollama qua Generative AI Service native — không xây plugin riêng.** Vì vậy với 4 nhóm của anh, so sánh thực chất chủ yếu là *tính năng native vs. PL/SQL tự viết*, cộng một lớp mỏng plug-in tùy chọn.

### The native baseline you already own (APEX 26.1 + DB 26ai)

Any plug-in must beat this — and in most categories it already covers the need:

| Native capability | What it does | Category it covers |
|---|---|---|
| **Generative AI Service** (Workspace Utility) | Declarative config for **OpenAI, Cohere, OCI GenAI, + Google** OOTB in 26.1; **Ollama via the OpenAI-compatible provider type** (endpoint = your Ollama host) | 2 — LLM/provider connectivity |
| **`APEX_AI.CHAT` / `APEX_AI.GENERATE`** | PL/SQL API to call the configured LLM; 26.1 lets you **define AI tools inline from PL/SQL** (no shared component) | 1, 2 |
| **AI Assistant / "Show AI Assistant" dynamic action** | Drop a conversational chat panel onto a page | 1, 4 |
| **"Generate Text with AI" dynamic action** | Generate/transform text into a page item | 4 |
| **AI Configurations + RAG Sources** (since 24.2) | Native **RAG**: supplement GenAI calls with your own data declaratively | 1, 3 |
| **AI Interactive Reports (NL2IR)** | Users filter/pivot/chart reports in natural language | 4 |
| **Native tool types** (Retrieve Data / Execute Server-side Code) | Agent tools without custom code | 1 |
| **AI Application Generator** | Build whole apps from a natural-language prompt | (dev-time) |
| **`DBMS_VECTOR` / `DBMS_VECTOR_CHAIN`** (DB, not APEX) | `UTL_TO_TEXT`, `UTL_TO_CHUNKS`, `UTL_TO_EMBEDDING`, `UTL_TO_GENERATE_TEXT` — chunk/embed/generate, **Ollama supported as a local provider** | 3 |
| **Select AI** (Autonomous DB feature) | NL→SQL at the DB layer | 4 (data Q&A) |

_Sources: [Announcing APEX 26.1 GA](https://blogs.oracle.com/apex/announcing-oracle-apex-261), [Expanding AI Choice — providers in 26.1](https://blogs.oracle.com/apex/expanding-ai-choice-with-out-of-the-box-support-for-major-ai-providers-in-oracle-apex-26-1), [Build ad-hoc AI agents in PL/SQL](https://blogs.oracle.com/apex/build-ad-hoc-ai-agents-entirely-in-pl-sql), [AI Config & RAG Sources](https://blogs.oracle.com/apex/blog-ai-config-and-rag-sources), [DBMS_VECTOR docs](https://docs.oracle.com/en/database/oracle/oracle-database/26/arpls/dbms_vector1.html), [Using local LLMs with Oracle DB](https://blogs.oracle.com/coretec/using-local-llms-with-oracle-database)_

### What actually exists as "open-source / plug-in" (verified vs. not)

| Item | Type | Source | Local LLM? | Notes |
|---|---|---|---|---|
| **Ollama** | Open-source LLM runtime | github.com/ollama/ollama (MIT-ish) | ✅ (it *is* the local LLM) | Not an APEX plug-in — the thing APEX connects TO. You already run it. |
| **Community RAG reference implementations** | Blog code / patterns | CloudNueva, APEX App Lab, Oracle-Base, Oracle Devs Medium | ✅ | Copy-paste PL/SQL/SQL, **not installable packages**. Highest-value learning, zero maintenance guarantee. |
| **LangChain + Oracle 23ai/26ai (Python RAG layer)** | Open-source library | LangChain (MIT) | ✅ via Ollama | Lives **outside APEX** (Python service). Only relevant if you want a Python RAG tier, à la the OCR microservice option. |
| **Named third-party APEX "AI plug-in" (region/item)** | APEX plug-in | apex.world | — | **NOT verified to exist as a maintained, dominant package.** `[verify on apex.world]` — searches surfaced blog tutorials and native features, not a canonical downloadable AI plug-in. Do not assume one exists. |
| **OCI Generative AI Agents integration** | Oracle pattern | Oracle blog | ❌ cloud (OCI) | Managed RAG agents; cloud-only, off-strategy for your self-host preference. |

_Sources: [When APEX meets Open source LLMs (App Lab)](https://blog.apexapplab.dev/apex-in-the-ai-era), [Building AI-powered APEX with Ollama & Bedrock (radapex)](https://www.radapex.com/post/building-ai-powered-oracle-apex-apps-with-ollama-and-aws-bedrock), [Local RAG with 23ai + Ollama (Oracle Devs)](https://medium.com/oracledevs/building-a-local-rag-pipeline-with-oracle-23ai-and-ollama-in-visual-studio-code-ba2d03da93af), [23ai Vector Search RAG (CloudNueva)](https://blog.cloudnueva.com/23ai-vector-search-rag), [OCI GenAI Agents + APEX](https://blogs.oracle.com/apex/integrating-oci-generative-ai-agents-with-oracle-apex-apps-for-ragpowered-conversational-experience)_

_Confidence: HIGH that native + config dominates and that community offerings are patterns not packages. `[verify]` on whether any single maintained third-party AI plug-in exists on apex.world — none surfaced across multiple targeted searches, but apex.world's plug-in catalog was not enumerated directly here._

### ⭐ The one genuine open-source contender: UC AI (United Codes)

Follow-up searching surfaced a real, maintained, open-source project that IS an installable package (not just blog code) — correcting the "nothing exists" impression:

- **UC AI** — `github.com/United-Codes/uc_ai`, **license LGPL-3.0**, **PL/SQL-native AI framework** (packages `uc_ai_agents_api`, `uc_ai_prompt_profiles_api`, etc.).
- **Providers:** "OpenAI GPT, Anthropic Claude, Google Gemini, **Ollama**, etc." + OpenAI-compatible endpoints → **works with your self-hosted Ollama** ✅.
- **Features:** LLM text generation, **AI agents**, **tool/function calling** (DB functions as tools), reasoning; a **Responses API** added in the 26.2 release.
- **UC AI Chat Plug-In** — an APEX region plug-in that exposes UC AI agents as an in-app chatbot (import scripts + PL/SQL package, then add a region of type "UC AI Chat").
- **Maintenance:** active — release "26.2" dated **2026-04-23**, 11 releases, ~416 commits, ~47 stars `[verify current numbers]`.
- **Key positioning:** deliberately **does not require DB 23ai/26ai native AI or Enterprise Edition** — it puts provider-agnostic AI into *any* Oracle DB from PL/SQL. That is its core differentiator vs. your native stack.
- _Sources: [UC AI GitHub](https://github.com/United-Codes/uc_ai), [UC AI Chat Plug-In Beta (Hartenfeller)](https://hartenfeller.dev/blog/uc-ai-chat-plugin-beta)_

> ⚠️ **License note:** LGPL-3.0 is copyleft. Using it as a called library/package is generally fine, but bundling/modifying has obligations — `[verify with your legal/compliance before shipping]`. This matters more than for MIT/Apache tools.

---

## Integration Patterns Analysis

### How each option plugs into an APEX 26.1 app

| Pattern | How it connects | Local LLM (Ollama)? | Best for |
|---|---|---|---|
| **Native Generative AI Service + `APEX_AI`** | Declarative provider config (Ollama via OpenAI-compatible type) → `APEX_AI.CHAT/GENERATE` or "Show AI Assistant" DA | ✅ | Default. You already run this. |
| **Native AI Configurations + RAG Sources** | Declarative RAG: attach your data as a RAG source to a GenAI call | ✅ | Category 1+3 RAG **without** hand-writing the retrieval loop |
| **UC AI (PL/SQL framework) + UC AI Chat plug-in** | Install PL/SQL packages + import APEX plug-in; call `uc_ai_agents_api`; add "UC AI Chat" region | ✅ (Ollama provider) | Provider abstraction + agents on DBs where native AI is absent/weak, or when you want one API across OpenAI/Claude/Gemini/Ollama |
| **Custom PL/SQL over `APEX_WEB_SERVICE`/`UTL_HTTP`** | Your current CRM pattern — direct calls to Ollama `/api/generate` | ✅ | Maximum control (your hard-exit / prefix-cache tuning); what you already do |
| **`DBMS_VECTOR_CHAIN` pipeline** | DB-native chunk/embed/search (bge-m3, HNSW) | ✅ | Category 3 — you already run this |
| **External Python (LangChain/FastAPI) tier** | Separate service APEX calls over REST | ✅ | Only if you need Python-side orchestration (e.g. the OCR microservice option) |

### The decision axis: when does a plug-in / framework beat native?

- **Native wins (skip the plug-in) when:** you're on 26.1 + 26ai (you are), single provider (Ollama), and you want declarative chat/RAG/agents — 26.1's inline PL/SQL tools + RAG Sources + Show AI Assistant already cover categories 1, 2, 4 and most of 3.
- **UC AI becomes attractive (watch/selective-adopt) when:** you need **one abstraction across multiple providers** (swap Ollama↔Claude↔OpenAI without rewriting), you want its **agent/tool framework ergonomics**, or you must run on **an older DB/APEX without native AI**. On your exact 26.1+26ai stack it **overlaps** native heavily — adopt only for a concrete gap (multi-provider or its chat UI convenience).
- **Self-build (custom PL/SQL) wins when:** you need the low-level control you already exploit — hard-exit to cut the 2nd LLM call, byte-identical prefix for KV-cache, `num_batch`/`keep_alive` tuning. No plug-in exposes those levers; your CRM agent already proves this path.

### Interoperability & operational notes

- **All roads support Ollama** via the OpenAI-compatible endpoint — provider connectivity (category 2) is a **solved, non-differentiating** problem on 26.1. No plug-in needed just to reach Ollama.
- **RAG UI:** native "Show AI Assistant" + RAG Sources gives a chat panel declaratively; UC AI Chat gives an alternative region. Either avoids hand-building a chat UI.
- **Vector tooling (category 3):** there is **no plug-in that meaningfully improves on `DBMS_VECTOR_CHAIN`** for your case — it's a DB-native capability; "tooling" here means your own helper packages (like your `bodau`, chunk/embed jobs), not a marketplace add-on.

_Confidence: HIGH on native coverage and the UC AI capability set (source-backed). MEDIUM on exact UC AI ⇄ APEX-26.1 version support — `[verify]` the plug-in's supported APEX versions before install._

---

## Architectural Patterns and Design

### Recommended architecture: "native-first, self-build the hot path, plug-in only for a named gap"

**EN —** For your exact stack (APEX 26.1 + DB 26ai + Ollama), the optimal architecture is a **three-tier layering** where each capability is served by the *lightest* option that fully covers it:

```
┌─ UI / declarative tier  ─────────────────────────────────────────┐
│  Native "Show AI Assistant" DA · Generate Text with AI · NL2IR    │  ← categories 1 & 4
│  (chat panel + generative items + NL reports, zero custom UI)      │
├─ Orchestration tier  ────────────────────────────────────────────┤
│  Native APEX_AI.CHAT/GENERATE + AI Configurations + RAG Sources    │  ← category 1 (RAG) + agents
│  (26.1 inline PL/SQL tools; RAG Source = custom SQL over YOUR      │
│   bge-m3/HNSW tables; RAG Sources auto-become agent tools in 26.1) │
│  ── OR, only if you need multi-provider abstraction ──             │
│  UC AI (uc_ai_agents_api) as a drop-in agent layer  [selective]    │
├─ Provider tier  ─────────────────────────────────────────────────┤
│  Native Generative AI Service → Ollama (OpenAI-compatible)         │  ← category 2 (solved)
│  ── OR your custom APEX_WEB_SERVICE call for the tuned hot path ── │
├─ Data / retrieval tier  ─────────────────────────────────────────┤
│  DBMS_VECTOR_CHAIN chunk/embed (bge-m3) · VECTOR(1024) · HNSW      │  ← category 3 (you own this)
└──────────────────────────────────────────────────────────────────┘
```

**VI —** Với stack của anh, kiến trúc tối ưu là **phân tầng 3 lớp**, mỗi năng lực dùng option *nhẹ nhất* phủ đủ: UI khai báo (native DA) → điều phối (native `APEX_AI` + RAG Sources, hoặc UC AI nếu cần đa-provider) → provider (Generative AI Service → Ollama, hoặc custom call cho hot path) → dữ liệu (`DBMS_VECTOR_CHAIN` + HNSW anh đã có).

### The key architectural unlock: native RAG Source = custom SQL over your existing vectors

A native **RAG Source can be a custom SQL query using `VECTOR_DISTANCE`/`VECTOR_EMBEDDING`** — e.g.:

```sql
SELECT chunk_text
FROM   doc_chunks
ORDER  BY VECTOR_DISTANCE(embedding,
          VECTOR_EMBEDDING(bge_m3 USING :APEX$AI_LAST_USER_PROMPT AS DATA), COSINE)
FETCH FIRST :k ROWS ONLY;
```

This means your **existing bge-m3 + HNSW tables feed the native AI Assistant directly — no plug-in, no Python, no re-architecture.** In 26.1 that RAG Source **auto-becomes an agent tool** (Augment or On-Demand), and Oracle recommends On-Demand tools for lower token usage. Reported native benefit: vector RAG Source cut input from ~706 → ~78 tokens for one question — directly relevant to your CPU-prefill bottleneck.

- _Sources: [AI Configurations & RAG Sources (Oracle)](https://blogs.oracle.com/apex/blog-ai-config-and-rag-sources), [Managing AI Configurations and RAG Sources (docs)](https://docs.oracle.com/en/database/oracle/apex/24.2/htmdb/managing-ai-configurations-and-rag-sources.html), [AI Agents in Oracle APEX](https://blogs.oracle.com/apex/ai-agents-in-oracle-apex), [RAG in APEX 24.2 (maxapex)](https://www.maxapex.com/blogs/rag-in-oracle-apex-24-2/)_

### Design principles for choosing per-category

1. **Don't add a dependency to solve a solved problem.** Categories 2 (Ollama connectivity) and 3 (vector search) are fully native on 26.1+26ai — a plug-in here is pure liability.
2. **Prefer declarative for cold paths, custom for hot paths.** Low-traffic chat/RAG → native declarative. The latency-critical CRM agent path → keep your hand-tuned PL/SQL (hard-exit, KV-cache prefix) that no plug-in can replicate.
3. **Adopt a framework only against a named gap.** UC AI earns its place only if/when you need multi-provider portability or must deploy to a DB without native AI — not "just in case."
4. **Migrate RAG Sources → On-Demand tools** in 26.1 to cut tokens (helps prefill).

### Scalability / performance fit for the CPU-only constraint

- Native RAG Source token reduction (706→78) and On-Demand tools both **shrink prefill** — the exact lever that matters on the non-AVX2 CPU (ref your `llm-cpu-prefill-cache-bottleneck` finding).
- No plug-in changes the fundamental CPU physics; architecture choice affects **token count and call count**, which is where your wins actually come from.

### Deployment / operations

- **Native path:** nothing to install/patch — lowest ops surface, moves with APEX upgrades.
- **UC AI path:** install PL/SQL packages + APEX plug-in, track LGPL-3.0 obligations, follow its release cadence (26.2 was 2026-04). One more upgrade axis to manage.
- **Self-build path:** you own the code (already the case) — max control, max responsibility.

_Confidence: HIGH — the native-RAG-over-custom-vectors pattern is documented and directly compatible with your existing tables; the layering follows established APEX 26.1 guidance._

---

## Implementation Approaches and Technology Adoption

### Critical adoption fact: 26.1 native now covers multi-provider too

APEX **26.1 added native, declarative support for Anthropic Claude, Google Gemini, Mistral AI, and Ollama** — on top of the earlier OpenAI / Cohere / OCI GenAI. This **erases the main advantage UC AI used to have** (one abstraction over many providers). On 26.1, UC AI's remaining differentiators shrink to: (a) running on a DB/APEX **without** native AI, (b) its **multi-agent / agent-framework ergonomics**, (c) its chat plug-in UI. For your 26.1 + 26ai stack, (a) doesn't apply.
- _Sources: [Expanding AI Choice in 26.1 (Oracle)](https://blogs.oracle.com/apex/expanding-ai-choice-with-out-of-the-box-support-for-major-ai-providers-in-oracle-apex-26-1), [UC AI docs](https://www.united-codes.com/products/uc-ai/docs/), [UC AI GitHub](https://github.com/United-Codes/uc_ai)_

### Weighted ranking of the real options

Scoring 1–5 on your three criteria — **(a) local/self-host LLM ×2 (highest weight), (b) genuinely open-source ×1.5, (c) APEX 26.1 compat + maintenance ×1.5.** (Native APEX AI is "open" in the sense of no extra license/cost, though not OSS — scored on cost/lock-in spirit.)

| Option | (a) Local LLM ×2 | (b) OSS ×1.5 | (c) 26.1 + maint ×1.5 | Weighted total | Rank |
|---|---|---|---|---|---|
| **Native APEX 26.1 AI** (APEX_AI, RAG Sources, DAs, DBMS_VECTOR) | 5 (10) | 4 (6)* | 5 (7.5) | **23.5** | 🥇 1 |
| **Your custom PL/SQL** (APEX_WEB_SERVICE→Ollama, tuned) | 5 (10) | 5 (7.5) | 5 (7.5) | **25.0** | 🥇 tie/1 (hot path) |
| **UC AI + UC AI Chat plug-in** | 5 (10) | 4 (6) LGPL | 4 (6) `[verify 26.1]` | **22.0** | 🥈 2 |
| **LangChain (Python tier)** | 5 (10) | 5 (7.5) | 2 (3) not-in-APEX | **20.5** | 3 |
| **OCI GenAI Agents** | 1 (2) cloud | 2 (3) | 4 (6) | **11.0** | ✕ off-strategy |

_*Native isn't OSS but carries no extra licence/cost/lock-in beyond APEX itself → scored high on the criterion's intent (freedom to use with self-host). `[verify]` UC AI's declared APEX 26.1 support._

### Adopt / Watch / Skip — per option, relative to what you already have

| Option | Call | Reasoning |
|---|---|---|
| **Native APEX_AI + RAG Sources + native DAs** | ✅ **ADOPT** | Covers categories 1, 2, 4 and most of 3 declaratively; feeds your bge-m3/HNSW via custom-SQL RAG Source; zero new dependency; moves with upgrades. |
| **Your custom PL/SQL hot path** | ✅ **KEEP** | The only way to get hard-exit / KV-cache / batch tuning the CPU needs. No plug-in exposes these. Already proven in the CRM agent. |
| **`DBMS_VECTOR_CHAIN` + your helper packages** (`bodau`, chunk/embed jobs) | ✅ **KEEP** | Category 3 is DB-native; no marketplace tool beats it for you. |
| **UC AI (framework + chat plug-in)** | 🟡 **WATCH** | Genuinely good OSS, supports Ollama, active. But on 26.1 it **overlaps native**; adopt only for a concrete gap — multi-agent ergonomics you can't get native, or a future non-26ai deployment. Mind LGPL-3.0. |
| **LangChain / Python tier** | 🟡 **WATCH** | Only if you already stand up a Python service (e.g., the OCR microservice). Don't add Python just for LLM orchestration APEX does natively. |
| **OCI GenAI Agents / any cloud-only** | ❌ **SKIP** | Violates the self-host preference; cloud egress + cost. |
| **Unverified apex.world "AI plug-ins"** | ❌ **SKIP until verified** | None surfaced as maintained/dominant; don't adopt an unmaintained one over native. |

### Gaps where NO good off-the-shelf option exists → build it yourself

1. **CPU-latency-optimized agent loop** (hard-exit to cut call-2, byte-identical prefix for KV-cache, `num_batch`/`keep_alive`/`num_thread` tuning). No plug-in or native feature exposes this — **your custom PL/SQL is the only answer** (already built).
2. **Vietnamese accent-normalization for search** (`bodau`/`mle_norm`) — domain-specific, self-built, correct.
3. **OCR→RAG ingestion** (from the companion research) — no plug-in; async DBMS_SCHEDULER job.
4. **Deferred-embedding background job** (`CRM_LEADS_EMBED_JOB`) to protect the shared CPU — orchestration no plug-in provides.

### Testing / adoption steps

- **Spike native RAG Source** pointing at `doc_chunks` with a `VECTOR_DISTANCE` custom SQL → confirm the native AI Assistant answers grounded on your data with **no** custom retrieval code. This is the highest-ROI experiment.
- **Migrate any RAG Sources → On-Demand tools** (26.1) and measure token drop.
- Only if a native gap appears, **trial UC AI in a throwaway workspace** and check its declared APEX-26.1 support + LGPL obligations before committing.

## Technical Research Recommendations

### Implementation Roadmap

1. **Lean fully into native 26.1 AI** for new AI surfaces (chat, generative items, NL reports) — declarative, no dependency.
2. **Wire your existing vectors into native RAG Sources** (custom `VECTOR_DISTANCE` SQL) so the native assistant is grounded on your data.
3. **Keep the CRM hot path custom** — do not port it to any framework.
4. **Park UC AI on a watch-list** with one trigger written down: "adopt if we need multi-agent orchestration native can't express, or must deploy to a non-26ai DB."
5. **Re-check apex.world's plug-in catalog directly** to close the `[verify]` on third-party UI plug-ins.

### Technology Stack Recommendations

Native APEX 26.1 AI + DBMS_VECTOR_CHAIN + your tuned PL/SQL = the whole stack. Add UC AI only against a named gap; add Python/LangChain only if a Python service already exists.

### Skill Development Requirements

None new for the native path (your existing SQL/PLSQL + APEX config skills). UC AI would add a small PL/SQL API surface to learn; LangChain adds Python.

### Success Metrics and KPIs

- Categories 1–4 delivered with **zero new runtime dependencies** (native-first success).
- Token count per RAG answer after On-Demand migration (lower = better prefill).
- Number of adopted third-party dependencies kept at **0 unless a written gap justifies one**.

_Confidence: HIGH. The decisive facts (26.1 native multi-provider incl. Ollama; native RAG Source over custom vectors; UC AI real but overlapping) are all multi-source verified. `[verify]` items: UC AI's exact 26.1 support line, and a direct apex.world catalog scan._

---

# AI Plug-ins & Open-Source for Oracle APEX — Research Synthesis

## Executive Summary

**EN —** The direct answer to "is there a plug-in or open-source project for AI on APEX?" is: **a little, but you mostly don't need one.** The APEX AI ecosystem in 2026 is **native-and-configuration-first**, not a plug-in marketplace. On your target — **APEX 26.1 + DB 26ai** — the native stack already delivers all four capability categories: embedded chat (Show AI Assistant DA), LLM connectivity (Generative AI Service now natively supports OpenAI, Cohere, OCI, Anthropic, Gemini, Mistral **and Ollama**), RAG (AI Configurations + RAG Sources that can run a **custom `VECTOR_DISTANCE` SQL over your existing bge-m3/HNSW tables**, auto-promoted to agent tools in 26.1), and AI UI (Generate Text with AI, NL2IR). Adding a third-party dependency to do what native already does is pure liability.

There **is** one legitimate open-source contender worth knowing: **UC AI** by United Codes (`github.com/United-Codes/uc_ai`, LGPL-3.0) — a PL/SQL AI-agent framework that supports Ollama and ships an APEX chat plug-in, actively maintained (release Apr 2026). It's genuinely good, but on 26.1 it **overlaps the native stack** heavily; its standout edge (multi-provider, run-anywhere without 26ai) is now mostly matched by native 26.1. Recommendation: **native-first; keep UC AI on a watch-list for a named gap; keep your latency-critical CRM agent hand-built** because no plug-in exposes the hard-exit / KV-cache / batch levers your non-AVX2 CPU needs.

**VI —** Trả lời thẳng: **có một chút, nhưng phần lớn anh không cần.** Hệ sinh thái AI của APEX 2026 là **native + cấu hình trước**, không phải chợ plugin. Trên **APEX 26.1 + DB 26ai**, stack native đã phủ cả 4 nhóm: chat nhúng (Show AI Assistant), kết nối LLM (Generative AI Service nay hỗ trợ native cả OpenAI, Cohere, OCI, Anthropic, Gemini, Mistral **và Ollama**), RAG (RAG Sources chạy được **custom SQL `VECTOR_DISTANCE` trên bảng bge-m3/HNSW sẵn có**, tự thành agent tool ở 26.1), và AI UI (Generate Text, NL2IR). Thêm dependency bên thứ ba để làm điều native đã làm là gánh nợ. Ứng viên open-source hợp lệ duy nhất: **UC AI** (LGPL-3.0, chạy Ollama, còn bảo trì) — tốt nhưng trùng native trên 26.1 → **native-first; UC AI để watch-list; giữ CRM agent tự xây**.

### Key Technical Findings

- **No dominant third-party AI plug-in market for APEX.** Community output = blog reference code, not installable packages. `[HIGH]`
- **Native 26.1 covers all four categories**, including multi-provider with **Ollama** and RAG over **your own vectors** via custom-SQL RAG Sources. `[HIGH]`
- **UC AI is the one real OSS framework** (LGPL-3.0, Ollama, agents/tools, active) — but overlaps native on 26.1; watch, don't reflexively adopt. `[HIGH; [verify] its 26.1 support]`
- **Categories 2 (connectivity) & 3 (vector) are solved natively** — a plug-in here is liability, not value. `[HIGH]`
- **The real work is in self-build gaps** native/plug-ins don't cover: CPU-latency agent tuning, VI accent-normalization, OCR→RAG ingestion, deferred-embed jobs. `[HIGH]`

### Technical Recommendations (top 5)

1. **Native-first** — build new AI surfaces with APEX 26.1's declarative AI (Show AI Assistant, Generate Text, NL2IR), no dependency.
2. **Ground native RAG on your existing vectors** — add a RAG Source with a `VECTOR_DISTANCE` custom SQL over `doc_chunks`; migrate to On-Demand tools to cut prefill tokens.
3. **Keep the CRM hot path hand-built** — hard-exit, KV-cache prefix, batch tuning; no framework replicates these.
4. **Watch-list UC AI** with one written trigger (multi-agent need, or a non-26ai deployment). Check LGPL-3.0 before shipping.
5. **Close the `[verify]`** by scanning apex.world's plug-in catalog directly for any maintained AI UI plug-in.

## Ranked shortlist (weighted)

| Rank | Option | Verdict | One-line why |
|---|---|---|---|
| 🥇 | **Custom PL/SQL hot path** | KEEP | Only path to CPU-latency levers |
| 🥇 | **Native APEX 26.1 AI** | ADOPT | Covers all 4 categories, zero dependency |
| 🥈 | **UC AI + chat plug-in** | WATCH | Real OSS, Ollama-ready, but overlaps native on 26.1 |
| 3 | **LangChain / Python tier** | WATCH | Only if a Python service already exists |
| ✕ | **OCI GenAI Agents / cloud-only** | SKIP | Breaks self-host preference |

## Category-by-category: what to use

| Category | Best choice for your stack | Plug-in needed? |
|---|---|---|
| 1. Chat / RAG assistant | Native Show AI Assistant + RAG Sources (custom vector SQL) | ❌ No |
| 2. LLM / provider connectivity | Native Generative AI Service → Ollama | ❌ No |
| 3. Vector search / embeddings | `DBMS_VECTOR_CHAIN` + your helper packages | ❌ No |
| 4. AI UI components | Native Generate Text with AI, NL2IR | ❌ No (UC AI Chat optional) |
| (hot path) latency-tuned agent | Custom PL/SQL | ❌ Self-build |

## Risks & Open Questions to validate

- **UC AI ⇄ APEX 26.1** declared compatibility and **LGPL-3.0** obligations before any adoption `[verify]`.
- **apex.world catalog** not directly enumerated here — a maintained AI UI plug-in may exist; scan before concluding "none" `[verify]`.
- Native **RAG Source performance** with your bge-m3 model + `:APEX$AI_LAST_USER_PROMPT` binding — validate the embedding call path on your CPU.
- Provider/version drift: native provider list expands per release; re-check at each APEX upgrade.

## Methodology & Source Verification

Five-stage technical research (scope → landscape → integration → architecture → implementation), grounded in live sources (July 2026). No plug-in names or repos were invented; the only named third-party project (UC AI) was verified on its GitHub + docs. Unconfirmed facts marked `[verify]`.

**Primary sources:**
- [Announcing APEX 26.1 GA](https://blogs.oracle.com/apex/announcing-oracle-apex-261) · [Expanding AI Choice — providers in 26.1](https://blogs.oracle.com/apex/expanding-ai-choice-with-out-of-the-box-support-for-major-ai-providers-in-oracle-apex-26-1) · [Build ad-hoc AI agents in PL/SQL](https://blogs.oracle.com/apex/build-ad-hoc-ai-agents-entirely-in-pl-sql)
- [AI Configurations & RAG Sources](https://blogs.oracle.com/apex/blog-ai-config-and-rag-sources) · [Managing AI Configurations and RAG Sources (docs)](https://docs.oracle.com/en/database/oracle/apex/24.2/htmdb/managing-ai-configurations-and-rag-sources.html) · [AI Agents in Oracle APEX](https://blogs.oracle.com/apex/ai-agents-in-oracle-apex) · [RAG in APEX 24.2 (maxapex)](https://www.maxapex.com/blogs/rag-in-oracle-apex-24-2/)
- [UC AI GitHub](https://github.com/United-Codes/uc_ai) · [UC AI docs](https://www.united-codes.com/products/uc-ai/docs/) · [UC AI Chat Plug-In (Hartenfeller)](https://hartenfeller.dev/blog/uc-ai-chat-plugin-beta) · [Build Real AI with PL/SQL, no 23ai](https://hartenfeller.dev/blog/real-ai-solutions-oracle-plsql)
- [When APEX meets Open-source LLMs (App Lab)](https://blog.apexapplab.dev/apex-in-the-ai-era) · [Deep dive into APEX AI components (App Lab)](https://blog.apexapplab.dev/how-the-new-apex-ai-features-work) · [Building AI-powered APEX with Ollama (radapex)](https://www.radapex.com/post/building-ai-powered-oracle-apex-apps-with-ollama-and-aws-bedrock)
- [DBMS_VECTOR docs](https://docs.oracle.com/en/database/oracle/oracle-database/26/arpls/dbms_vector1.html) · [Using local LLMs with Oracle DB](https://blogs.oracle.com/coretec/using-local-llms-with-oracle-database) · [Local RAG with 23ai + Ollama (Oracle Devs)](https://medium.com/oracledevs/building-a-local-rag-pipeline-with-oracle-23ai-and-ollama-in-visual-studio-code-ba2d03da93af)

---

**Technical Research Completion Date:** 2026-07-04
**Source Verification:** All claims cited; unverified license/version/maintenance marked `[verify]`; no invented plug-ins/repos
**Overall Confidence:** HIGH on native coverage and the native-vs-UC-AI verdict; `[verify]` on UC AI's exact 26.1 support and a direct apex.world catalog scan.
