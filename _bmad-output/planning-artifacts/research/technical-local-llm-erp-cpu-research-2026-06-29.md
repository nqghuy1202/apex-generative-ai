---
title: "Local LLM Models for ERP on CPU-only — Technical Research"
research_type: technical
research_topic: "Best local LLM models for ERP (CPU-only, bilingual EN-VI)"
date: 2026-06-29
author: Gia Huy (facilitated by BMad Technical Research)
stepsCompleted: [1, 2, 3]
status: complete
---

# Nghiên cứu kỹ thuật: Mô hình LLM chạy Local cho hệ thống ERP (CPU-only, song ngữ Anh–Việt)
# Technical Research: Local LLM Models for ERP (CPU-only, Bilingual EN–VI)

> **Grounding note / Lưu ý nguồn:** Mọi số liệu tốc độ/RAM dưới đây là **ước tính tổng hợp từ nguồn công khai 2026** và phụ thuộc mạnh vào CPU cụ thể, số luồng, độ dài context. Các điểm chưa kiểm chứng được đánh dấu `[chưa chắc chắn]`. Không có benchmark nào được bịa ra; nơi nguồn không nói rõ, đã ghi rõ.

---

## 1. Tóm tắt điều hành / Executive Summary

**Bối cảnh:** Chọn LLM chạy **chỉ trên CPU** (không GPU rời) cho ERP, song ngữ Anh–Việt, tích hợp qua Ollama vào pipeline APEX 26.1 + DB 26ai hiện có (đã dùng `bge-m3` để embedding). Bốn nhiệm vụ: (1) RAG hỏi-đáp, (2) Text-to-SQL/báo cáo, (3) function-calling/agent, (4) tóm tắt & trích xuất.

**Kết luận nhanh:**

| Vai trò | Model đề xuất | Lý do |
|---|---|---|
| 🏆 **An toàn nhất (cân bằng chất lượng)** | **Qwen3-4B (Q4_K_M, GGUF)** | Tiếng Việt tốt nhất trong nhóm nhỏ, function-calling & Text-to-SQL mạnh nhất phân khúc, Apache-2.0, chạy được trên ~6–8 GB RAM. |
| ⚡ **Nhanh nhất (latency thấp)** | **Gemma 3 2B (Q4)** hoặc **Llama 3.2 3B (Q4)** | ~15 tok/s và ~10 tok/s trên CPU, RAM 2–4 GB. Đổi lại chất lượng tiếng Việt & function-calling yếu hơn. |
| 🤝 **Phương án "vừa đủ" 1 model duy nhất** | **Qwen3-4B** | Nếu chỉ chạy 1 model cho cả 4 nhiệm vụ, đây là lựa chọn rủi ro thấp nhất. |

**Khuyến nghị triển khai:** Bắt đầu với **Qwen3-4B Q4_K_M**. Nếu CPU quá yếu (latency > vài giây/câu không chấp nhận được), hạ xuống **Llama 3.2 3B** cho các nhiệm vụ đơn giản (tóm tắt, chat) và **giữ Qwen3-4B riêng cho Text-to-SQL/function-calling** — kiến trúc "2 model theo nhiệm vụ".

---

## 2. Ràng buộc & tiêu chí / Constraints & Criteria

- **Phần cứng:** CPU-only, máy yếu → giới hạn thực tế **1B–8B tham số, quantized Q4/Q5 GGUF**. Model > 8B (kể cả MoE lớn như Qwen3-235B) **bị loại** dù chất lượng cao hơn, vì không chạy nổi trên CPU yếu.
- **Ngôn ngữ:** Song ngữ Anh–Việt là bắt buộc → ưu tiên model đa ngôn ngữ mạnh tiếng Việt.
- **Tích hợp:** Phải có sẵn trên **Ollama** (OpenAI-compatible API) để khớp pipeline APEX hiện tại.
- **Ưu tiên #1 = Tốc độ** (tokens/giây trên CPU). **Ưu tiên #2 = Độ chính xác** (hallucination thấp, function-calling & Text-to-SQL đúng).

---

## 3. Bảng so sánh các ứng viên / Candidate Comparison

> Tốc độ là **ước tính trên CPU desktop tầm trung (vd i7-12700, Q4)** theo nguồn công khai. Máy yếu hơn sẽ chậm hơn đáng kể.

