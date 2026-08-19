#!/usr/bin/env bash
# ============================================================
# start-deepseek-v4-flash-dspark.sh
# Launch DeepSeek V4 Flash 0731 (DSpark, TP=2, 1M ctx) on a
# DGX Spark node. Run on the WORKER node FIRST, then HEAD.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
[ -f "$ROOT_DIR/.env.dspark" ] || { echo "Missing .env.dspark (cp .env.dspark.example .env.dspark)"; exit 1; }
# shellcheck source=/dev/null
. "$ROOT_DIR/.env.dspark"

# ---- earlyoom guard (critical) ----
if systemctl is-active --quiet earlyoom 2>/dev/null; then
  echo "!! earlyoom is ACTIVE. It will kill vLLM under deep-context load."
  echo "!! Run: systemctl stop earlyoom && systemctl disable earlyoom  (on BOTH hosts)"
  echo "!! Aborting start to protect the cluster."
  exit 1
fi

# ---- env defaults ----
DSPARK_IMAGE="${DSPARK_IMAGE:-ghcr.io/anemll/dspark-vllm-gx10:0.1.1}"
HF_MODEL="${HF_MODEL:-deepseek-ai/DeepSeek-V4-Flash-0731}"
HF_CACHE="${HF_CACHE:-/root/.cache/huggingface}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-1048576}"
MAX_NUM_SEQS="${MAX_NUM_SEQS:-6}"
MAX_NUM_BATCHED_TOKENS="${MAX_NUM_BATCHED_TOKENS:-8192}"
MTP_NUM_TOKENS="${MTP_NUM_TOKENS:-5}"
DEFAULT_THINKING="${DEFAULT_THINKING:-max}"
VLLM_USE_BREAKABLE_CUDAGRAPH="${VLLM_USE_BREAKABLE_CUDAGRAPH:-0}"
MAX_CUDAGRAPH_CAPTURE_SIZE="${MAX_CUDAGRAPH_CAPTURE_SIZE:-36}"
DSPARK_SKIP_SPIN_WAIT_HOTFIX="${DSPARK_SKIP_SPIN_WAIT_HOTFIX:-}"
DSPARK_ENABLE_ASSISTANT_FINAL_HOTFIX="${DSPARK_ENABLE_ASSISTANT_FINAL_HOTFIX:-}"

for var in WORKER_HOST MASTER_ADDR NCCL_IB_HCA NCCL_SOCKET_IFNAME VLLM_HOST_IP; do
  [ -n "${!var:-}" ] || { echo "Missing required env: $var"; exit 1; }
done

echo ">>> docker pull $DSPARK_IMAGE"
docker pull "$DSPARK_IMAGE"

echo ">>> Starting DSpark vLLM (TP=2) on $HOSTNAME (host_ip=$VLLM_HOST_IP)"
docker run -d --name dspark-vllm \
  --gpus all \
  --ipc=host \
  --network=host \
  --restart=unless-stopped \
  -e WORKER_HOST="$WORKER_HOST" \
  -e MASTER_ADDR="$MASTER_ADDR" \
  -e NCCL_IB_HCA="$NCCL_IB_HCA" \
  -e NCCL_SOCKET_IFNAME="$NCCL_SOCKET_IFNAME" \
  -e VLLM_HOST_IP="$VLLM_HOST_IP" \
  -e HF_CACHE="$HF_CACHE" \
  -e MAX_MODEL_LEN="$MAX_MODEL_LEN" \
  -e MAX_NUM_SEQS="$MAX_NUM_SEQS" \
  -e MAX_NUM_BATCHED_TOKENS="$MAX_NUM_BATCHED_TOKENS" \
  -e MTP_NUM_TOKENS="$MTP_NUM_TOKENS" \
  -e DEFAULT_THINKING="$DEFAULT_THINKING" \
  -e VLLM_USE_BREAKABLE_CUDAGRAPH="$VLLM_USE_BREAKABLE_CUDAGRAPH" \
  -e VLLM_DSPARK_MAX_CUDAGRAPH_CAPTURE_SIZE="$MAX_CUDAGRAPH_CAPTURE_SIZE" \
  ${DSPARK_SKIP_SPIN_WAIT_HOTFIX:+-e DSPARK_SKIP_SPIN_WAIT_HOTFIX=$DSPARK_SKIP_SPIN_WAIT_HOTFIX} \
  ${DSPARK_ENABLE_ASSISTANT_FINAL_HOTFIX:+-e DSPARK_ENABLE_ASSISTANT_FINAL_HOTFIX=$DSPARK_ENABLE_ASSISTANT_FINAL_HOTFIX} \
  -v "$HF_CACHE:$HF_CACHE" \
  "$DSPARK_IMAGE"

echo ">>> Container started. Head node serves OpenAI API on :8888"
echo ">>> Verify: curl :8888/v1/models  -> max_model_len 1048576"
