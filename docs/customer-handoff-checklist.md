# Checklist bàn giao khách — Cụm 2× DGX Spark (Local AI Engine)

> Mục đích: checklist kỹ thuật + vận hành khi bàn giao cụm on-prem 2× DGX Spark cho khách SMB Việt Nam. Dùng chung cho đợt demo khách và bán theo đơn. Đối chiếu với runbook nội bộ `docs/dogfood-runbook.md`.

## A. Phần cứng (bàn giao vật lý)

- [ ] 2× DGX Spark / ASUS Ascent GX10 (NVIDIA GB10, 128GB unified RAM) — khớp SKU đặt hàng
- [ ] Cáp **QSFP56 RoCE 200G DAC** (NVIDIA/Mellanox MCP1650-H00AE30) kết nối 2 node
- [ ] Nguồn điện + dây nguồn, quy trình cắm đúng thứ tự (an toàn)
- [ ] Ảnh/ghi chú vị trí rack, label hostname worker/head

## B. Hệ điều hành & mạng

- [ ] Ubuntu (ARM64/aarch64) cài trên cả 2 node, kernel driver NVIDIA CUDA OK
- [ ] `nvidia-smi` chạy được, GB10 thấy ~121.7 GiB unified
- [ ] IP tĩnh worker/head đặt trong `.env.dspark` (`WORKER_HOST`, `MASTER_ADDR`, `VLLM_HOST_IP`)
- [ ] RoCEv2 lên: `ibstat` State=Active, Rate=200Gb (QSFP56)
- [ ] `NCCL_IB_HCA` + `NCCL_SOCKET_IFNAME` đúng interface

## C. Docker & image

- [ ] Docker engine trên cả 2 node
- [ ] `docker pull ghcr.io/anemll/dspark-vllm-gx10:0.1.1` thành công (image Anemll, TP=2 DSpark)

## D. Model checkpoint (chỉ official)

- [ ] Chỉ dùng `deepseek-ai/DeepSeek-V4-Flash-0731` @ `9e165c30` (ABLITERATED=0)
- [ ] **KHÔNG dùng models HF MiaAI-Lab** (`Qwable`/`Gemmable` — nghi fake/dequantized)
- [ ] `HF_CACHE` trỏ đúng, cache đầy đủ trên cả 2 node

## E. Cấu hình serving (default profile)

| Knob | Giá trị |
|---|---|
| MAX_MODEL_LEN | 1048576 (1M) |
| MAX_NUM_SEQS | 6 |
| MAX_NUM_BATCHED_TOKENS | 8192 |
| MTP_NUM_TOKENS | 5 |
| DEFAULT_THINKING | max |
| VLLM_USE_BREAKABLE_CUDAGRAPH | 0 |
| --max-cudagraph-capture-size | 36 |

## F. Vận hành (bắt buộc)

- [ ] **TẮT earlyoom cả 2 host**: `systemctl stop earlyoom && systemctl disable earlyoom`
- [ ] Hotfix #55/#26/#21/#27/#43 luôn chạy; #22 riêng biệt
- [ ] #79 spin-wait P-core: mặc định hotfix ON (opt-out `DSPARK_SKIP_SPIN_WAIT_HOTFIX=1`)
- [ ] #52 assistant-final: opt-in `DSPARK_ENABLE_ASSISTANT_FINAL_HOTFIX=1` cho agent harness
- [ ] #72 sau reboot: systemd `SuccessExitStatus=3`
- [ ] #81 RULER-lite context: bulk-pad đúng 32k/262k
- [ ] `VLLM_DSPARK_*` no-op trên Anemll 0.1.1 (chỉ hiệu lực image Stage-C)

## G. Khởi động & verify

- [ ] Worker node start TRƯỚC, head node sau
- [ ] `curl :8888/v1/models` → `max_model_len: 1048576`
- [ ] `./scripts/smoke-test.sh` PASS (1M ctx + stream + non-stream)
- [ ] `./scripts/status-deepseek-v4-flash-dspark.sh` trên cả 2 node OK