| Model | Kích thước (Q4 GGUF) | RAM tối thiểu | Tốc độ ước tính (CPU) | Tiếng Việt | Function-calling | Text-to-SQL | Giấy phép |
|---|---|---|---|---|---|---|---|
| **Qwen3-4B** | ~2.5–3 GB | 6–8 GB | ~7–10 tok/s `[chưa chắc chắn]` | ⭐⭐⭐⭐ Tốt nhất nhóm nhỏ | ⭐⭐⭐⭐ Mạnh (agent-native) | ⭐⭐⭐⭐ ~90–95% trên semantic model đơn giản | Apache-2.0 |
| **Qwen3-7B/8B** | ~5 GB | 8–16 GB | ~4–6 tok/s | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | Apache-2.0 |
| **Llama 3.2 3B** | ~2 GB | 2.5–6 GB | ~10 tok/s | ⭐⭐⭐ Khá | ⭐⭐⭐ Trung bình | ⭐⭐ Yếu | Llama Community |
| **Gemma 3 2B** | ~1.5 GB | 2–4 GB | ~15 tok/s (nhanh nhất) | ⭐⭐ Trung bình | ⭐⭐ Hạn chế | ⭐⭐ Yếu | Gemma (cho phép TM) |
| **Gemma 3 4B** | ~2.5 GB | ~4.2 GB | trung bình (hiệu suất RAM tốt nhất) | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | Gemma |
| **Phi-4-mini (3.8B)** | ~2.3 GB | 3–6 GB | ~12 tok/s | ⭐⭐ Yếu tiếng Việt `[chưa chắc chắn]` | ⭐⭐⭐ | ⭐⭐⭐ | MIT |
| **Mistral 7B / Small** | ~4–5 GB | 6–12 GB | ~4–6 tok/s | ⭐⭐ Trung bình-yếu | ⭐⭐⭐⭐ Tốt cho agent | ⭐⭐⭐ | Apache-2.0 |
| **PhoGPT / Vistral / SeaLLM** | tuỳ bản | ~4–8 GB | `[chưa chắc chắn]` | ⭐⭐⭐⭐ Chuyên tiếng Việt/ĐNÁ | ⭐⭐ Hạn chế (ít hỗ trợ tool) | ⭐ Yếu | tuỳ model |

**Ghi chú về model chuyên tiếng Việt:** PhoGPT (VinAI), Vistral (Viet-Mistral), SeaLLM (Đông Nam Á) mạnh về *văn phong tiếng Việt thuần*, nhưng **không tìm được benchmark 2026 cập nhật** về function-calling/Text-to-SQL và **ít hỗ trợ tool-calling chuẩn** — rủi ro cho nhiệm vụ agent/SQL của ERP. `[chưa chắc chắn]` Với ERP cần cả 4 nhiệm vụ, Qwen3 (đa ngôn ngữ + agent-native) thực dụng hơn một model chỉ giỏi tiếng Việt.

---

## 4. Chấm điểm theo 4 nhiệm vụ + 2 tiêu chí / Scoring (1–5)

| Model | RAG | Text-to-SQL | Function-calling | Tóm tắt/Trích xuất | Tốc độ (CPU) | Độ chính xác | **Tổng** |
|---|---|---|---|---|---|---|---|
| **Qwen3-4B** | 4 | 4 | 4 | 4 | 3 | 4 | **23** 🏆 |
| Qwen3-7B/8B | 5 | 4 | 5 | 5 | 2 | 5 | 26* |
| Llama 3.2 3B | 3 | 2 | 3 | 4 | 4 | 3 | 19 |
| Gemma 3 2B | 3 | 2 | 2 | 3 | 5 | 3 | 18 |
| Phi-4-mini | 3 | 3 | 3 | 3 | 4 | 3 | 19 |
| Mistral 7B | 3 | 3 | 4 | 3 | 2 | 3 | 18 |

*Qwen3-7B/8B điểm cao nhất về chất lượng nhưng **tốc độ CPU thấp** — chỉ chọn nếu máy có ≥16 GB RAM và chấp nhận ~4–6 tok/s. Với ràng buộc "tốc độ là #1", **Qwen3-4B là điểm cân bằng tốt nhất**.

---

## 5. Khuyến nghị cuối / Final Recommendations

### 🏆 An toàn nhất: **Qwen3-4B**
- Cân bằng tốt nhất giữa 4 nhiệm vụ ERP và ràng buộc CPU.
- Agent-native (function-calling, có thinking/non-thinking mode), đa ngôn ngữ >100 ngôn ngữ gồm tiếng Việt, Apache-2.0 (an toàn thương mại).
- **Cấu hình tối thiểu:** Q4_K_M GGUF, **~8 GB RAM**, context 4K–8K cho RAG.

### ⚡ Nhanh nhất: **Gemma 3 2B (Q4)** — hoặc **Llama 3.2 3B (Q4)** nếu cần chất lượng nhỉnh hơn
- ~15 tok/s / ~10 tok/s, RAM 2–4 GB. Phù hợp khi tốc độ là tất cả và nhiệm vụ chủ yếu là chat/tóm tắt tiếng Anh.
- **Cảnh báo:** Text-to-SQL và tiếng Việt yếu hơn rõ rệt → không nên dùng làm engine SQL/agent chính.

