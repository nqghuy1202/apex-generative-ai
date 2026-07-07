---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments: []
workflowType: 'research'
lastStep: 6
research_type: 'technical'
research_topic: 'Metadata-driven NL→SQL architecture for Oracle APEX 26.1 + DB 26ai'
research_goals: 'Replace hand-coded per-table crm_nl2sql_pkg with a scalable, metadata/semantic-layer-driven NL→SQL engine that covers thousands of tables without per-table code, while keeping the CPU-only single-call latency profile and current safety guarantees.'
user_name: 'Gia Huy'
date: '2026-07-07'
web_research_enabled: true
source_verification: true
---

# Research Report: technical

**Date:** 2026-07-07
**Author:** Gia Huy
**Research Type:** technical

---

## Research Overview

**Vấn đề / Problem.** The current `crm_nl2sql_pkg` is fast (WARM 1.8–2.4s, 1 LLM call) and safe (12/12 accuracy, 4/4 adversarial refused) but **does not scale**: every new table requires hand-written column/op/intent whitelists plus SQL skeletons. With thousands of tables and hundreds of thousands of columns, the per-table hardcoding model is untenable.

**Research goal.** Find a **metadata-driven / semantic-layer** NL→SQL architecture that (a) covers many tables without per-table code, (b) keeps the CPU-only single-call latency profile on server B (qwen2.5:3b-instruct, no AVX2), and (c) preserves the current safety guarantees (whitelisted, bound, read-only, DML-refusing).

**Methodology.** Current (2025–2026) web sources with source verification; every architecture recommendation states its **latency impact** and **safety impact**; unverified Oracle 26.1/26ai API details are marked `[unverified]` with a live-DB confirmation checklist at the end.

