---
title: 'Select AI / Ollama Phase-0 verification script'
type: 'chore'
created: '2026-07-07'
status: 'done'
route: 'one-shot'
context: ['{project-root}/_bmad-output/planning-artifacts/research/technical-metadata-driven-nl2sql-architecture-research-2026-07-07.md']
---

# Select AI / Ollama Phase-0 verification script

## Intent

**Problem:** The metadata-driven NL→SQL research (report 2026-07-07) recommends adopting Oracle Select AI (`DBMS_CLOUD_AI`) as the primary backend *only after* verifying it runs on this on-prem, non-Autonomous 26ai with the local Ollama model — the single unresolved risk (Option A vs Option B).

**Approach:** A hand-run, DB-server-side SQL/PLSQL script `sql/crm_selectai_phase0_verify.sql` that walks the report's Phase-0 checklist as 6 independent, EXCEPTION-wrapped steps with `DBMS_OUTPUT` diagnostics: (1) is `DBMS_CLOUD_AI` present + granted; (2) network ACL + credential prereqs; (3) `CREATE_PROFILE` trying both `provider=>'ollama'` and an `openai`/`.../v1` fallback against localhost:11434; (4) `showsql`+`narrate` NL test with wall-clock latency; (5) server-side guidance to count LLM calls; (6) read-only note + cleanup. Every uncertain 26.1/26ai API is tagged `[XÁC NHẬN API]`; no secrets, nothing destructive by default.

## Suggested Review Order

1. [Header + conventions](../../sql/crm_selectai_phase0_verify.sql) — what it does, where it runs (DB side, not the PC), literal-vs-`/* */` convention, `[XÁC NHẬN API]` meaning.
2. [STEP 1](../../sql/crm_selectai_phase0_verify.sql) — availability/privs probe + early-exit-to-Option-B logic.
3. [STEP 2](../../sql/crm_selectai_phase0_verify.sql) — ACL (`APPEND_HOST_ACE`) for localhost/127.0.0.1/172.25.10.38 + credential template (placeholders only).
4. [STEP 3](../../sql/crm_selectai_phase0_verify.sql) — the risk point: two provider attempts, each isolated so one failing doesn't abort the other.
5. [STEP 4](../../sql/crm_selectai_phase0_verify.sql) — `GENERATE(showsql/narrate)` + latency; compare vs `crm_nl2sql_pkg.ask` ~1.8–2.4s.
6. [STEP 5–6](../../sql/crm_selectai_phase0_verify.sql) — LLM-call counting on the server + cleanup.

## Notes

- Runs on the DB server (172.25.10.38) where Ollama binds localhost — NOT from the Windows client (that is the separate PL/SQL Developer AI Assistant path, blocked by network).
- No repo build/test pipeline; validation = the DBA running the script on the live 26ai and reading each STEP's KET LUAN line.
- Decision gate it feeds: 1 LLM call + acceptable latency + a working provider ⇒ Option A (Select AI); else keep Option B (uc_ai metadata-RAG).
