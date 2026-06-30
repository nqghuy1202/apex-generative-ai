# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

This is **not an application codebase** — it is a **BMad Method v6 workspace** for a project named `apex-ai`. There is no build/test/lint pipeline yet; work here is currently planning, research, and design driven through BMad skills. Application code, planning artifacts, and design artifacts are produced into the output folders below as the project progresses.

## Active work

Building an **Oracle AI Vector Search / RAG pipeline on APEX 26.1 + DB 26ai**, embedding via Ollama `bge-m3:latest` (dimension 1024, COSINE) through a native Generative AI Service (static id `apex-embed`).

**Milestone — end-to-end RAG demo working (2026-06-27):** `sql/apex_vector_rag_demo.sql` runs successfully: two-table schema `documents` ↔ `doc_chunks`, chunk via `DBMS_VECTOR_CHAIN.UTL_TO_CHUNKS`, embed via `apex_ai.get_vector_embeddings(p_value, p_service_static_id => 'apex-embed')`, `VECTOR(1024, FLOAT32)` column, HNSW index, `FETCH APPROX FIRST n ROWS ONLY` search. Verified: semantic query ranks the relevant doc (dist 0.42) above an unrelated one (0.73).

**Milestone — APEX AI Assistant + CPU speed work (2026-06-29):** wired a `customers` table (`sql/customers_sample.sql`, `sql/customers_vector_rag.sql`) into an APEX AI Assistant with two tools — `search_customers_semantic` (vector_distance RAG) and `query_customer_metrics` (GROUP BY aggregate). The generation model runs **CPU-only on a separate Linux server (server B) via Ollama**; the APEX/DB host (server A, IP `172.25.10.38` in logs) calls it. Baseline `qwen3.5:latest` (5.8 GiB) was painfully slow (80–153 s/request).

**VERIFIED FIX (2026-06-29):** the real root cause was **thinking-mode that cannot be turned off on Qwen3**. Both `/no_think` (deprecated token) and Ollama's `"think": false` failed to stop `qwen3:4b` — it still dumped reasoning into `content`, hit the `num_predict` cap (256–512 tokens), `done_reason: "length"`, 27–73 s/request. **Solution that works = swap to a pure-instruct model `qwen2.5:3b-instruct`** (no thinking). Verified tool-call test: `content=""`, correct `tool_calls` (`search_customers_semantic` + `search_text`), `done_reason: "stop"`, `eval_count=30`, eval ~2 s. Keep the custom model **named `qwen3-erp`** (so APEX config is untouched) but built `FROM qwen2.5:3b-instruct`, temp 0.1, num_ctx 2048, num_predict 256, **Vietnamese system prompt WITH diacritics** (no-diacritics text confuses the model). Use `keep_alive 24h` / `OLLAMA_KEEP_ALIVE=24h` to avoid ~4 s reloads. Note: `sql/README_llm_speed_round1.md` + the research report still describe the OLD (qwen3:4b + `/no_think`) approach and are now superseded — update them if used.

**Milestone — CRM_LEADS agent design + implementation (2026-06-30):** ran `bmad-technical-research` to design an AI Agent over the `CRM_LEADS` table (CRM leads, **>500k rows**, 40+ cols), serving both sales and managers. Report: `_bmad-output/planning-artifacts/research/technical-crm-leads-ai-agent-setup-research-2026-06-30.md`. Core design: (1) split columns into **Semantic** (embed into a VI-with-diacritics sentence), **Structured** (filter/aggregate), **Identity** (b-tree lookup); (2) **4 job-specific tools** `lookup_lead_exact` / `search_leads_semantic` (pre-filter) / `query_lead_metrics` / `suggest_lead_actions`; (3) at >500k, **pre-filter before RAG** (Oracle 26ai `PRE_W` on Local Partitioned HNSW) is the decisive lever. Authored `sql/crm_leads_vector_rag.sql`, `sql/crm_leads_agent_tools.sql`, `sql/crm_leads_agent_prompts.md`. The embeddings table carries denormalized filter cols (status/temperature/emp_id/co_id) so vector search + WHERE run on one table (enables pre-filter). Memory: `crm-leads-agent-research`.