**Headline finding (drives the whole report).** Oracle Database **26ai ships a native, metadata-driven NL→SQL engine — Select AI (`DBMS_CLOUD_AI`)** — that already does the single hardest part of this project: it **automatically detects the relevant tables for a question and sends only those tables' metadata** (column names, data types, table/column comments, constraints — never row data) to the LLM ([Oracle Select AI User's Guide 26ai](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/select-ai.html); [Select AI by release](https://blogs.oracle.com/machinelearning/select-ai-by-release-a-quick-guide-to-26ai-and-19c-capabilities)). The research therefore pivots from "build a schema-retrieval engine from scratch" to "**should we adopt Select AI's metadata-driven core, wrap it in our safety layer, or build a lean equivalent**" — evaluated against the CPU-only local-LLM constraint (whose Select AI compatibility is the #1 item to verify).

---

## Technical Research Scope Confirmation

**Research Topic:** Metadata-driven NL→SQL architecture for Oracle APEX 26.1 + DB 26ai
**Research Goals:** Replace hand-coded per-table `crm_nl2sql_pkg` with a scalable metadata/semantic-layer-driven engine covering thousands of tables, keeping CPU-only single-call latency and current safety guarantees.

**Scope (7 questions → 5 standard axes):** Architecture (table-coverage strategy, semantic-layer design) · Implementation (safe SQL generation from metadata, maintenance economics) · Technology Stack (APEX 26.1 native vs uc_ai vs custom PL/SQL) · Integration (schema/context retrieval, RAG over the data dictionary) · Performance (latency tiering fast/slow path on CPU).

**Scope Confirmed:** 2026-07-07

---

## Technology Stack Analysis

This section maps the technology landscape for large-schema NL→SQL as of mid-2026, focused on what is usable inside an Oracle 26ai + APEX 26.1 + local-Ollama stack.

### The three families of NL→SQL over large schemas

Current research and product practice converge on three families, all of which reject "paste the whole schema into the prompt" as unworkable past a few dozen tables:

1. **Native database NL→SQL (Oracle Select AI / `DBMS_CLOUD_AI`).** The database itself owns the metadata catalog and the schema-selection step. In **26ai**, Select AI *automatically detects relevant tables* and sends only their metadata (column names, types, table/column comments, constraints — **no row data**) to the configured LLM, then generates/runs/narrates/explains SQL. Actions: `showsql`, `runsql`, `narrate`, `chat`, `summarize`. 26ai adds **NL2SQL feedback** (users correct results via SQL CLI or PL/SQL) to improve future generations.
   _Source: [Select AI User's Guide 26ai](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/select-ai.html), [DBMS_CLOUD_AI Package](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/dbms-cloud-ai-package.html), [Select AI by release](https://blogs.oracle.com/machinelearning/select-ai-by-release-a-quick-guide-to-26ai-and-19c-capabilities)._
   _Confidence: High on capability; **`[unverified]` on our stack** — must confirm Select AI runs on non-Autonomous on-prem 26ai and accepts a local Ollama provider (see verification checklist)._

2. **Retrieval-augmented schema linking (RASL / SchemaRAG / CSR-RAG family).** When the DB does not do it for you, you build a **vector index over schema metadata** (per-table and per-column descriptions, embedded) and retrieve only the relevant fragments per question, keeping the prompt within a fixed token budget. This is exactly the pattern this repo already has the parts for (bge-m3 embeddings + `VECTOR_DISTANCE`).
   - **RASL** decomposes schema+metadata into discrete semantic units, indexes each separately, prioritizes table identification while using column-level info, and caps retrieved tables to a manageable context budget ([RASL, Amazon Science](https://www.amazon.science/publications/rasl-retrieval-augmented-schema-linking-for-massive-database-text-to-sql)).
   - **SchemaRAG** — schema-aware RAG framework for text-to-SQL ([ACM SIGMOD](https://dl.acm.org/doi/10.1145/3786696)).
   - **CSR-RAG** splits enterprise-scale retrieval into semantic context + DB structure + table connectedness, combined via hypergraph ranking ([CSR-RAG](https://arxiv.org/pdf/2601.06564)).
   - **SchemaGraphSQL** uses pathfinding graph algorithms for join-path linking on large DBs ([arXiv 2505.18363](https://arxiv.org/pdf/2505.18363)); **R2D2** retrieves table *segments* not whole tables; **EnrichIndex/Pneuma** enrich the retrieval index with LLM-generated metadata.
   _Source: as cited. Confidence: High — this is the mainstream 2025–2026 approach and is stack-compatible today._

3. **Semantic-layer NL→SQL (dbt Semantic Layer / AtScale / Semantic Views).** Instead of raw tables, the LLM targets a **curated semantic model** (business metrics, dimensions, declared joins, synonyms, RLS) — SQL is generated against governed definitions, not the physical schema. The accuracy evidence here is the strongest in the field:
   - Semantic-layer documentation improves accuracy **+17 to +23 points** across frontier models; a semantic-layer+query-engine system hit **92.5%** vs **20%** for bare schema+PK/FK ([Semantic Layers benchmark, arXiv 2604.25149](https://arxiv.org/pdf/2604.25149)).
   - An LLM-generated semantic catalog improved SQL accuracy **up to +27%**; dbt Semantic Layer NL answers ~**83%** accurate ([dbt Labs](https://www.getdbt.com/blog/semantic-layer-as-the-data-interface-for-llms)).
   - "For queries covered by a well-modeled semantic layer, accuracy approaches or hits 100%" — recommended precisely for **large, complex, messy enterprise datasets** ([datalakehousehub](https://datalakehousehub.com/blog/2026-05-semantic-layers-text-to-sql/), [dbt 2026 benchmark](https://docs.getdbt.com/blog/semantic-layer-vs-text-to-sql-2026)).
   - Oracle 26ai's own answer to this is **Semantic Views**, which Select AI can consume.
   _Source: as cited. Confidence: High on the accuracy claim; this is the decisive lever for correctness at scale._

**Cross-cutting takeaway.** The accuracy of large-schema NL→SQL is dominated **not** by the LLM size but by **how good the metadata/semantic descriptions are** and **how precisely the right tables are retrieved** before generation. This is favorable for a CPU-only 3B model: invest in the metadata catalog + retrieval, not a bigger model.

### Database and storage technologies (in-stack)

- **Oracle DB 26ai** — vector datatype `VECTOR(1024, FLOAT32)`, HNSW indexes, `VECTOR_DISTANCE`/`FETCH APPROX`, `DBMS_VECTOR_CHAIN` chunking, **Select AI / `DBMS_CLOUD_AI`**, **Semantic Views**, and the data dictionary (`ALL_TAB_COMMENTS`, `ALL_COL_COMMENTS`, `ALL_CONSTRAINTS`, `ALL_TAB_COLUMNS`) as the free source of a metadata catalog. _Source: [Select AI 26ai](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/select-ai.html)._
- **bge-m3 via Ollama** (`apex-embed`, dim 1024, COSINE) — already wired; the embedding engine for a schema-metadata vector index.
- **Metadata catalog store** — a small set of Oracle tables (`nl2sql_table`, `nl2sql_column`, `nl2sql_join`, `nl2sql_synonym`) holding curated descriptions + embeddings; this becomes the runtime-read registry that replaces hardcoded PL/SQL whitelists.

### Frameworks / packages (in-stack)

- **APEX 26.1 native AI** — "AI Configurations" renamed **AI Agents**; **AI Tools** (Retrieve Data via SQL/Function/static, Execute Server-side Code, Execute Client-side Code); **RAG sources** renamed **"Augment System Prompt"** tools, both Augment and On-Demand tools can run RAG via `VECTOR_DISTANCE`; `APEX_AI.generate`/`chat` now prefer `p_agent_static_id` (`p_config_static_id` deprecated but works); native providers now include Claude/Gemini/Mistral; **APEXlang** declarative generative dev. _Source: [APEX 26.1 new features](https://docs.oracle.com/en/database/oracle/apex/26.1/htmrn/new-features.html), [AI Agents in APEX](https://blogs.oracle.com/apex/ai-agents-in-oracle-apex), [AI config & RAG sources](https://blogs.oracle.com/apex/blog-ai-config-and-rag-sources)._
- **uc_ai (United Codes)** — `generate_text` with `p_response_json_schema` + zero tools = exactly 1 LLM call; the structured-output path already proven in `crm_nl2sql_pkg`. Remains the low-latency single-call primitive if we do NOT use Select AI.
- **Custom PL/SQL** — the safety/validation/binding layer (`DBMS_SQL` bind-by-name, `bodau()` accent-strip, row caps) is bespoke and stays regardless of which generation engine is chosen.

### Local LLM (fixed constraint)

- **qwen2.5:3b-instruct** on Ollama, CPU-only 2×Xeon E5-2680 v2, no AVX2, prefill-dominated. The stack must keep NL→SQL at ~1 call for simple questions. Any engine that fans out to N LLM calls (agentic tool loops) is penalized by prefill and is reserved for the "slow path" only. _Source: project memory `llm-cpu-prefill-cache-bottleneck`, `uc-ai-nl2sql-crm-leads`._

### Technology adoption trend

The 2026 consensus (dbt, AtScale, academic benchmarks) is a **hybrid**: a **semantic layer for governed/high-value questions** + **RAG schema-linking for the long tail** of ad-hoc tables — not one or the other. Oracle has folded both into the database (Semantic Views + Select AI auto table-detection), which is the strategically aligned direction for an Oracle-native shop. _Source: [dbt 2026 benchmark](https://docs.getdbt.com/blog/semantic-layer-vs-text-to-sql-2026), [Coalesce playbook](https://coalesce.io/data-insights/semantic-layers-2025-catalog-owner-data-leader-playbook/)._

## Integration Patterns Analysis

How the pieces connect: the LLM ↔ database contract, the metadata ↔ engine contract, and the APEX ↔ engine contract.

### Pattern A — Native: Select AI profile as the integration control plane

Select AI centralises everything in an **AI profile** created via `DBMS_CLOUD_AI.CREATE_PROFILE` / `SET_PROFILE`. The profile is the control plane: AI provider + model, credentials (Web Credential/wallet), metadata options, and — critically — the **`object_list`**.

- **`object_list` is the security boundary.** The LLM only ever receives schema metadata (column names, types, comments, constraints) for the objects listed in `object_list`. It is a **native, declarative table whitelist** — this is the single most important integration fact for us: it replaces the hand-coded per-table whitelist in `crm_nl2sql_pkg` with a profile attribute. _Source: [Select AI Concepts](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/select-ai-concepts.html), [Manage AI Profiles](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/manage-ai-profiles.html)._
- **26ai auto table-detection operates *within* `object_list`.** You may list many objects; 26ai detects the relevant ones per question and sends only their metadata to the LLM — bounding prompt size without you pre-selecting tables per query. _Source: [Select AI by release](https://blogs.oracle.com/machinelearning/select-ai-by-release-a-quick-guide-to-26ai-and-19c-capabilities)._
- **Metadata toggles** `"comments": true`, `"constraints": true`, `"annotations": true` control how rich the sent metadata is; accuracy tracks metadata richness. _Source: [Best practices to improve NL2SQL accuracy](https://blogs.oracle.com/machinelearning/best-practices-to-improve-nl2sql-accuracy-with-oracle-select-ai), [Making Select AI smarter with annotations](https://blogs.oracle.com/coretec/making-select-ai-smarter-with-database-annotations)._
- **No row data ever leaves the DB** — only schema metadata. Good for governance. _Source: [Select AI Concepts](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/select-ai-concepts.html)._

### ⚠️ Pattern A caveat — on-prem + Ollama provider (the #1 verification risk)

- Select AI / `DBMS_CLOUD_AI` **is available on-prem** (Database 19c and 26ai as a PL/SQL package), not only Autonomous. _Source: [Using local LLMs with Oracle Database](https://blogs.oracle.com/coretec/using-local-llms-with-oracle-database), [Running Oracle's Private AI Stack On-Premises](https://sillidata.com/2026/04/13/running-oracles-private-ai-stack-on-premises/)._
- **BUT** the provider story on-prem is nuanced `[unverified for our exact build]`: `DBMS_VECTOR.UTL_TO_GENERATE_TEXT` explicitly supports `provider => 'ollama'` (and `'openai'` with `host:'local'` for any OpenAI-compatible server), whereas one source notes that raw path "doesn't give you the Select AI NL2SQL syntax." The practical integration route for our stack is therefore: **point a Select AI profile at Ollama's OpenAI-compatible endpoint** (`provider => 'openai'`, base URL = `http://172.25.10.38:11434/v1`) rather than a dedicated `ollama` provider for NL2SQL. _Source: [Using local LLMs with Oracle Database](https://blogs.oracle.com/coretec/using-local-llms-with-oracle-database)._
- **Verification required on the live DB** (checklist at end): (1) does `DBMS_CLOUD_AI.CREATE_PROFILE` on this 26ai build accept `provider => 'ollama'` or require the OpenAI-compatible route; (2) does the auto table-detection step incur an **extra internal LLM call** (latency); (3) does 26ai auto-detection need a vector index on the metadata to scale to a large `object_list`.

### Pattern B — DIY: RAG schema-linking over the data dictionary (the fallback / long-tail)

When Select AI is unavailable or too slow for a case, replicate its core with in-stack parts — this is the RASL/SchemaRAG pattern grounded in Oracle:

1. **Offline catalog build.** Read `ALL_TAB_COMMENTS`, `ALL_COL_COMMENTS`, `ALL_TAB_COLUMNS`, `ALL_CONSTRAINTS` → compose one VI-with-diacritics description sentence per table (and per column group) → embed with **bge-m3 (`apex-embed`)** → store in a `nl2sql_catalog` table with a `VECTOR(1024)` column + HNSW index.
2. **Online retrieval.** Per question: embed the question, `VECTOR_DISTANCE` top-k tables/columns from the catalog → inject only those into the prompt. Fixed token budget regardless of total schema size. _Source: [RASL](https://www.amazon.science/publications/rasl-retrieval-augmented-schema-linking-for-massive-database-text-to-sql), [SchemaRAG](https://dl.acm.org/doi/10.1145/3786696)._
3. **Join declaration reuse.** Declared joins live in a `nl2sql_join` table (FK graph seeded from `ALL_CONSTRAINTS`, curated for the important paths) so join paths are declared once and reused — the SchemaGraphSQL idea done declaratively. _Source: [SchemaGraphSQL](https://arxiv.org/pdf/2505.18363)._

**Integration contract for B:** identical single-call uc_ai `generate_text` + `p_response_json_schema` as today — only the *prompt context* becomes retrieved-not-hardcoded. Keeps the 1-call latency profile.

### Pattern C — APEX 26.1 as the front-door integration

- APEX 26.1 **AI Agents** + **AI Tools** ("Retrieve Data" via SQL/Function, "Augment System Prompt" = RAG source via `VECTOR_DISTANCE`, "Execute Server-side Code") can wrap either engine. `APEX_AI.generate/chat` now prefer `p_agent_static_id`. _Source: [AI Agents in APEX](https://blogs.oracle.com/apex/ai-agents-in-oracle-apex), [AI config & RAG sources](https://blogs.oracle.com/apex/blog-ai-config-and-rag-sources)._
- **Integration decision:** for the low-latency NL→SQL Q&A, call the engine directly in PL/SQL (as `crm_nl2sql_pkg` does today) — the APEX AI-Agent tool-loop adds the second uncacheable LLM call (`UNTRUSTED-DATA` marker) we already proved is the latency killer. Use APEX AI-Agent only for the conversational/multi-tool UX, not the hot NL→SQL path. _Source: project memory `apex-untrusted-data-marker-cache-killer`._

### The metadata IS the integration contract (semantic layer, natively)

The strongest cross-cutting integration insight: in Oracle, **table/column `COMMENTS` + `ANNOTATIONS` are the semantic layer** — the same metadata feeds Select AI (Pattern A), the RAG catalog (Pattern B), and any APEX tool (Pattern C). Investing once in high-quality VI/EN comments+annotations on the important tables pays off across all three engines. This makes the semantic layer an **asset in the database**, not code in a package. _Source: [Making Select AI smarter with annotations](https://blogs.oracle.com/coretec/making-select-ai-smarter-with-database-annotations), [Best practices NL2SQL accuracy](https://blogs.oracle.com/machinelearning/best-practices-to-improve-nl2sql-accuracy-with-oracle-select-ai)._

## Architectural Patterns Analysis

### The core architectural decision

Three whole-system shapes were on the table (from Step 2's three families). Evaluated against our constraints:

| Shape | Per-table code? | Accuracy at scale | Latency on CPU | Fit |
|---|---|---|---|---|
| **A. Select AI native** (`DBMS_CLOUD_AI` profile) | **None** — `object_list` + comments | High (95.5% cloud study; tracks metadata quality) | `[unverified]` — auto-detect may add an internal call; provider on-prem needs the OpenAI-compat route | Best *if* it runs on our on-prem 26ai + Ollama |
| **B. DIY metadata-RAG** (bge-m3 catalog + uc_ai 1-call) | **None** — catalog rows, not code | High if catalog descriptions are good (RASL/SchemaRAG) | **1 call, ~2–4s** — same profile as today | Guaranteed to work in-stack; fallback if A fails |
| **C. Keep hardcoded skeletons** (today) | **Per table** ❌ | High but only for coded tables | Fastest (1.8s) | Does not scale — reject as the general solution |

_Latency anchor: independent 26ai Select AI study = mean **3,906 ms**, **94.5% of it LLM generation** ([DZone study](https://dzone.com/articles/select-ai-oracle-26ai-openai), [TechRxiv](https://www.techrxiv.org/doi/full/10.36227/techrxiv.177281023.37874227/v1)). Confirms our own finding: minimise call count and prompt tokens; model size is secondary to metadata/retrieval quality._

**Recommended target = a tiered hybrid, engine-pluggable.** Do NOT bet the whole system on one engine before the on-prem Select AI + Ollama verification. Build a thin **NL→SQL orchestrator** (`nl2sql_router`) with a **pluggable generation backend** (Select AI *or* uc_ai-1-call), fed by **one shared metadata asset** (DB comments/annotations + a bge-m3 catalog). This lets you adopt Select AI where it works and fall back to DIY-RAG everywhere else — with zero per-table code either way.

### Target architecture (text diagram)

```
                         ┌─────────────────────────────────────────────┐
   User question (VI) ──▶│  nl2sql_router  (PL/SQL, 1 entry point)      │
                         │  1. is_dml_question? ──▶ refuse (0 LLM calls) │
                         │  2. classify tier (deterministic, no LLM)     │
                         └───────────────┬──────────────┬───────────────┘
                                         │ FAST         │ SLOW
                                         │ (governed)   │ (long-tail / cross-table)
              ┌──────────────────────────▼───┐     ┌────▼─────────────────────────────┐
              │ SEMANTIC CORE (curated)       │     │ METADATA CATALOG (auto/all schema)│
              │ nl2sql_table / column / join  │     │ bge-m3 vectors over ALL_*_COMMENTS│
              │ synonyms VI/EN, RLS, grain    │     │ HNSW; VECTOR_DISTANCE top-k tables│
              └──────────────┬────────────────┘     └────────────┬──────────────────────┘
                             │  inject compact, stable prefix     │ inject retrieved schema
                             ▼                                    ▼
                    ┌──────────────────── Generation backend (pluggable) ─────────────────┐
                    │  Option A: Select AI  DBMS_CLOUD_AI (showsql, object_list-bounded)   │
                    │  Option B: uc_ai generate_text + p_response_json_schema  (1 call)    │
                    └───────────────────────────────┬─────────────────────────────────────┘
                                                     ▼
              ┌──────────────────────────────────────────────────────────────────────────┐
              │ SAFETY GATE (PL/SQL, unchanged philosophy):                                │
              │  whitelist cols/ops against catalog · bind ALL literals · read-only ·      │
              │  row cap · reject anything not SELECT · apply RLS predicate                 │
              └───────────────────────────────┬──────────────────────────────────────────┘
                                               ▼
                                   DBMS_SQL bind-by-name · execute · format VI answer
```

### Decision rule — which tables get the "governed core" vs "long-tail" treatment

> **Curate (semantic core)** a table when it is: (a) high query volume / business-critical (CRM_LEADS, sales, inventory…), (b) has ambiguous or coded columns needing synonyms/RLS, or (c) demands ~100% accuracy. **Leave to the auto catalog (long-tail)** the thousands of low-frequency tables where "good enough" retrieval-based answers are acceptable.

**Recommended default for this ERP:** start with a **curated core of ~20–50 tables/views** (the ones users actually ask about) + **auto-catalog the entire schema** for coverage. This is the field consensus (semantic layer for high-value, RAG for the long tail — [dbt 2026 benchmark](https://docs.getdbt.com/blog/semantic-layer-vs-text-to-sql-2026)). You do **not** hand-write code for either tier — the core is *curated rows/comments*, the long tail is *auto-harvested comments*.

### Latency tiering — the routing signal

The router classifies **before any LLM call**, using deterministic signals (no model):

- **FAST path (target ~2–4s, 1 LLM call):** question maps to a **single governed table/view** (matched by synonym/keyword against the semantic core) → inject that table's compact, **byte-stable** metadata prefix (KV-cache friendly) → 1-call generation → safety gate. This is essentially today's `crm_nl2sql_pkg` speed, generalised via the registry.
- **SLOW path (accept higher latency):** question is cross-table, ambiguous, or hits only the long tail → run **catalog retrieval** (vector top-k, no LLM — pure `VECTOR_DISTANCE`) → inject retrieved schema → 1-call generation → safety gate. Retrieval adds DB time, **not** an extra LLM call, so the CPU prefill penalty is avoided; only the prompt is a bit larger.
- **Routing signal (deterministic):** (1) `is_dml_question` → refuse; (2) count of governed-table synonym hits: exactly 1 → FAST; 0 or ≥2 (cross-table) → SLOW. Optionally a tiny cached classifier later, but start rule-based to keep 0 extra calls.

**Key CPU insight:** keep the *number of LLM calls = 1* on both paths. The slow path is "slower" only because of a larger prompt + a DB vector search, never a second uncacheable LLM call. Reserve any 2-call agentic flow for genuinely conversational UX, not NL→SQL. _Source: project memory `apex-untrusted-data-marker-cache-killer`, `llm-cpu-prefill-cache-bottleneck`._

### Recommended semantic-layer schema (the metadata registry)

Replaces hardcoded PL/SQL whitelists with runtime-read rows. Sequences + `.NEXTVAL` per project convention.

```
nl2sql_table
  tab_id (PK, seq)         table_owner        table_name
  logical_name_vi/_en      description_vi/_en (feeds prompt + embedding)
  grain (one row = ...)    tier ('CORE'|'LONGTAIL')
  rls_predicate  (e.g. 'emp_id = :app_user_emp'  — appended by safety gate)
  is_enabled     embedding VECTOR(1024)  (for the catalog / retrieval)

nl2sql_column
  col_id (PK, seq)  tab_id (FK)  column_name  data_type
  logical_name_vi/_en   description_vi/_en   is_filterable  is_aggregatable
  is_groupable  allowed_ops (CSV: '=,<,>,LIKE,IN')  code_map_json (coded→label)
  is_pii (mask/omit)

nl2sql_join
  join_id (PK, seq)  left_tab_id (FK)  right_tab_id (FK)
  join_condition  ('l.co_id = r.co_id')   cardinality  is_preferred
  -- seeded from ALL_CONSTRAINTS, curated for the important paths; declared once, reused

nl2sql_synonym
  syn_id (PK, seq)  object_type ('TABLE'|'COLUMN'|'VALUE')  ref_id
  term_vi/_en  (bodau()-normalised)  weight
  -- powers deterministic routing + fixes VI phrasing → schema mapping

nl2sql_feedback   (optional, mirrors Select AI 26ai feedback)
  fb_id (PK, seq)  question  chosen_sql  verdict  created_by  created_at
```

**Why this scales:** onboarding a new table = **INSERT rows + write good comments/annotations**, optionally embed — **no PL/SQL, no deploy**. The three fixed SQL skeletons in `crm_nl2sql_pkg` generalise into skeletons parameterised by registry rows (single-table count/aggregate/list stay; joins come from `nl2sql_join`). For Pattern A, most of this maps directly onto Select AI's native `object_list` + `COMMENTS` + `ANNOTATIONS`, so the registry doubles as the source you generate the Select AI profile from.

### Anti-patterns to avoid (from the research)

- **Dumping the whole schema into the prompt** — impossible past a few dozen tables; blows prefill on CPU. Always retrieve/bound. _Source: [RASL](https://www.amazon.science/publications/rasl-retrieval-augmented-schema-linking-for-massive-database-text-to-sql)._
- **Free-form raw-SQL from the LLM without a safety gate** — reintroduces injection/DML risk that the current design eliminates (see Step 5).
- **A second LLM call to "read the result"** — the proven CPU latency killer; format answers in PL/SQL instead.
- **Bigger model as the accuracy fix** — the evidence says metadata/semantic quality beats model size for NL→SQL. _Source: [Semantic Layers benchmark](https://arxiv.org/pdf/2604.25149)._

## Implementation Research

### Safe SQL generation from a *dynamic* table set — the three options

The hard part of going metadata-driven: today's safety comes from hardcoded whitelists; once tables are dynamic, safety must derive from the **registry/catalog + database-enforced read-only**, not from code. Three generation strategies compared:

| Strategy | How safety is kept | Latency | Verdict |
|---|---|---|---|
| **(i) Constrained-JSON intermediate** (current, generalised) | LLM returns `{intent, table, filters[], group_by, sort_by, limit}` with **enum values drawn from the registry**; PL/SQL validates every col/op against `nl2sql_column.allowed_ops` and builds the SQL from fixed skeletons; **all literals bound**. LLM never emits SQL text. | 1 call, low | ✅ **Recommended default** — strongest safety, unchanged philosophy, just registry-driven enums instead of hardcoded ones |
| **(ii) Guarded raw-SQL** (Select AI `showsql` / uc_ai raw) | LLM emits SQL; PL/SQL **parses & validates** it: must be single `SELECT`, tables ⊂ `object_list`/registry, no DDL/DML, add row cap + RLS. Relies on a robust SQL parser. | 1 call, low | ⚠️ Use only for the **long-tail/complex joins** the JSON schema can't express; higher validation burden |
| **(iii) Hybrid** | JSON-intermediate for FAST path; guarded raw-SQL (or Select AI `showsql`) for SLOW/cross-table path where fixed skeletons are insufficient. | 1 call | ✅ Matches the tiered architecture |

**Recommendation:** keep **(i) as the safe default** (it is why the current design refused 4/4 adversarial), add **(ii) behind the safety gate** only for the long-tail slow path. This is exactly the tiered hybrid.

### Defense-in-depth (must hold regardless of engine)

The 2026 consensus: prompt-level guardrails are necessary but **not sufficient** — enforce safety where it cannot be bypassed. _Source: [Prompt injection is the new SQL injection (Cisco)](https://blogs.cisco.com/ai/prompt-injection-is-the-new-sql-injection-and-guardrails-arent-enough), [Datadog LLM guardrails](https://www.datadoghq.com/blog/llm-guardrails-best-practices/)._

1. **DB-enforced read-only** — execute all generated SQL as a **dedicated read-only DB user** (only SELECT grants on the exposed views) so a hallucinated `UPDATE/DELETE` is rejected by the database, not just by our parser. Strictly more reliable than prompt guardrails. _Source: [Self-healing SQL pipeline](https://arxiv.org/pdf/2604.16511)._
2. **Registry/`object_list` allowlist** — tables/columns not in the registry (or Select AI `object_list`) are invisible + unusable. Native security boundary in Pattern A.
3. **Structured-output validation** — enum-constrained JSON validated in PL/SQL before any SQL is built. _Source: [Guardrails AI / structured output](https://aisecurityandsafety.org/en/guides/llm-guardrails/)._
4. **Bind every literal** (`DBMS_SQL` bind-by-name) — no user/LLM string ever concatenated into SQL → injection-proof.
5. **Deterministic pre-checks** — `is_dml_question` refuse + row cap + `refuse` intent (already proven, keep).
6. **RLS predicate** appended from `nl2sql_table.rls_predicate` so row-level security holds even on dynamically chosen tables (e.g. sales rep sees only own leads). Prefer Oracle **VPD/OLS** on the exposed views for defense-in-depth.
7. **Audit** — log question + chosen SQL + result count (the `nl2sql_feedback` table doubles as audit + a training signal, mirroring Select AI 26ai feedback).

**Net safety statement:** the metadata-driven design is **as safe or safer** than the hardcoded one, because the allowlist becomes data (auditable, testable) and read-only is enforced by the DB, not by remembering to hand-code a whitelist per table.

### Maintenance & scale economics (why the rewrite pays)

Estimated effort to **onboard one new table** to NL→SQL:

| Approach | Steps to add a table | Rough effort | Deploy? |
|---|---|---|---|
| **Current (hardcoded)** | Write column whitelist + op whitelist + SQL skeleton(s) + few-shot examples in PL/SQL; recompile package; retest | **~0.5–2 days/table** of dev | Yes (code deploy) |
| **Metadata-driven core (Pattern B/i)** | INSERT `nl2sql_table`/`column`/`synonym` rows + write good VI/EN comments; (optional) run embed job | **~0.5–2 hours/table**, no code | No (data only) |
| **Select AI native (Pattern A)** | Add table to `object_list` + ensure `COMMENTS`/`ANNOTATIONS` exist | **~minutes–1 hour/table** | No |
| **Long-tail auto-catalog** | Nightly job harvests `ALL_*_COMMENTS` → embeds → catalog | **~0 marginal/table** (bulk) | No |

At thousands of tables, the hardcoded model is a non-starter (person-years); the metadata-driven model turns table onboarding into a **data-entry + comment-writing task** that business analysts can do, and the long tail is **free** via a bulk harvest job. This is the core justification for the rewrite. The one-time investment is: build the router + registry + safety gate + catalog job (a few weeks), then scale is linear-cheap.

**Critical dependency:** accuracy is bounded by **comment/annotation quality**. Reallocate the effort saved on coding into **writing good VI/EN table & column comments** on the core tables — the highest-ROI activity (semantic layer = +17–27 pts accuracy). _Source: [Semantic Layers benchmark](https://arxiv.org/pdf/2604.25149), [Best practices NL2SQL accuracy](https://blogs.oracle.com/machinelearning/best-practices-to-improve-nl2sql-accuracy-with-oracle-select-ai)._

### Phased migration path from `crm_nl2sql_pkg`

- **Phase 0 — Verify (days).** On the live 26ai: confirm Select AI on-prem + Ollama/OpenAI-compat provider; measure Select AI call count & latency vs the current 1-call uc_ai. Decide Pattern A vs B as the primary backend. (Verification checklist at end.)
- **Phase 1 — Registry + generalise CRM_LEADS (1–2 wk).** Build `nl2sql_table/column/join/synonym`. **Migrate CRM_LEADS from hardcoded whitelists into registry rows** — no behaviour change, proves the registry reproduces current 12/12 accuracy & 1.8–2.4s latency. Router = single-table FAST path only.
- **Phase 2 — Safety gate + read-only user (days).** Extract the validation/bind/row-cap into a reusable safety gate; run under a dedicated read-only DB user; add RLS predicate support. Re-run the 4/4 adversarial suite.
- **Phase 3 — Catalog + SLOW path (1–2 wk).** Nightly harvest of `ALL_*_COMMENTS` → bge-m3 catalog + HNSW; add vector-retrieval SLOW path + cross-table joins from `nl2sql_join`. Now the whole schema is *answerable* (long tail) with the core still fast.
- **Phase 4 — Onboard the next N core tables (ongoing).** Pure data entry + comment writing; add `nl2sql_feedback` loop; optionally flip specific cases to Select AI if Phase 0 favoured it. No package rewrites.

Each phase is independently shippable and keeps the current behaviour working; CRM_LEADS never regresses.

## Research Synthesis & Final Verdict

### Executive Summary

The current `crm_nl2sql_pkg` is fast and safe but hardcodes whitelists and SQL skeletons **per table** — a dead end at thousands of tables. The research finds a clear path out that **keeps the 1-call CPU latency profile and the safety guarantees while eliminating per-table code**: make NL→SQL **metadata-driven**, where the "whitelist" becomes *data* (a registry + the database's own comments/annotations) rather than PL/SQL.

The decisive external facts:
1. **Oracle 26ai already ships the hard part** — Select AI (`DBMS_CLOUD_AI`) **auto-detects relevant tables and sends only their metadata** to the LLM, with `object_list` as a native table allowlist. It runs on-prem, but its **Ollama provider path needs live verification** (likely via the OpenAI-compatible endpoint).
2. **Accuracy at scale is driven by metadata quality, not model size** (+17–27 pts from a semantic layer; 92.5% vs 20% bare schema) — favourable for the CPU-only 3B model.
3. **Retrieval, not a bigger prompt** — RAG schema-linking (RASL/SchemaRAG) bounds prompt tokens regardless of schema size, and **adds DB time, not a second LLM call** — so it survives the CPU prefill limit.

### FINAL VERDICT

> **ADOPT a tiered, engine-pluggable, metadata-driven NL→SQL architecture — with the metadata (registry + DB comments/annotations) as the single scaling asset.** Keep exactly **one LLM call** on both the fast (single governed table) and slow (retrieval over the auto-catalog) paths. Default the generation backend to the **proven in-stack uc_ai 1-call structured-output (Pattern B/i)**, and **adopt Oracle Select AI (Pattern A) as the primary backend only after Phase-0 verification** confirms it runs on this on-prem 26ai with the local Ollama model at competitive call-count/latency. Migrate `crm_nl2sql_pkg` in 5 shippable phases, starting by moving CRM_LEADS from hardcoded whitelists into the registry with zero behaviour change.

**Why this is the recommended default (not full Select AI, not status-quo):**
- **De-risks the one unknown** (on-prem Select AI + Ollama) by not depending on it to ship value — Pattern B works today with parts already in the repo.
- **Eliminates per-table code** immediately via the registry (0.5–2 days/table → 0.5–2 hours/table; long tail ~free).
- **Preserves the CPU latency win** — 1 call, byte-stable prefix on the fast path, retrieval-not-second-call on the slow path.
- **Same-or-better safety** — allowlist-as-data + DB-enforced read-only user + bound literals + RLS.
- **Converges with Oracle's own direction** (Semantic Views + Select AI), so adopting Pattern A later is additive, not a rewrite.

**When to prefer full Select AI (Pattern A) as primary:** if Phase-0 shows it runs on-prem with Ollama at ≤1 effective LLM call and ≤ our latency budget, prefer it for the long-tail (less code than the DIY catalog) while keeping the JSON-intermediate fast path for the governed core.

**When to stay closer to status-quo:** only for the ~handful of ultra-hot questions where a fully hardcoded skeleton is measurably faster than the registry-driven one — keep those as an optional pinned fast-path, not the general model.

### ✅ Phase-0 RESULT (verified 2026-07-07)

Ran `sql/crm_selectai_phase0_verify.sql` on the live on-prem 26ai: **`DBMS_CLOUD_AI` is NOT installed** (STEP 1 → "KHONG thay DBMS_CLOUD_AI"). **Select AI / Option A is therefore unavailable** on this instance (enabling it would require Oracle's manual on-prem `DBMS_CLOUD` install — out of scope). **Decision locked: Option B** — metadata-driven registry + bge-m3 RAG catalog + uc_ai 1-call structured-output. (Network ACL for DB→Ollama was granted successfully during the run.) The remaining checklist items below are moot for Select AI and superseded by the Option-B build (Phase 1 onward).

### ⚠️ Live-DB Verification Checklist (Phase 0 — do before building) — *superseded by the result above*

Run on the real 26ai / APEX 26.1 to resolve every `[unverified]`:
1. `SELECT * FROM DBA_REGISTRY` / `DESC DBMS_CLOUD_AI` — is `DBMS_CLOUD_AI` installed & usable on this **non-Autonomous on-prem 26ai**?
2. `DBMS_CLOUD_AI.CREATE_PROFILE` — does it accept `provider => 'ollama'`, or must we use `provider => 'openai'` with `host/base_url => 'http://172.25.10.38:11434/v1'` (Ollama OpenAI-compat)? Confirm a Web Credential is accepted.
3. Run a `SELECT AI showsql "..."` and **tcpdump/journalctl** the Ollama side: **how many LLM calls** does one question make (does auto table-detection add an internal call)? Measure end-to-end latency vs current uc_ai 1-call.
4. With a large `object_list` (e.g. 200+ tables), does auto table-detection stay accurate and bounded, and does it require/benefit from a vector index on the metadata?
5. Confirm `"comments": true`, `"constraints": true`, `"annotations": true` behaviour and that **no row data** is sent (packet-inspect).
6. APEX 26.1: confirm `APEX_AI.generate` with `p_agent_static_id` and whether an AI-Agent tool wrapping Select AI still incurs the `UNTRUSTED-DATA` 2nd-call penalty (prefer direct PL/SQL for the hot path).
7. Confirm a **read-only DB user** with SELECT-only grants can execute the generated SQL (defense-in-depth).
8. Validate `bodau()` FBIs exist on the routing/synonym columns before enabling the fast-path matcher at scale.

### Bản tóm tắt tiếng Việt (Vietnamese summary)

**Vấn đề:** `crm_nl2sql_pkg` nhanh và an toàn nhưng **hardcode whitelist + skeleton cho từng bảng** → không thể mở rộng tới hàng ngàn bảng.

**Kết luận (VERDICT):** Chuyển sang **kiến trúc NL→SQL metadata-driven, phân tầng, backend cắm-được**, với **metadata (registry + comment/annotation trong DB) là tài sản mở rộng duy nhất**. Giữ **đúng 1 lần gọi LLM** trên cả fast path (1 bảng governed) và slow path (retrieval trên catalog tự sinh). Mặc định backend = **uc_ai 1-call structured-output (đã chạy tốt trong repo)**; **chỉ dùng Oracle Select AI làm backend chính sau khi Phase-0 verify** rằng nó chạy trên 26ai on-prem + Ollama với số call/latency chấp nhận được.

**Vì sao mở rộng được:** onboard bảng mới = **INSERT vài dòng registry + viết comment VI/EN tốt** (0.5–2 giờ, không deploy code), long-tail thì **gần như miễn phí** qua job harvest `ALL_*_COMMENTS` hằng đêm. Ở ngàn bảng, cách hardcode = person-years (bất khả thi).

**An toàn:** bằng hoặc hơn hiện tại — allowlist thành *data* + **user DB read-only** (DB tự chối DML ảo) + bind mọi literal + RLS. Độ chính xác ở quy mô lớn phụ thuộc **chất lượng comment/annotation**, KHÔNG phải model to hơn → rất hợp với 3B CPU-only.

**Bước tiếp theo:** chạy **Checklist Phase-0** trên DB thật (đặc biệt: Select AI có chạy on-prem + Ollama không, và mất mấy lần gọi LLM), rồi chuyển CRM_LEADS sang registry trước (không đổi hành vi).

### Sources

- Oracle Select AI User's Guide 26ai — https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/select-ai.html
- Select AI Concepts (26ai) — https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/select-ai-concepts.html
- Select AI by Release (26ai & 19c) — https://blogs.oracle.com/machinelearning/select-ai-by-release-a-quick-guide-to-26ai-and-19c-capabilities
- DBMS_CLOUD_AI Package — https://docs.oracle.com/en/database/oracle/oracle-database/26/arpls/dbms_cloud_ai1.html
- Manage AI Profiles — https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/manage-ai-profiles.html
- Best practices to improve NL2SQL accuracy with Select AI — https://blogs.oracle.com/machinelearning/best-practices-to-improve-nl2sql-accuracy-with-oracle-select-ai
- Making Select AI smarter with database annotations — https://blogs.oracle.com/coretec/making-select-ai-smarter-with-database-annotations
- Using local LLMs with Oracle Database (on-prem + Ollama) — https://blogs.oracle.com/coretec/using-local-llms-with-oracle-database
- Running Oracle's Private AI Stack On-Premises — https://sillidata.com/2026/04/13/running-oracles-private-ai-stack-on-premises/
- Oracle 26ai Select AI: SQL Accuracy & Latency Study — https://dzone.com/articles/select-ai-oracle-26ai-openai
- NL2SQL at Scale via Select AI (TechRxiv) — https://www.techrxiv.org/doi/full/10.36227/techrxiv.177281023.37874227/v1
- RASL: Retrieval Augmented Schema Linking — https://www.amazon.science/publications/rasl-retrieval-augmented-schema-linking-for-massive-database-text-to-sql
- SchemaRAG (ACM SIGMOD) — https://dl.acm.org/doi/10.1145/3786696
- CSR-RAG (enterprise-scale retrieval) — https://arxiv.org/pdf/2601.06564
- SchemaGraphSQL (graph join-path linking) — https://arxiv.org/pdf/2505.18363
- Semantic Layers for Reliable LLM Analytics (benchmark) — https://arxiv.org/pdf/2604.25149
- Semantic Layer as the Data Interface for LLMs (dbt) — https://www.getdbt.com/blog/semantic-layer-as-the-data-interface-for-llms
- Semantic Layer vs Text-to-SQL 2026 benchmark (dbt) — https://docs.getdbt.com/blog/semantic-layer-vs-text-to-sql-2026
- Why Semantic Layers Make Enterprise Text-to-SQL Safer — https://datalakehousehub.com/blog/2026-05-semantic-layers-text-to-sql/
- APEX 26.1 New Features — https://docs.oracle.com/en/database/oracle/apex/26.1/htmrn/new-features.html
- AI Agents in Oracle APEX — https://blogs.oracle.com/apex/ai-agents-in-oracle-apex
- Building RAG in APEX with AI Configurations and RAG Sources — https://blogs.oracle.com/apex/blog-ai-config-and-rag-sources
- Prompt injection is the new SQL injection (Cisco) — https://blogs.cisco.com/ai/prompt-injection-is-the-new-sql-injection-and-guardrails-arent-enough
- Self-healing NL→SQL pipeline (arXiv) — https://arxiv.org/pdf/2604.16511

---

## Table of Contents

1. Research Overview
2. Technical Research Scope Confirmation
3. Technology Stack Analysis — three families of large-schema NL→SQL
4. Integration Patterns — Select AI control plane, DIY RAG catalog, APEX front-door
5. Architectural Patterns — tiered hybrid target, fast/slow paths, semantic-layer schema
6. Implementation Research — safe SQL generation, defense-in-depth, economics, migration
7. Research Synthesis & Final Verdict — executive summary, verdict, verification checklist

*End of report.*