## H. Bàn giao khách (SLA/vận hành)

- [ ] Document quick start + `.env.dspark.example` giải thích cho khách
- [ ] Hướng dẫn `./scripts/start|stop|status|smoke-test`
- [ ] Liệt kê hotfix & lưu ý earlyoom trong tài liệu khách
- [ ] Khách ký xác nhận đã nhận + hiểu quy trình vận hành

---

# Customer Handoff Checklist — 2× DGX Spark Cluster (Local AI Engine)

> Purpose: technical + ops checklist when handing over an on-prem 2× DGX Spark cluster to a Vietnamese SMB customer. Shared for customer demos and build-to-order sales. Cross-references `docs/dogfood-runbook.md`.

## A. Hardware (physical handoff)
- [ ] 2× DGX Spark / ASUS Ascent GX10 (NVIDIA GB10, 128GB unified RAM) — matches ordered SKU
- [ ] **QSFP56 RoCE 200G DAC** (NVIDIA/Mellanox MCP1650-H00AE30) linking both nodes
- [ ] Power + cables, correct plug order (safety)
- [ ] Rack position notes, worker/head hostname labels

## B. OS & networking
- [ ] Ubuntu (ARM64/aarch64) on both nodes, NVIDIA CUDA driver OK
- [ ] `nvidia-smi` runs, GB10 sees ~121.7 GiB unified
- [ ] Static worker/head IPs in `.env.dspark` (`WORKER_HOST`, `MASTER_ADDR`, `VLLM_HOST_IP`)
- [ ] RoCEv2 up: `ibstat` State=Active, Rate=200Gb (QSFP56)
- [ ] `NCCL_IB_HCA` + `NCCL_SOCKET_IFNAME` correct

## C. Docker & image
- [ ] Docker engine on both nodes
- [ ] `docker pull ghcr.io/anemll/dspark-vllm-gx10:0.1.1` OK (Anemll image, TP=2 DSpark)

## D. Model checkpoint (official only)
- [ ] Use only `deepseek-ai/DeepSeek-V4-Flash-0731` @ `9e165c30` (ABLITERATED=0)
- [ ] **Do NOT use MiaAI-Lab HF models** (`Qwable`/`Gemmable` — suspected fake/dequantized)
- [ ] `HF_CACHE` correct, full cache on both nodes

## E. Serving config (default profile) — see table in VI section

## F. Ops (required)
- [ ] **STOP earlyoom on both hosts**: `systemctl stop earlyoom && systemctl disable earlyoom`
- [ ] Hotfix #55/#26/#21/#27/#43 always run; #22 separate
- [ ] #79 spin-wait P-core: hotfix ON by default (opt-out `DSPARK_SKIP_SPIN_WAIT_HOTFIX=1`)
- [ ] #52 assistant-final: opt-in `DSPARK_ENABLE_ASSISTANT_FINAL_HOTFIX=1` for agent harness
- [ ] #72 after reboot: systemd `SuccessExitStatus=3`
- [ ] #81 RULER-lite: bulk-pads correct 32k/262k
- [ ] `VLLM_DSPARK_*` no-ops on Anemll 0.1.1 (Stage-C image only)

## G. Start & verify
- [ ] Worker node starts FIRST, head node second
- [ ] `curl :8888/v1/models` → `max_model_len: 1048576`
- [ ] `./scripts/smoke-test.sh` PASS (1M ctx + stream + non-stream)
- [ ] `./scripts/status-deepseek-v4-flash-dspark.sh` OK on both nodes

## H. Customer handoff (SLA/ops)
- [ ] Quick-start doc + `.env.dspark.example` explained to customer
- [ ] `./scripts/start|stop|status|smoke-test` usage documented
- [ ] Hotfix list & earlyoom warning in customer docs
- [ ] Customer signs receipt + confirms ops understanding
