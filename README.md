# 5ac AI Lab — Recipe 2× DGX Spark (GB10) cho DeepSeek V4 Flash 0731

> Recipe vận hành đã xác minh để chạy **DeepSeek V4 Flash 0731** với **1M-token context** trên **2× DGX Spark / ASUS Ascent GX10** (NVIDIA GB10, 128GB unified RAM), vLLM TP=2 + DSpark speculative decoding.
>
> Vietnamese first, English below. — [5ac AI Lab](https://5ac.vn)

---

## Mục đích

Cụm **2× DGX Spark (GB10)** + cáp **QSFP56 RoCE 200G** là mức phần cứng tối thiểu để chạy DeepSeek V4 Flash 0731 **FP8 chính thức (~149GB)** ở **1M context thật** — điều mà một chiếc Mac 128GB không làm được (crash) và RTX PRO chỉ giới hạn 131K.

Repo này là **serving config + runbook ops** cho chính cụm lab nội bộ của 5ac (dogfood), đồng thời là **checklist bàn giao khách** khi bán cụm on-prem cho SMB Việt Nam (Local AI Engine).

## ⚠️ Nguồn gốc & tuân thủ

- **Nguồn recipe gốc:** [MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark](https://github.com/MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark) (777★) — chúng tôi **chỉ dùng serving config + image** từ repo này.
- **Image:** `ghcr.io/anemll/dspark-vllm-gx10:0.1.1` (từ [Anemll/dspark-vllm-gx10](https://github.com/Anemll/dspark-vllm-gx10)).
- **KHÔNG dùng models Hugging Face của MiaAI-Lab** (`Qwable`/`Gemmable`) — chúng bị cộng đồng tố nghi là **base model quantized rồi dequantized** (không phải fine-tune thật). Chúng tôi chỉ dùng **official checkpoints** (`deepseek-ai/DeepSeek-V4-Flash-0731`).
- Credits: drowzeys (DSpark concurrency patch), u1tra_instinct (abliterated weights), Anemll (image).

## Cấu hình chuẩn (default profile)

| Knob | Giá trị |
|---|---|
| Image | `ghcr.io/anemll/dspark-vllm-gx10:0.1.1` |
| Checkpoint | official 0731 @ `9e165c30` (ABLITERATED=0) |
| Context | `MAX_MODEL_LEN=1048576` (1M) |
| Concurrent | `MAX_NUM_SEQS=6` · `MAX_NUM_BATCHED_TOKENS=8192` |
| KV cache | `nvfp4_ds_mla`, text util **0.835** (~2.49M tokens) |
| Spec decode | `MTP_NUM_TOKENS=5` (≥ dspark_block_size) |
| Thinking | `DEFAULT_THINKING=max` · `VLLM_USE_BREAKABLE_CUDAGRAPH=0` |
| `--max-cudagraph-capture-size` | `MAX_NUM_SEQS × (MTP_NUM_TOKENS+1)` = **36** (6×6) |

### Tốc độ kỳ vọng (default Anemll 1M/6)

- 1 chat ≤128K: **~62-83 tok/s** decode sau first token
- 6 short chats: **~160-190 tok/s aggregate** (~30-37/stream)
- 6 cold 32K-128K prompts: prefill **queue** (issue #27), ~8 tok/s floor

## Bắt đầu nhanh

```bash
# 1. Clone + copy env
git clone https://github.com/moken627-hub/dgx-spark-recipe.git
cd dgx-spark-recipe
cp .env.dspark.example .env.dspark
# → sửa WORKER_HOST / MASTER_ADDR / NCCL_IB_HCA / NCCL_SOCKET_IFNAME / VLLM_HOST_IP / HF_CACHE

# 2. Trên CẢ 2 node: pull image + chuẩn bị model cache
docker pull ghcr.io/anemll/dspark-vllm-gx10:0.1.1
./scripts/prepare-dspark-model-cache.sh --official   # downlaod official 0731 checkpoint

# 3. TẮT earlyoom trên cả 2 host (nếu đang bật)
systemctl stop earlyoom && systemctl disable earlyoom

# 4. Worker trước, head sau
./scripts/start-deepseek-v4-flash-dspark.sh   # chạy trên worker node trước
./scripts/start-deepseek-v4-flash-dspark.sh   # sau đó trên head node

# 5. Verify
curl :8888/v1/models   # → "max_model_len": 1048576
./scripts/smoke-test.sh
```

## ⚠️ Lưu ý vận hành

- **TẮT earlyoom trên cả 2 host** — nếu không, nó giết vLLM dưới deep-context load.
- Hotfix **#55 / #26 / #21 / #27 / #43** luôn chạy (không bị bỏ qua qua `DSPARK_SKIP_HOTFIX`); **#22** riêng biệt.
- **#79 spin-wait P-core:** opt-out `DSPARK_SKIP_SPIN_WAIT_HOTFIX=1`.
- **#52 assistant-final:** **opt-in** `DSPARK_ENABLE_ASSISTANT_FINAL_HOTFIX=1` (mặc định 0 = stock; fail-closed, idempotent) — bắt buộc cho agent harness để tránh no-op turns.
- **#72 sau reboot:** container up → `exit 3` (không phải 1) → systemd `SuccessExitStatus=3`.
- **#81 RULER-lite:** bulk-pad đúng 32k/262k cells.
- `VLLM_DSPARK_*` là **no-op** trên Anemll 0.1.1 (chỉ có hiệu lực khi đổi sang image Stage-C).
- Option VL sidecar: `ENABLE_VL_SIDECAR=1` → Qwen3-VL :8889 + MCP.
- Responses API live verifier: `verify-responses-api-live.py` (4 gates); stateful continuation cần `VLLM_ENABLE_RESPONSES_API_STORE=1`.

## Cấu trúc repo

```
dgx-spark-recipe/
├── README.md
├── LICENSE                      (MIT)
├── .env.dspark.example
├── scripts/
│   ├── prepare-dspark-model-cache.sh
│   ├── start-deepseek-v4-flash-dspark.sh
│   ├── stop-deepseek-v4-flash-dspark.sh
│   ├── status-deepseek-v4-flash-dspark.sh
│   └── smoke-test.sh
└── docs/
    ├── customer-handoff-checklist.md   (VI + EN)
    └── dogfood-runbook.md              (runbook nội bộ — deploy 2× Spark)
```

## Liên hệ / Nguồn

- [5ac AI Lab](https://5ac.vn) — AI lab open-source Việt Nam
- Research note đầy đủ: `/root/5ac/research/model-serving/miaai-lab-dgx-spark-research-2026-08-19.md`
- Repo gốc: [MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark](https://github.com/MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark)

---

# 5ac AI Lab — 2× DGX Spark (GB10) Recipe for DeepSeek V4 Flash 0731

> Verified ops recipe to run **DeepSeek V4 Flash 0731** at **1M-token context** on **2× DGX Spark / ASUS Ascent GX10** (NVIDIA GB10, 128GB unified RAM), vLLM TP=2 + DSpark speculative decoding.

## Purpose

A **2× DGX Spark (GB10)** cluster + **QSFP56 RoCE 200G** cable is the minimum hardware that runs official **FP8 DeepSeek V4 Flash 0731 (~149GB)** at **real 1M context** — something a 128GB Mac cannot (crashes) and RTX PRO caps at 131K.

This repo is the **serving config + ops runbook** for 5ac's own dogfood lab, and doubles as the **customer handoff checklist** for selling on-prem clusters to Vietnamese SMBs (Local AI Engine).

## ⚠️ Attribution & compliance

- **Source recipe:** [MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark](https://github.com/MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark) (777★) — we use **only serving config + image**.
- **Image:** `ghcr.io/anemll/dspark-vllm-gx10:0.1.1` (from [Anemll/dspark-vllm-gx10](https://github.com/Anemll/dspark-vllm-gx10)).
- **We do NOT use MiaAI-Lab HF models** (`Qwable`/`Gemmable`) — community-flagged as likely **quantized-then-dequantized base models** (not real fine-tunes). We use only **official checkpoints** (`deepseek-ai/DeepSeek-V4-Flash-0731`).
- Credits: drowzeys (DSpark concurrency patch), u1tra_instinct (abliterated weights), Anemll (image).

## Default profile

| Knob | Value |
|---|---|
| Image | `ghcr.io/anemll/dspark-vllm-gx10:0.1.1` |
| Checkpoint | official 0731 @ `9e165c30` (ABLITERATED=0) |
| Context | `MAX_MODEL_LEN=1048576` (1M) |
| Concurrent | `MAX_NUM_SEQS=6` · `MAX_NUM_BATCHED_TOKENS=8192` |
| KV cache | `nvfp4_ds_mla`, text util **0.835** (~2.49M tokens) |
| Spec decode | `MTP_NUM_TOKENS=5` (≥ dspark_block_size) |
| Thinking | `DEFAULT_THINKING=max` · `VLLM_USE_BREAKABLE_CUDAGRAPH=0` |
| `--max-cudagraph-capture-size` | `MAX_NUM_SEQS × (MTP_NUM_TOKENS+1)` = **36** (6×6) |

### Expected throughput (default Anemll 1M/6)

- 1 chat ≤128K: **~62-83 tok/s** decode after first token
- 6 short chats: **~160-190 tok/s aggregate** (~30-37/stream)
- 6 cold 32K-128K prompts: prefill **queues** (issue #27), ~8 tok/s floor

## Quick start

```bash
git clone https://github.com/moken627-hub/dgx-spark-recipe.git
cd dgx-spark-recipe
cp .env.dspark.example .env.dspark   # edit WORKER_HOST/MASTER_ADDR/NCCL_IB_HCA/NCCL_SOCKET_IFNAME/VLLM_HOST_IP/HF_CACHE

# On BOTH nodes
docker pull ghcr.io/anemll/dspark-vllm-gx10:0.1.1
./scripts/prepare-dspark-model-cache.sh --official

# STOP earlyoom on both hosts if enabled
systemctl stop earlyoom && systemctl disable earlyoom

# Worker first, head second
./scripts/start-deepseek-v4-flash-dspark.sh
./scripts/start-deepseek-v4-flash-dspark.sh   # on head node

curl :8888/v1/models   # → "max_model_len": 1048576
./scripts/smoke-test.sh
```

## ⚠️ Ops notes

- **STOP earlyoom on both hosts** — otherwise it kills vLLM under deep-context load.
- Hotfix **#55/#26/#21/#27/#43** always run (ignored `DSPARK_SKIP_HOTFIX`); **#22** separate.
- **#79 spin-wait P-core:** opt-out `DSPARK_SKIP_SPIN_WAIT_HOTFIX=1`.
- **#52 assistant-final:** **opt-in** `DSPARK_ENABLE_ASSISTANT_FINAL_HOTFIX=1` (default 0 = stock; fail-closed, idempotent) — required for agent harness to avoid no-op turns.
- **#72 after reboot:** container up → `exit 3` (not 1) → systemd `SuccessExitStatus=3`.
- **#81 RULER-lite:** bulk-pads correct 32k/262k cells.
- `VLLM_DSPARK_*` are **no-ops** on Anemll 0.1.1 (only take effect on Stage-C image).
- Optional VL sidecar: `ENABLE_VL_SIDECAR=1` → Qwen3-VL :8889 + MCP.
- Responses API live verifier: `verify-responses-api-live.py` (4 gates); stateful continuation needs `VLLM_ENABLE_RESPONSES_API_STORE=1`.

## Repo layout

```
dgx-spark-recipe/
├── README.md
├── LICENSE                      (MIT)
├── .env.dspark.example
├── scripts/
│   ├── prepare-dspark-model-cache.sh
│   ├── start-deepseek-v4-flash-dspark.sh
│   ├── stop-deepseek-v4-flash-dspark.sh
│   ├── status-deepseek-v4-flash-dspark.sh
│   └── smoke-test.sh
└── docs/
    ├── customer-handoff-checklist.md   (VI + EN)
    └── dogfood-runbook.md              (internal runbook — 2× Spark deploy)
```

## Contact / Sources

- [5ac AI Lab](https://5ac.vn) — Vietnam open-source AI lab
- Source repo: [MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark](https://github.com/MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark)
