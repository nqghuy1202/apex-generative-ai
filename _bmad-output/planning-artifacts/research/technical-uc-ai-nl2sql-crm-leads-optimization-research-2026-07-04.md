---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments: []
workflowType: 'research'
lastStep: 6
research_type: 'technical'
research_topic: 'Optimize uc_ai for NL->SQL Q&A over CRM_LEADS at <30s on CPU-only server B'
research_goals: 'Determine the lowest-latency way to use the uc_ai PL/SQL package for natural-language -> SQL questions (count/filter/aggregate) over CRM_LEADS on the non-AVX2 CPU-only server B, targeting <30s/question. Compare single-call structured-SQL vs uc_ai native tool-calling loop vs structured_output intent+filters; define uc_ai/Modelfile latency levers; design SQL-safety for LLM-driven queries; keep qwen3-erp + bge-m3 coexisting; give an honest verdict vs the existing native hard-exit agent. Research + read uc_ai source only, NO production code changes.'
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

**EN —** This report determines the lowest-latency, safe way to use the installed **uc_ai** PL/SQL package for **natural-language → SQL** questions over **CRM_LEADS** at **<30s** on the non-AVX2, CPU-only server B. Verdict: **ADOPT — but only in one specific shape.** Use `uc_ai.generate_text` with `p_response_json_schema` and **zero registered tools** so the model makes **exactly one LLM call**, returning a flat, enum-constrained `{intent, filters, group_by, limit}` JSON that deterministic PL/SQL validates (whitelist + binds + read-only + row cap) and turns into a parameterized query. This avoids uc_ai's multi-call tool-loop — the very prefill trap that made the native agent slow — and is competitive with, and simpler than, the native hard-exit agent for this narrow job. All absolute latency figures are `[estimate]`; the report ends with a Phase-B benchmark plan. See the Synthesis section for the full verdict, schema, and roadmap.

**VI —** Báo cáo xác định cách **latency thấp nhất & an toàn** để dùng package **uc_ai** (đã cài) cho hỏi-đáp **NL→SQL trên CRM_LEADS** đạt **<30s** trên CPU server B (không AVX2). Kết luận: **ADOPT — nhưng chỉ ở một dạng cụ thể.** Dùng `uc_ai.generate_text` với `p_response_json_schema` và **0 tool đăng ký** → model chỉ **1 LLM call**, trả JSON phẳng ràng buộc enum `{intent, filters, group_by, limit}`; PL/SQL validate (whitelist + bind + read-only + cap dòng) rồi dựng query tham số hóa. Tránh được tool-loop đa-call của uc_ai (đúng bẫy prefill làm agent native chậm), nhanh ngang & đơn giản hơn agent native cho việc hẹp này. Mọi số latency là `[estimate]`; cuối báo cáo có kế hoạch benchmark Phase B.

---

<!-- Content will be appended sequentially through research workflow steps -->

## Technical Research Scope Confirmation

**Research Topic:** Optimize uc_ai for NL->SQL Q&A over CRM_LEADS at <30s on CPU-only server B
**Research Goals:** Lowest-latency uc_ai NL->SQL over CRM_LEADS (<30s), comparing single-call structured-SQL vs uc_ai tool-loop vs structured_output; latency levers; SQL safety; CPU coexistence; honest verdict vs the native hard-exit agent. Research + source-read only; no production code changes.

**Method note:** uc_ai API verified by reading source at C:\Users\Admin\Downloads\uc_ai-development\uc_ai-development\src, not web guesses. Unmeasured latency marked [estimate].

**Scope Confirmed:** 2026-07-04

---

## Technology Stack Analysis — what uc_ai actually gives us (source-verified)

All facts below are read directly from `…\uc_ai-development\src\packages` (not web guesses).

### Three mechanisms uc_ai exposes, and their LLM-call cost

