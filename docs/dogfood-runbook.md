# Dogfood Runbook — Deploy nội bộ 2× DGX Spark (DeepSeek V4 Flash 0731)

> **Trạng thái: BLOCKED — chờ máy vật lý về.** Các bước [HW] cần 2× DGX Spark + cáp QSFP56 RoCE 200G. Đây là runbook nội bộ 5ac (dogfood lab + demo khách), khác với checklist bàn giao khách ở mức độ chi tiết kỹ thuật và giả định kiểm soát hoàn toàn hạ tầng.

---

## 0. Yêu cầu & điều kiện tiên quyết

**Phần cứng (đã chốt Q6):**
- [HW] 2× DGX Spark / ASUS Ascent GX10 (NVIDIA GB10, 128GB unified RAM, 4TB NVMe)
- [HW] Cáp **QSFP56 RoCE 200G DAC** (NVIDIA/Mellanox MCP1650-H00AE30) nối 2 node

**Mục tiêu TP=2:** chạy official **FP8 DeepSeek V4 Flash 0731 (~149GB)** ở **1M context thật**. 1 máy 128GB không đủ (crash); RTX PRO cap 131K.

**Nguồn recipe:** [MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark](https://github.com/MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark) (777★) — chỉ dùng serving config + image Anemll. Research: `/root/5ac/research/model-serving/miaai-lab-dgx-spark-research-2026-08-19.md`.

---

## 1. Chuẩn bị node (cần máy vật lý) — [HW]

Trên **cả 2 node**:

```bash
# 1. OS + driver
#    Ubuntu ARM64 (aarch64), cài NVIDIA CUDA driver, verify
nvidia-smi          # GB10 ~121.7 GiB unified

# 2. Docker engine
docker --version

# 3. Pull image Anemll (TP=2 DSpark)
docker pull ghcr.io/anemll/dspark-vllm-gx10:0.1.1

# 4. TẮT earlyoom (BẮT BUỘC — nếu không sẽ giết vLLM dưới deep-context load)
systemctl stop earlyoom && systemctl disable earlyoom
systemctl is-active earlyoom   # → inactive

# 5. Cài huggingface_hub + fetch official checkpoint
pip install -U "huggingface_hub[cli]"
huggingface-cli download deepseek-ai/DeepSeek-V4-Flash-0731 \
  --revision 9e165c30 --local-dir /root/.cache/huggingface/deepseek-ai/DeepSeek-V4-Flash-0731
```

> Có thể dùng `./scripts/prepare-dspark-model-cache.sh --official` từ repo này.

## 2. Cấu hình mạng RoCE (cần máy vật lý) — [HW]

```bash
# Xác định IB HCA cho link QSFP56 200G
ibstat                 # State=Active, Rate=200Gb → ghi mlx5_x vào NCCL_IB_HCA
ip a                   # xác định ethernet iface → NCCL_SOCKET_IFNAME

# Ping đối tác qua RoCE
# (tùy topology: IPoIB hoặc ethernet control plane)
```

Gán IP tĩnh worker/head; ghi vào `.env.dspark`:
```
WORKER_HOST=10.0.0.2
MASTER_ADDR=10.0.0.1
NCCL_IB_HCA=mlx5_0
NCCL_SOCKET_IFNAME=eth0
VLLM_HOST_IP=<ip node này>
HF_CACHE=/root/.cache/huggingface
```

## 3. Khởi động (worker trước, head sau)

```bash
# Trên WORKER node trước
./scripts/start-deepseek-v4-flash-dspark.sh
# Trên HEAD node sau
./scripts/start-deepseek-v4-flash-dspark.sh
```

Script tự kiểm tra earlyoom (chặn start nếu active) và set đủ env profile 1M/6.

## 4. Verify 1M context

```bash
# API model metadata — PHẢI thấy max_model_len 1048576
curl :8888/v1/models

# Smoke test đầy đủ (1M ctx + stream + non-stream)
./scripts/smoke-test.sh

# Status cả 2 node
./scripts/status-deepseek-v4-flash-dspark.sh
```

## 5. Vận hành & hotfix

- **earlyoom**: tắt trên cả 2 host (xem bước 1).
- **#55 tool-truncation**: `finish_reason="length"` khi max_tokens cắt giữa tool call (tránh transcript bị 400 poison) — luôn chạy.
- **#79 spin-wait P-core**: hotfix ON mặc định (giảm hao Grace P-core). Opt-out `DSPARK_SKIP_SPIN_WAIT_HOTFIX=1`.
- **#52 assistant-final**: **opt-in** `DSPARK_ENABLE_ASSISTANT_FINAL_HOTFIX=1` (bắt buộc cho agent harness — tránh no-op turns + DSML ảo giác; fail-closed, idempotent).
- **#72 sau reboot**: container up → `exit 3` → systemd `SuccessExitStatus=3`.
- **#81 RULER-lite**: bulk-pad đúng 32k/262k cells.
- **#21/#26/#27/#43**: luôn chạy (không bị `DSPARK_SKIP_HOTFIX` bỏ qua); **#22** riêng biệt.
- `VLLM_DSPARK_*` là no-op trên Anemll 0.1.1 (chỉ hiệu lực khi đổi image Stage-C).
- VL sidecar (tùy chọn): `ENABLE_VL_SIDECAR=1` → Qwen3-VL :8889 + MCP.
- Responses API live verifier: `verify-responses-api-live.py` (4 gates); stateful continuation cần `VLLM_ENABLE_RESPONSES_API_STORE=1`.

## 6. Tốc độ kỳ vọng (default Anemll 1M/6)

| Kịch bản | Tốc độ | Ghi chú |
|---|---|---|
| 1 chat ≤128K | **~62-83 tok/s** decode sau first token | |
| 6 short chats | **~160-190 tok/s** aggregate (~30-37/stream) | |
| 6 cold 32K-128K prompts | prefill **queue** (issue #27), ~8 tok/s floor | |

## 7. Danh sách bước BLOCKED chờ máy

Các bước cần **máy vật lý** (không thực hiện được trước khi máy về): toàn bộ mục **1** (chuẩn bị node), **2** (RoCE mạng), và **3-4** (start + verify). Không block được, chỉ khi máy về.

---

# (EN) Internal Dogfood Runbook — 2× DGX Spark Deploy

> **Status: BLOCKED — awaiting physical hardware.** Steps marked [HW] need 2× DGX Spark + QSFP56 RoCE 200G cable. Internal 5ac runbook (dogfood lab + customer demo), more technically detailed than the customer handoff checklist.

## 0. Prereqs
- [HW] 2× DGX Spark / ASUS Ascent GX10 (GB10, 128GB unified, 4TB NVMe)
- [HW] **QSFP56 RoCE 200G DAC** (NVIDIA/Mellanox MCP1650-H00AE30)
- Goal TP=2: run official **FP8 DeepSeek V4 Flash 0731 (~149GB)** at **real 1M context**.

## 1. Node prep (needs hardware) — [HW]
On **both nodes**: Ubuntu ARM64 + CUDA driver (`nvidia-smi` ~121.7 GiB), Docker, `docker pull ghcr.io/anemll/dspark-vllm-gx10:0.1.1`, **STOP earlyoom**, download official `deepseek-ai/DeepSeek-V4-Flash-0731` @ `9e165c30`.

## 2. RoCE networking (needs hardware) — [HW]
`ibstat` → find 200G HCA → set `NCCL_IB_HCA` / `NCCL_SOCKET_IFNAME` / `WORKER_HOST` / `MASTER_ADDR` / `VLLM_HOST_IP`.

## 3. Start (worker first, head second)
`./scripts/start-deepseek-v4-flash-dspark.sh` on worker then head.

## 4. Verify 1M
`curl :8888/v1/models` → `max_model_len 1048576`; `./scripts/smoke-test.sh`; `./scripts/status-...`.

## 5. Ops & hotfix — same table as VI section 5.

## 6. Expected throughput — same as VI section 6.

## 7. Hardware-blocked steps
All of sections 1-4 are hardware-blocked until the machines arrive.
