---
stepsCompleted: [1, 2, 3]
inputDocuments: []
workflowType: 'research'
lastStep: 3
research_type: 'technical'
research_topic: 'APEX 26.1 AI Agent tool fields — Description, Data Description, Execution Point (Augment System Prompt)'
research_goals: 'Hiểu rõ từng ô cấu hình của một AI Tool dùng để làm gì + tầm quan trọng, đặc biệt Data Description và per-tool system-prompt'
user_name: 'Gia Huy'
date: '2026-06-30'
web_research_enabled: true
source_verification: true
---

# Research Report: Technical — Các trường cấu hình của AI Tool trong APEX 26.1

**Date:** 2026-06-30 · **Author:** Gia Huy · **Research Type:** technical

## Research Overview

Làm rõ MỖI ô text khi tạo một AI Agent Tool trong APEX 26.1 dùng để làm gì, tầm quan
trọng, và phân biệt với system prompt cấp agent. Trọng tâm: (1) trường mà người dùng
gọi là "system prompt cấp tool" = **Execution Point: Augment System Prompt**;
(2) **Data Description** — trường đã bị bỏ sót khi cấu hình 6 tool CRM_LEADS.

## 1. Hai cấp "prompt": Agent vs Tool

- **System Prompt (CẤP AGENT)** — cấu hình MỘT lần cho cả agent: persona + mục tiêu +
  luật chung (chính là nội dung §1 ta dán vào Instructions). Áp cho mọi lượt.
- Mỗi **TOOL** có bộ trường riêng (dưới đây). Các Description của tool **làm việc
  CÙNG** system prompt agent để model biết có năng lực gì.

## 2. Các trường của một TOOL (APEX 26.1)

| Trường | Dùng để làm gì | Pha trong vòng lặp |
|---|---|---|
| **Name** | Tên hàm tool; model gọi theo tên này (vd `rank_leads`). | Định danh |
| **Type** | Retrieve Data (SQL) / Execute Server-side Code (PL/SQL) / Execute Client-side Code (JS). | Cách thực thi |
| **Execution Point** | **Augment System Prompt** hoặc **On Demand** (xem §3). | Trước khi gọi |
| **Description** | Cho model biết **KHI NÀO / TẠI SAO** gọi tool này (định tuyến). | TRƯỚC khi gọi |
| **Data Description** | Mô tả **Ý NGHĨA DỮ LIỆU TRẢ VỀ** (các cột là gì) để model ĐỌC HIỂU & diễn giải kết quả đúng. | SAU khi gọi |
| **Parameters** | Mỗi tham số có Description riêng → model biết điền gì vào đâu. | Khi gọi |

## 3. Execution Point — "system prompt cấp tool"

- **Augment System Prompt:** tool chạy **LUÔN mỗi lượt**, kết quả được **chèn sẵn vào
  system prompt** làm ngữ cảnh nền. Model KHÔNG cần "quyết định gọi". Hợp với dữ liệu
  **tham chiếu nhỏ, tĩnh, hầu như câu nào cũng cần** (vd: tập trạng thái hợp lệ, thông
  tin nhân viên đang đăng nhập). **Nhược:** tốn token MỖI lượt → **tăng prefill** (đắt
  trên CPU).
- **On Demand:** model **tự quyết định** gọi khi cần (function-calling). Hợp với tool
  nặng/đặc thù. **5–6 tool CRM_LEADS đều nên để On Demand.**

## 4. Tầm quan trọng của Data Description (trường đã bỏ sót)

- Description trả lời "**khi nào DÙNG**" (trước khi gọi). Data Description trả lời
  "**kết quả NGHĨA LÀ GÌ**" (sau khi gọi) — phục vụ 2 pha khác nhau của agentic loop.
- Thiếu Data Description → model nhận về các cột thô (vd `distance`, `score`, `cnt`,
  `avg_score`) mà **không biết diễn giải** → trả lời sai/mơ hồ. Ví dụ: với
  `search_leads_semantic`, model cần biết `distance` nhỏ = gần/đúng hơn; với
  `query_lead_metrics`, `cnt` là số lead, `avg_score` là điểm trung bình.
- **Quan trọng nhất cho:** `rank_leads` (score, thứ hạng), `query_lead_metrics`
  (cnt/avg/sum), `search_leads_semantic` (distance). Các tool lookup trả cột tên rõ
  thì Data Description có thể ngắn.

## 5. Hệ quả cho dự án (tốc độ + chất lượng)

- **Tốc độ:** ưu tiên **On Demand**; hạn chế "Augment System Prompt" vì nó nhồi token
  vào system prompt mỗi lượt → đội prefill (đã là nút thắt trên CPU, xem báo cáo
  latency). Nếu cần dữ liệu nền tĩnh (vd tập enum status), cân nhắc nhồi thẳng 1 dòng
  vào §1 thay vì 1 tool Augment (rẻ token hơn).
- **Chất lượng:** BỔ SUNG Data Description ngắn gọn (tiếng Việt có dấu) cho ít nhất
  `rank_leads`, `query_lead_metrics`, `search_leads_semantic` để model diễn giải đúng
  cột. Giữ ngắn để không phá ngân sách prefill.
- **Nguyên tắc viết** (prompt-engineering cho 2 ô này): Description = điều kiện kích
  hoạt + ranh giới "KHÔNG dùng khi..."; Data Description = liệt kê cột + đơn vị/ý nghĩa,
  1 câu. Cả hai đặt token tối thiểu vì đều nằm trong payload mỗi lượt.

## Sources
- [Move from Insights to Action with AI Agents in Oracle APEX](https://blogs.oracle.com/apex/ai-agents-in-oracle-apex)
- [Build Your First AI Agent in Oracle APEX (maxapex) — Data Description, fields](https://www.maxapex.com/blogs/build-ai-agent-oracle-apex/)
- [How to Add an AI Agent to an Oracle APEX Application (cloudnueva)](https://blog.cloudnueva.com/adding-ai-agent-to-apex-app)
- [Oracle APEX 26.1 — New Features](https://docs.oracle.com/en/database/oracle/apex/26.1/htmrn/new-features.html)
- [Oracle APEX 26.1 AI Architecture (bigdba)](https://www.bigdba.com/oracle/2336/oracle-apex-26-1-ai-architecture-apexlang-native-ai-agents-and-declarative-natural-language-interfaces/)