**Key project conventions (see memory):**
- PK columns use explicit **SEQUENCE + `.NEXTVAL`**, never `GENERATED AS IDENTITY` (system rule — `use-sequences-not-identity`).
- **MLE normalization at scale:** `mle_norm` (MLE/JS in `sql/mle_text_normalize.sql`) is more accurate than `NLSSORT`/`CONVERT` for Vietnamese (`đ→d` + diacritics), but is per-value. On large tables (CRM_LEADS >500k) do NOT wrap `mle_norm()` around a column in `WHERE`/`GROUP BY` — it forces a per-row JS call + disables the index (full scan). Normalize once at write-time into indexed `*_norm` columns, then query plain SQL on them and call `mle_norm()` only on the input param. The small `customers`-pattern files use per-row `mle_norm(col)`, acceptable only at small scale (memory `mle-normalize-at-write-not-query`).
- The earlier `HTTP 400 invalid input` was only the **Test Connection** chat probe failing against embedding-only bge-m3 — it does NOT block real embedding use. Provider = Ollama, Base URL = host:port only (no `/v1/embeddings`).
- Operational gotcha: run steps in order (seq → insert documents → chunk → UPDATE embedding + COMMIT) before querying; a NULL `embedding` makes `VECTOR_DISTANCE` return NULL.
- **CPU LLM speed:** the dominant cost was **thinking-mode** generating runaway output. On Qwen3 you CANNOT disable it (`/no_think` and `"think": false` both ignored) — for ERP tool-calling use a **pure-instruct model: `qwen2.5:3b-instruct`** (escalate to `qwen2.5:7b-instruct` if 3b picks the wrong tool). Always write the system prompt in **Vietnamese with diacritics**. `ORA-20960` from the AI Assistant means the model emitted an invalid tool-call (weak/embedding-only models trigger this) — debug by tailing `journalctl -u ollama -f` while reproducing. The model lives on **server B (Linux/bash)**, not this Windows box — don't paste PowerShell into its bash shell.

Full reports in `_bmad-output/planning-artifacts/research/`. Persistent memory: `apex-ollama-bge-m3-embedding`, `apex-vector-rag-table-design`, `use-sequences-not-identity`, `erp-local-llm-model-choice`, `llm-cpu-speed-optimization`.

## Layout

- `_bmad/` — installed BMad Method v6 framework. **Installer-managed, treat as read-only.** Modules: `bmm` (software dev lifecycle), `gds` (game dev), `wds` (web design system), `cis` (creative/innovation), `tea` (test architecture), `bmb` (builder), `automator`, `core`.
- `.claude/skills/` — the BMad skills surfaced to Claude Code (agents like Mary/Winston/Amelia, and workflows like `bmad-technical-research`, `bmad-prd`, `bmad-architecture`). Also contains the `prompt-master` skill.
- `_bmad-output/` — all generated artifacts land here: `planning-artifacts/` (research reports live under `planning-artifacts/research/`), `implementation-artifacts/`, `test-artifacts/`.
- `sql/` — hand-written SQL/PLSQL for the APEX work: `apex_vector_rag_demo.sql` (end-to-end vector RAG demo); `customers_sample.sql` + `customers_vector_rag.sql` + `customer_agent_tools.sql` (the `customers` AI-Assistant dataset — the template pattern); `crm_leads_vector_rag.sql` + `crm_leads_agent_tools.sql` + `crm_leads_agent_prompts.md` (the CRM_LEADS agent, scaled for >500k); `mle_text_normalize.sql` (shared `mle_norm` accent-stripper); `optimize_llm_speed_round1.sql` + `README_llm_speed_round1.md` (CPU speed tuning playbook). **SQL file convention:** blocks inside `/* ... */` are the query to paste into an APEX AI Assistant Tool (APEX binds `:p_*` from the model); the un-commented `SELECT`s use literal values for local testing (SQL Workshop chokes on bind/`VARIABLE` → ORA-06502). Ollama runs on a **remote Linux server**, not this Windows dev box — Modelfile/`ollama` commands run there over SSH.
- `docs/` — project knowledge base (`project_knowledge`). Currently empty.
- `design-artifacts/` — WDS design output. Currently empty.

## Config (read-only — do not hand-edit)

`_bmad/config.toml` and `_bmad/config.user.toml` are regenerated by the installer on every run. To change values durably, re-run the installer or use `_bmad/custom/config.toml` (team) / `_bmad/custom/config.user.toml` (personal) — those are never overwritten.

Key settings already in effect:
- `output_folder` = `_bmad-output`
- `document_output_language` = **English and Vietnamese**, `communication_language` = **English and Vietnamese** — user (Gia Huy) expects bilingual responses.
- `user_skill_level` = intermediate.

## Working conventions

- Drive work through BMad skills rather than ad-hoc scripting. Match the skill to the phase: research → `bmad-technical-research`/`bmad-domain-research`; requirements → `bmad-prd`; architecture → `bmad-architecture`; implementation → `bmad-dev-story`/`bmad-quick-dev`. `bmad-help` recommends the next skill when unsure.
- Write generated documents into the configured output folders above, not the repo root.
- This **is** a git repository (default branch `main`), but commits have not been part of the workflow so far — commit/push only when the user explicitly asks.
- The user runs the Oracle DB / APEX / Ollama stack themselves on a separate Linux host; this dev box (Windows) only authors SQL and docs. When something needs running, hand the user the exact command rather than expecting to execute it here.