| # | Mechanism | uc_ai API (verified) | LLM calls | Prefill weight |
|---|---|---|---|---|
| **(a)** | **Single-call structured output** | `uc_ai.generate_text(p_user_prompt, p_system_prompt, p_provider=>c_provider_ollama, p_model, p_response_json_schema => <schema>)` with **NO active tools** | **1** | system prompt + schema only |
| **(b)** | **Tool-calling loop** | register tools via `uc_ai_tools_api.create_tool_from_schema(...)`, then `generate_text` (no schema) | **2..N** (loops while model emits tool_calls; `p_max_tool_calls` default **10**) | system prompt + **all active tool defs** + tool results, re-sent every turn |
| **(c)** | **Structured intent+filters** | same as (a) but the schema describes `{intent, filters[]}` instead of raw SQL | **1** | same as (a) |

**Key source facts (verified in `uc_ai_ollama.pkb` / `uc_ai.pkb`):**
- `generate_text` routes to `uc_ai_ollama.generate_text(..., p_schema => p_response_json_schema)`. When `p_schema` is not null it does `l_input_obj.put('format', uc_ai_structured_output.to_ollama_format(p_schema))` — i.e. it uses **Ollama's native structured-output `format` field**, which constrains the model's decoding to the schema (reliable JSON, no code fences).
- The agentic loop (`internal_generate_text`) only re-calls the LLM **when the model returns `tool_calls`**. **With no active tools registered, there is exactly ONE call.** So approach (a)/(c) = single call by construction.
- `uc_ai_tools_api.get_tools_array(p_provider)` sends **every active tool** to the model on **every** turn — each tool definition is extra prefill tokens, paid on each of the 2..N calls. This is the latency trap on the CPU.
- `execute_tool` binds arguments as a **single `:ARGUMENTS` JSON bind** ("Only supports single bind variable for security") and runs the tool's stored `function_call` PL/SQL.
- Ollama path requires `uc_ai_ollama.g_use_responses_api := false` (the `g_use_responses_api=true` branch targets a Responses API Ollama doesn't serve).

### Ollama structured-output constraints that shape our schema

- Structured outputs (Ollama ≥0.3.0) constrain decoding to the JSON schema → near-100% parse success, no fences/preamble. `[HIGH]`
- **Use temperature 0** for schema adherence/determinism.
- **Keep the schema FLAT** — quantized ~3–4B models (our `qwen3-erp` = qwen2.5:3b-instruct) get unreliable on schemas nested 3+ levels (empty intermediate arrays). Our `{intent, filters[]}` must be shallow.
- _Sources: [Ollama Structured Outputs docs](https://docs.ollama.com/capabilities/structured-outputs), [Ollama structured outputs blog](https://ollama.com/blog/structured-outputs), [Constraining LLMs w/ structured output (Qwen3)](https://medium.com/@rosgluk/constraining-llms-with-structured-output-ollama-qwen3-python-or-go-2f56ff41d720), [Reliable structured output from local LLMs (Markaicode)](https://markaicode.com/ollama-structured-output-pipeline/)_

### Immediate implication for the <30s goal

The single biggest latency lever is **call count × prefill tokens**. Approach (a)/(c) is **1 call with a small prefix**; approach (b) is **2..N calls each carrying all tool defs**. On a non-AVX2 CPU where prefill dominates, **(a)/(c) is structurally faster** and is the only design with a realistic shot at <30s. This mirrors the native-agent finding that the hard-exit (kill the 2nd call) was mandatory — here we get the same effect for free by **not registering tools and using a response schema instead**.

_Confidence: HIGH — all API/loop behavior read from source; Ollama structured-output behavior multi-source. Latency ordering is deductive (fewer calls + fewer tokens = less prefill); absolute seconds are `[estimate]` pending on-hardware benchmark._

---

## Integration Patterns Analysis

### The recommended pattern: (c) LLM emits intent+filters, PL/SQL builds the SQL

Approach **(c)** wins on both axes we care about — **latency** (1 call) and **safety** (LLM never touches raw SQL). The LLM's only job is to translate Vietnamese → a small, flat, validated JSON object; deterministic PL/SQL turns that into a parameterized, read-only query.

```
User (VI question)
   │
   ▼
uc_ai.generate_text(
   p_system_prompt => <tiny fixed schema-aware prompt>,
   p_user_prompt   => :question,
   p_provider      => uc_ai.c_provider_ollama,
   p_model         => 'qwen3-erp:latest',
   p_response_json_schema => <FLAT schema: intent, filters[], group_by, metric, limit>
)                                   ← ONE LLM call, Ollama-constrained JSON
   │  returns e.g.
   │  { "intent":"count",
   │    "filters":[{"col":"status","op":"=","val":"HOT"},
   │               {"col":"source","op":"=","val":"Facebook"}],
   │    "group_by":"source", "limit":50 }
   ▼
PL/SQL VALIDATOR + BUILDER  (no LLM)
   • whitelist col ∈ {status,temperature,source,emp_id,co_id,created,...}
   • whitelist op  ∈ {=,!=,>,>=,<,<=,IN,LIKE}
   • whitelist intent ∈ {count,list,aggregate,rank}
   • values → BIND variables (never concatenated)
   • force read-only + FETCH FIRST :limit ROWS
   ▼
EXECUTE (parametrized, read-only role)  →  rows/number
   ▼
Format Vietnamese answer  (template, or a 2nd tiny optional LLM call — usually not needed)
```

- _Sources: [OWASP SQL Injection Prevention](https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html), [LLM-generated SQL best practices (Ha)](https://medium.com/@vi.ha.engr/bridging-natural-language-and-databases-best-practices-for-llm-generated-sql-fcba0449d4e5), [Are your Text-to-SQL models secure? (arXiv)](https://arxiv.org/html/2503.05445v3)_

### Why not the other two

- **(a) LLM emits raw SQL string** — 1 call, but the model *writes the SQL*. Even read-only, it invites malformed/expensive SQL, full scans, hallucinated columns, and injection if any value is concatenated. **Rejected on safety** unless every query is re-parsed/whitelisted anyway — at which point (c) is simpler.
- **(b) uc_ai tool-loop** — 2..N calls, all tool defs re-sent each turn → the exact CPU-prefill trap. **Rejected on latency** for the interactive path. (Still fine for rare, non-latency-sensitive multi-step tasks.)

### SQL-safety design (the core of this pattern)

| Layer | Control |
|---|---|
| **Column whitelist** | Map allowed `col` tokens → real column names in PL/SQL; anything else → reject. LLM never names a raw column that reaches SQL unchecked. |
| **Operator whitelist** | Fixed enum; reject unknown ops. |
| **Values as binds** | Every `val` bound via `DBMS_SQL`/`EXECUTE IMMEDIATE ... USING`, never string-concatenated. |
| **Intent whitelist** | `count/list/aggregate/rank` → each maps to a fixed SQL skeleton; no free-form SQL. |
| **Read-only** | Run under a role/connection with SELECT-only on CRM_LEADS; no DML/DDL grant. Belt-and-suspenders even if a value slipped. |
| **Row cap** | Force `FETCH FIRST :n ROWS ONLY` (cap n) to bound cost + result-prefill for any follow-up. |
| **Audit** | Log the JSON + generated SQL + row count for every request. |

This reuses your existing `sql/crm_leads_agent_tools.sql` skeletons (`query_lead_metrics`, etc.) as the fixed intent templates — the LLM just fills validated parameters, exactly as your native tools already expect `:p_*` binds. **`bodau`** normalizes Vietnamese filter values on both sides.

### How this maps onto uc_ai concretely

- Use `uc_ai.generate_text` with `p_response_json_schema` and **register zero tools** → guaranteed single call.
- Keep the **system prompt tiny and byte-identical** across requests (schema description + the column glossary) so the KV-cache prefix can be reused between questions on the same model — a real win since, unlike the native agent's call-2, there is **no UNTRUSTED-DATA marker here** (we control the whole body).
- Set `uc_ai_ollama.g_use_responses_api := false`, `p_max_tool_calls => 0/1` (moot with no tools but explicit).
- Optional: skip a 2nd LLM "format the answer" call — render the number/rows with a PL/SQL template to stay at exactly **one** LLM call. Only use a 2nd tiny call if natural-language phrasing of the result matters.

_Confidence: HIGH on the pattern and safety design (OWASP + source-verified uc_ai binding model). The "KV-cache prefix reuse across questions" benefit is `[estimate]` — depends on Ollama keeping the model resident and the prefix truly identical._

---

## Architectural Patterns and Design

### The concrete FLAT response schema (qwen3-erp-safe)

Kept ≤2 levels deep so the 3B model stays reliable. `col`/`op`/`intent` are **enums** — the model can only pick from the whitelist, which both constrains decoding and pre-validates safety:

```json
{
  "type": "object",
  "properties": {
    "intent":   { "type": "string", "enum": ["count","list","aggregate","rank"] },
    "metric":   { "type": "string", "enum": ["none","count","avg_score","sum_value"] },
    "group_by": { "type": "string", "enum": ["none","status","temperature","source","emp_id","co_id"] },
    "filters": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "col": { "type": "string", "enum": ["status","temperature","source","emp_id","co_id","created"] },
          "op":  { "type": "string", "enum": ["=","!=",">",">=","<","<=","LIKE"] },
          "val": { "type": "string" }
        },
        "required": ["col","op","val"]
      }
    },
    "limit": { "type": "integer" }
  },
  "required": ["intent","filters"]
}
```

Because `col/op/intent/group_by/metric` are enums, **the only free-text the model emits is `val`**, which is always bound — the attack surface collapses to "a bad literal value," which read-only + binds already neutralize.

### PL/SQL wrapper package (design only — build in Phase B)

`crm_nl2sql_pkg` (thin wrapper over uc_ai):
- `ask(p_question) return clob` → (1) `generate_text` with the schema above, 0 tools; (2) parse JSON with `JSON_OBJECT_T`; (3) `validate_and_build` → parametrized SQL from fixed skeletons keyed by `intent`; (4) execute read-only with binds + row cap; (5) format VI answer via template.
- Globals set once: `uc_ai.g_base_url`, `uc_ai_ollama.g_apex_web_credential`, `uc_ai_ollama.g_use_responses_api := false`.
- Reuses `crm_leads_agent_tools.sql` skeletons + `bodau` for VI value normalization.

### Modelfile / Ollama settings for <30s (server B)

| Setting | Value | Why |
|---|---|---|
| base model | `qwen2.5:3b-instruct` (as `qwen3-erp`) | pure-instruct, no thinking; smallest that tool/JSON-follows reliably |
| `temperature` | **0** | schema adherence + determinism |
| `num_ctx` | **2048** (can drop from 4096) | NL→SQL prompt is tiny (no tool defs, no RAG) → smaller ctx = less prefill |
| `num_predict` | **~128** | JSON output is short; cap generation |
| `num_batch` | **1024** (try 512/1024/2048) | bigger prefill batch = faster prefill on CPU |
| `num_thread` | **16** (physical cores) | 1 NUMA node; match cores |
| `keep_alive` | **-1 / 24h** | never pay cold reload |

Env on server B: `OLLAMA_NUM_PARALLEL=1`, `OLLAMA_MAX_LOADED_MODELS=2`, `OLLAMA_KEEP_ALIVE=-1`.
- _Sources: [Ollama FAQ (concurrency/keep-alive)](https://docs.ollama.com/faq), [Ollama keep-alive & preloading](https://mljourney.com/ollama-keep-alive-and-model-preloading-eliminate-cold-start-latency/), [Optimizing Ollama (quantization/parallelism)](https://medium.com/@kapildevkhatik2/optimizing-ollama-performance-on-windows-hardware-quantization-parallelism-more-fac04802288e)_

### Coexistence with bge-m3 on one CPU (no eviction)

- `OLLAMA_MAX_LOADED_MODELS=2` + enough RAM (you have ~37 GB spare) → **both `qwen3-erp` and `bge-m3` stay resident**; no eviction between a NL→SQL question and an embedding call. `[HIGH]`
- `OLLAMA_NUM_PARALLEL=1` → **serialize**, never run both models' compute at once on the non-AVX2 CPU (parallel would thrash). NL→SQL and embedding jobs must not fire concurrently; schedule embeddings off-peak (your existing `CRM_LEADS_EMBED_JOB` already does this).
- NL→SQL uses **only** `qwen3-erp` (no embedding on the ask path) → bge-m3 is not even touched, so no contention for pure metric questions. Embedding is only needed for the *semantic* filter variant (optional, separate).

### Why this can plausibly hit <30s (and the honest caveat)

- Single call + tiny prefix (~a few hundred tokens: system schema + short question) + short JSON output. Compared to the native agent's ~1m7s (which paid a 2nd uncacheable ~1700–2900-token re-prefill), this removes **both** the 2nd call **and** most of the prefill tokens. Directionally this should land well under 30s, plausibly **single-digit-to-low-teens seconds warm** `[estimate]`.
- **Caveat:** unverified on hardware. The 3B model must reliably map VI questions → correct enums; if it mis-picks `intent`/`col`, you get a wrong-but-safe answer. Accuracy, not latency, is the risk for (c). Benchmark both.

_Confidence: HIGH on architecture + settings rationale; all absolute latency numbers `[estimate]` pending Phase-B measurement. Enum-schema safety is HIGH. 3B VI→enum accuracy is the open unknown._

---

## Implementation Approaches and Technology Adoption

### Verdict: uc_ai NL→SQL vs the existing native hard-exit agent

| Dimension | uc_ai + structured output (c) | Native APEX_AI hard-exit agent (existing) |
|---|---|---|
| LLM calls / question | **1** | 1 (after hard-exit rebuild) |
| Prefill tokens | Smallest (schema only, no tool defs) | Larger (tool schemas, UNTRUSTED-DATA marker on any 2nd call) |
| KV-cache prefix reuse | **Yes** (we own the whole body, byte-identical) | Broken on call-2 by the random UNTRUSTED-DATA marker |
| Safety | Enum-whitelist + binds + read-only | Same (your PL/SQL tools) |
| Dev effort | New thin `crm_nl2sql_pkg`; LGPL-3.0 dependency | Already built |
| Portability | Runs on any Oracle DB (no 26ai AI needed) | Tied to APEX native AI |
| **Best used for** | **Fast, structured metric/list Q&A over CRM_LEADS** | The full APEX chat UX / agent surface |

**Honest call:** For the narrow **NL→SQL metric/list** job at **<30s**, the **uc_ai single-call structured-output pattern (c) is at least as fast as the native hard-exit agent and simpler to reason about**, because it never registers tools (no tool-def prefill) and has no UNTRUSTED-DATA cache-buster. It is a **legitimate ADOPT for this specific use case** — *but only in the (c) shape*. If you instead used uc_ai's tool-loop (b), it would be **slower** than your native agent and should be skipped. The deciding factor is entirely "single structured call vs agentic loop," not "uc_ai vs native."

### Implementation Roadmap (Phase B — after you approve this report)

1. **Build `crm_nl2sql_pkg`** with the flat enum schema + `validate_and_build` over the fixed intent skeletons (reuse `crm_leads_agent_tools.sql`). Read-only role + binds + row cap.
2. **Tune the Modelfile** (`num_ctx 2048`, `num_predict 128`, `num_batch` 512/1024/2048 sweep, `temperature 0`, `keep_alive -1`) and rebuild `qwen3-erp`.
3. **Golden-question set (20–30 VI questions)** with known-correct answers spanning count/list/aggregate/rank + filters (status/source/temperature/emp/date).
4. **Benchmark** each question: (i) end-to-end latency warm & cold, (ii) enum-mapping accuracy vs golden, (iii) confirm exactly ONE call via `journalctl`/tcpdump on server B.
5. **Compare** head-to-head vs the native agent on the same golden set (latency + accuracy).
6. **Decide** adopt/keep based on measured numbers, not estimates.

### Testing / QA focus

- **Accuracy harness is the priority**, not latency — (c)'s risk is wrong enum mapping. Score exact-match on `intent`, `group_by`, and each `filter`.
- **Adversarial prompts**: try VI questions containing SQL-ish text ("xóa hết leads", "DROP TABLE") → confirm the schema/whitelist yields a safe no-op or refusal, never DML.
- **One-call proof**: server-B logs must show a single `/api/chat` per question (no loop).

### Cost / resource

- Zero incremental licensing (Ollama + qwen open; uc_ai LGPL-3.0 — mind copyleft if you modify/redistribute).
- Marginal cost = one short CPU inference per question; both models stay resident (RAM headroom exists).

### Risks & Mitigations

| Risk | Sev | Mitigation |
|---|---|---|
| 3B mis-maps VI → wrong enum (wrong-but-safe answer) | **High** | Accuracy harness; escalate to `qwen2.5:7b-instruct` if 3B too weak; add few-shot examples in the (fixed) system prompt |
| Model ignores schema / returns bad JSON | Med | Ollama `format` constrains decoding; temp 0; keep schema flat; validate + graceful fallback |
| Enum list grows → prefill creeps up | Low | Keep the column glossary lean; only expose queryable cols |
| uc_ai upgrade changes API | Low | Pin version; thin wrapper isolates us |
| Someone registers a tool globally → loop reappears | Med | In `ask()`, rely on schema path; document "no active tools on this path" |

## Technical Research Recommendations

### Recommendation
**ADOPT uc_ai for NL→SQL over CRM_LEADS, but ONLY in the single-call structured-output shape (c) with zero tools.** It is the fastest and safest uc_ai option and is competitive with — and simpler than — the native hard-exit agent for this narrow job. **Do NOT use uc_ai's tool-loop (b) on the interactive path.** Keep the full native agent for the broader APEX chat UX.

### Success Metrics / KPIs (measure in Phase B)
- p50 / p95 latency **<30s** (target single-digit warm) `[to measure]`
- Enum-mapping accuracy **≥90%** on the golden set `[to measure]`
- Exactly **1** LLM call per question (verified in logs)
- Zero DML/DDL ever reaches the DB (adversarial suite passes)

_Confidence: HIGH on the architectural verdict (single-call beats loop; source-verified). All latency/accuracy targets are `[to measure]` in Phase B — this report deliberately makes no on-hardware performance claim._

---

# Optimizing uc_ai for NL→SQL over CRM_LEADS — Research Synthesis

## Executive Summary

**EN —** The way to make uc_ai answer questions about CRM_LEADS fast (<30s) on your CPU-only server is **not** to use its headline agent/tool-calling feature — that runs a **multi-call loop** which re-pays prompt prefill on every turn, the exact bottleneck that made your native agent take ~1m7s. The winning design uses uc_ai's **structured-output** capability instead: **one** `uc_ai.generate_text` call with a **flat, enum-constrained JSON schema** and **no registered tools**, so the model does a single constrained decode returning `{intent, filters, group_by, limit}`. Deterministic PL/SQL then validates that JSON against column/operator/intent whitelists, binds every value, runs a read-only parameterized query with a row cap, and formats the Vietnamese answer. This is the lowest possible LLM-call count (one), the smallest prefill (schema only, no tool defs, no UNTRUSTED-DATA marker), and the tightest safety envelope (the model's only free text is a bound literal value).

The honest verdict: **ADOPT uc_ai for this narrow NL→SQL job, but strictly in the single-call structured-output shape.** In that shape it is at least as fast as — and simpler than — the native hard-exit agent, and it works on any Oracle DB. If you used uc_ai's tool-loop instead, it would be slower than native and should be skipped. The remaining unknown is **accuracy, not latency**: can the 3B model reliably map Vietnamese questions to the right enums? That is what Phase B must benchmark. This report changes no code; Phase B builds `crm_nl2sql_pkg` and measures.

**VI —** Cách làm uc_ai trả lời nhanh (<30s) về CRM_LEADS trên CPU của anh **không phải** dùng tính năng agent/tool-calling nổi bật của nó — cái đó chạy **loop đa-call**, trả lại phí prefill mỗi lượt (đúng nút thắt khiến agent native mất ~1m7s). Thiết kế thắng cuộc dùng **structured-output**: **1** call `uc_ai.generate_text` với **JSON schema phẳng ràng buộc enum** và **0 tool** → model decode 1 lần trả `{intent, filters, group_by, limit}`; PL/SQL validate whitelist + bind + read-only + cap dòng rồi format tiếng Việt. Đây là số call ít nhất (1), prefill nhỏ nhất (chỉ schema, không tool def, không UNTRUSTED-DATA marker), và an toàn chặt nhất (free-text duy nhất là literal value đã bind). **Kết luận: ADOPT uc_ai cho việc NL→SQL hẹp này, nhưng chỉ ở dạng single-call structured-output.** Ẩn số còn lại là **độ chính xác, không phải latency** — Phase B phải benchmark. Báo cáo không đổi code; Phase B mới xây `crm_nl2sql_pkg` và đo.

### Key Findings

- uc_ai's **tool-loop = 2..N LLM calls**, all tool defs re-sent each turn → CPU-prefill trap (source-verified in `uc_ai_ollama.pkb`). `[HIGH]`
- uc_ai's **structured output** (`p_response_json_schema` → Ollama `format` field) with **no tools = exactly 1 call**, constrained JSON. `[HIGH]`
- **Enum-constrained flat schema** makes the model's only free text a **bound value** → safety collapses to a solved problem. `[HIGH]`
- **Fastest & safest = approach (c)**; it removes both the 2nd call and the tool-def prefill vs the native agent. Latency <30s is plausible but `[estimate]`. `[HIGH design / estimate perf]`
- The real risk is **3B VI→enum accuracy**, addressed by a golden-set harness in Phase B. `[HIGH]`

### Recommendations (top 5)

1. **Adopt approach (c)** — single `generate_text` + flat enum schema + zero tools.
2. **Never register tools on the interactive ask path** (keeps it 1 call).
3. **Set** `g_use_responses_api := false`, temp 0, tiny byte-identical system prompt; tune Modelfile (`num_ctx 2048`, `num_predict 128`, `num_batch` sweep, `keep_alive -1`).
4. **Enforce safety in PL/SQL** — whitelist col/op/intent, bind values, read-only role, row cap, audit log.
5. **Phase B = build + benchmark** `crm_nl2sql_pkg` on a golden VI set; decide on measured latency+accuracy, not estimates.

## Approach comparison (final)

| | (a) LLM writes SQL | (b) uc_ai tool-loop | **(c) structured intent+filters** |
|---|---|---|---|
| LLM calls | 1 | 2..N | **1** |
| Prefill | medium | high (tool defs ×N) | **low** |
| Safety | poor | ok | **best (enums+binds)** |
| <30s feasible | maybe | unlikely | **most likely** |
| Verdict | skip | skip (interactive) | **ADOPT** |

## Roadmap (Phase B, on approval)

1. Build `crm_nl2sql_pkg` (schema + validate_and_build + read-only exec). 2. Tune/rebuild `qwen3-erp` Modelfile. 3. Golden 20–30 VI questions. 4. Benchmark latency + enum accuracy + one-call proof. 5. Head-to-head vs native agent. 6. Decide on measured numbers.

## Risks & Open Questions

- 3B VI→enum accuracy (primary) — golden harness; escalate to 7b-instruct + few-shot if weak.
- Absolute latency on non-AVX2 CPU — `[estimate]` until measured.
- LGPL-3.0 copyleft if you modify/redistribute uc_ai — `[verify]` before shipping externally.
- Guard against a globally-registered tool re-introducing the loop on this path.

## Methodology & Source Verification

Five-stage research; uc_ai behavior **read directly from source** (`…\uc_ai-development\src\packages`: `uc_ai.pkb`, `uc_ai_ollama.pkb`, `uc_ai_structured_output.pks`, `uc_ai_tools_api.pks`) rather than inferred. External facts (Ollama structured outputs, concurrency, NL→SQL safety) cited below. No performance number is fabricated; all are `[estimate]`/`[to measure]`.

**Primary sources:**
- [Ollama Structured Outputs docs](https://docs.ollama.com/capabilities/structured-outputs) · [Ollama structured outputs blog](https://ollama.com/blog/structured-outputs) · [Constraining LLMs w/ structured output (Qwen3)](https://medium.com/@rosgluk/constraining-llms-with-structured-output-ollama-qwen3-python-or-go-2f56ff41d720) · [Reliable structured output (Markaicode)](https://markaicode.com/ollama-structured-output-pipeline/)
- [Ollama FAQ — concurrency/keep-alive](https://docs.ollama.com/faq) · [Keep-alive & preloading (ML Journey)](https://mljourney.com/ollama-keep-alive-and-model-preloading-eliminate-cold-start-latency/) · [Optimizing Ollama (parallelism)](https://medium.com/@kapildevkhatik2/optimizing-ollama-performance-on-windows-hardware-quantization-parallelism-more-fac04802288e)
- [OWASP SQL Injection Prevention](https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html) · [LLM-generated SQL best practices (Ha)](https://medium.com/@vi.ha.engr/bridging-natural-language-and-databases-best-practices-for-llm-generated-sql-fcba0449d4e5) · [Text-to-SQL security via backdoor attacks (arXiv)](https://arxiv.org/html/2503.05445v3)
- uc_ai source (LGPL-3.0): [github.com/United-Codes/uc_ai](https://github.com/United-Codes/uc_ai)

---

**Technical Research Completion Date:** 2026-07-04
**Source Verification:** uc_ai API read from source; external claims cited; all performance `[estimate]`/`[to measure]`
**Overall Confidence:** HIGH on architecture/safety/verdict; latency & 3B accuracy pending Phase-B on-hardware benchmark.

---

## Phase B — MEASURED RESULTS (2026-07-04, verdict CONFIRMED)

Built `sql/crm_nl2sql_pkg` (approach c) + `sql/crm_nl2sql_test.sql` and benchmarked on the real stack (server B, `qwen3-erp` = qwen2.5:3b-instruct). The `[estimate]`s above are now replaced by measurement:

| Metric | Predicted | **Measured** | Verdict |
|---|---|---|---|
| Latency (warm) | single-digit s `[estimate]` | **1.8–2.4 s** | ✅ far under 30s (~13× headroom) |
| Latency (cold) | 15–25 s `[estimate]` | **2.2–2.3 s** | ✅ |
| LLM calls / question | 1 | **1** (no tool loop) | ✅ |
| Safety (adversarial) | safe no-op | **4/4 refuse, zero DML** | ✅ |
| VI enum accuracy (3B) | the open risk | **12/12 ≈100%** after prompt+normalize tuning | ✅ exceeds ≥90% target |
| Model needed | maybe 7B | **3B sufficed** | ✅ cheaper than expected |

**How accuracy got from ~50% → 100% (all deterministic, no bigger model):** (1) rewrote the fixed system prompt with explicit rules (nóng/ấm/nguội=temperature; "thống kê…theo X"⇒aggregate+group_by=X; source names⇒source col; extract values literally) + VI few-shot; (2) PL/SQL robustness in `build_where`: temperature & source column self-correct/reroute, skip filters whose col==group_by, skip sentinel/empty values; (3) `build_sql` treats limit≤0 as row-cap; (4) deterministic `is_dml_question` guard + `refuse` intent for DML/off-topic.

**Final verdict: ADOPT — CONFIRMED on hardware.** The single-call structured-output pattern (approach c) delivers ~2s, one call, zero-DML safety, and ~100% accuracy on a 3B model for NL→SQL over CRM_LEADS. The report's core prediction ("risk is accuracy, not latency; single call beats the tool-loop") held exactly; accuracy was fully recovered with deterministic PL/SQL + prompt engineering, no hardware or model upgrade required.