### 🤝 Kiến trúc đề xuất cho ERP (thực dụng nhất)
- **1 model duy nhất:** Qwen3-4B cho mọi việc (đơn giản hoá vận hành).
- **2 model theo nhiệm vụ** (nếu CPU đuối): Llama 3.2 3B / Gemma 3 2B cho chat+tóm tắt nhanh; Qwen3-4B dành riêng cho Text-to-SQL + function-calling (nơi độ chính xác quan trọng hơn tốc độ).
- **Cấu hình RAM/quantization tối thiểu khuyến nghị:** **8 GB RAM, Q4_K_M**. Nếu chỉ 4 GB RAM → buộc dùng model 2–3B (Gemma 3 2B / Llama 3.2 3B), chấp nhận giảm chất lượng SQL/agent.

---

## 6. Tích hợp vào pipeline APEX hiện tại / Integration with Existing APEX Pipeline

Pipeline hiện tại đã dùng Ollama cho embedding `bge-m3`. Thêm LLM sinh (generation) song song:

```bash
# 1. Kéo model về Ollama (ví dụ Qwen3-4B)
ollama pull qwen3:4b           # hoặc bản quantized cụ thể: qwen3:4b-q4_K_M

# 2. (Tuỳ chọn) Tạo Modelfile đặt system prompt + nhiệt độ thấp cho ERP/SQL
#    Temperature 0.1 cho Text-to-SQL/deterministic; 0.7 cho tóm tắt tự nhiên.
```

```text
# Modelfile (ví dụ cho nhiệm vụ Text-to-SQL)
FROM qwen3:4b-q4_K_M
PARAMETER temperature 0.1
PARAMETER num_ctx 8192
SYSTEM """Bạn là trợ lý ERP. Chỉ trả về SQL hợp lệ cho Oracle DB 26ai.
Không bịa tên bảng/cột. Nếu thiếu thông tin, hỏi lại."""
```

- **Trong APEX / DB 26ai:** Vì đã có Generative AI Service tĩnh (`apex-embed`) trỏ Ollama cho embedding, tạo thêm **một service tĩnh thứ hai** (vd `apex-llm`) trỏ cùng host:port Ollama nhưng dùng model sinh ở trên. Gọi qua `apex_ai`/`DBMS_VECTOR_CHAIN` tương tự cách `get_vector_embeddings` đang dùng.
- **Provider = Ollama, Base URL = host:port** (không thêm `/v1/...`) — đúng như ghi chú vận hành đã xác lập trong dự án.
- **Luồng RAG end-to-end:** câu hỏi → embed (`bge-m3`) → `VECTOR_DISTANCE` lấy top-k chunk → nhồi context vào prompt → **Qwen3-4B** sinh câu trả lời/SQL.

---

## 7. Rủi ro & bước tiếp theo / Risks & Next Steps

- ⚠️ **Tốc độ CPU là rủi ro lớn nhất.** ~7 tok/s nghĩa là một câu trả lời dài có thể mất nhiều giây. **Cần benchmark thực tế trên chính máy đích** trước khi chốt — đây là số liệu duy nhất đáng tin hơn mọi ước tính ở trên.
- ⚠️ **Model chuyên tiếng Việt (PhoGPT/Vistral/SeaLLM)** thiếu dữ liệu function-calling 2026 → cần thử nghiệm riêng nếu chất lượng tiếng Việt của Qwen3-4B chưa đạt.
- ✅ **Bước tiếp theo đề xuất:** (1) `ollama pull qwen3:4b` + `llama 3.2:3b`; (2) đo tok/s thực tế trên máy đích với prompt ERP thật; (3) tạo bộ 10–20 câu test cho mỗi nhiệm vụ (RAG/SQL/agent/tóm tắt) bằng tiếng Việt để chấm độ chính xác; (4) chốt 1-model hay 2-model.

---

## Nguồn / Sources

- [CPU-Only LLM 2026: Phi-4 Mini Runs 12 tok/s, No GPU — PromptQuorum](https://www.promptquorum.com/local-llms/best-cpu-only-llm)
- [Best Small Language Models 2026 (SLMs Ranked) — Local AI Master](https://localaimaster.com/blog/small-language-models-guide-2026)
- [Best Open-Source LLM Models in 2026 — Hugging Face Blog](https://huggingface.co/blog/daya-shankar/open-source-llms)
- [Ultimate Guide - Best Open Source LLM For Vietnamese In 2026 — SiliconFlow](https://www.siliconflow.com/articles/en/best-open-source-LLM-for-Vietnamese)
- [Qwen3 — GitHub (QwenLM/Qwen3)](https://github.com/QwenLM/Qwen3)
- [Qwen-3-4b Text-to-SQL — Hugging Face](https://huggingface.co/Ellbendls/Qwen-3-4b-Text_to_SQL)
- [Text-to-SQL using Local LLMs — datamonkeysite](https://datamonkeysite.com/2026/03/31/text-to-sql-using-semantic-models-and-small-language-models/)
- [Open Source LLM Comparison Table (2026) — ComputingForGeeks](https://computingforgeeks.com/open-source-llm-comparison/)
- [Best Open Source LLMs In 2026 — AceCloud](https://acecloud.ai/blog/best-open-source-llms/)
</content>
</invoke>
