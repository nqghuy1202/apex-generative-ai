# Vòng 1 — Quick wins tối ưu tốc độ AI Assistant (CPU)

Mục tiêu: đưa thời gian phản hồi từ **80–153s** xuống **5–15s/câu**.
Báo cáo đầy đủ: `_bmad-output/planning-artifacts/research/technical-cpu-llm-speed-optimization-research-2026-06-29.md`

Thực hiện **4 bước** dưới đây rồi **đo lại log** (`journalctl -u ollama -f`).

---

## Bước 1 — Kéo model nhỏ hơn (Đòn bẩy #2)

Trên server Linux (host chạy Ollama):

```bash
ollama pull qwen3:4b          # ~3GB thay vì 5.8GB của qwen3.5
```

## Bước 2 — Tạo model tùy biến: tắt thinking + temp thấp (Đòn bẩy #1 + #4)

Tạo file `Modelfile-erp` rồi build:

```text
FROM qwen3:4b
PARAMETER temperature 0.1
PARAMETER num_ctx 2048
PARAMETER num_predict 512
SYSTEM """/no_think
Bạn là trợ lý ERP. Trả lời ngắn gọn, đi thẳng kết quả.
Khi cần dữ liệu khách hàng, gọi đúng tool. Không bịa tên bảng/cột."""
```

```bash
ollama create qwen3-erp -f Modelfile-erp
ollama run qwen3-erp --verbose      # test nhanh + xem tok/s
```

> Lưu ý: nếu APEX gửi system prompt riêng đè lên, hãy thêm `/no_think` vào
> **system prompt cấu hình trong AI Service/Assistant của APEX** thay vì Modelfile.

## Bước 3 — Đổi model trong APEX

Trong AI Service tĩnh mà AI Assistant đang dùng → đổi model sang **`qwen3-erp`**
(hoặc `qwen3:4b` nếu đặt `/no_think` ở system prompt của APEX).

## Bước 4 — Giảm RAG top-k 5 → 3 (Đòn bẩy #3)

Cập nhật SQL của tool `search_customers_semantic` theo `optimize_llm_speed_round1.sql`
(`fetch approx first 3 rows only`).

---

## Đo lại & quyết định

Chạy lại "Show AI Assistant", xem log:

```bash
journalctl -u ollama -f
```

Tìm dòng `eval time ... tokens per second` và `[GIN] ... POST /api/chat`.
- ✅ Nếu tổng thời gian về **5–15s** → xong Vòng 1.
- ❌ Nếu chưa đạt → sang **Vòng 2** (biến môi trường Ollama, rút tool schema,
  cắt lịch sử chat) — xem mục 3 trong báo cáo.

> ⚠️ Sau khi giảm top-k & tắt thinking, hãy thử vài câu hỏi tiếng Việt thực tế
> để chắc chắn **độ chính xác không tụt** (đánh đổi tốc độ ↔ chất lượng).
