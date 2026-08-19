#!/usr/bin/env bash
# ============================================================
# status-deepseek-v4-flash-dspark.sh — cluster + container status
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
[ -f "$ROOT_DIR/.env.dspark" ] && . "$ROOT_DIR/.env.dspark"

NAME="${DSPARK_CONTAINER_NAME:-dspark-vllm}"
echo "=== hostname: $HOSTNAME ==="
echo "--- container ---"
docker ps --filter "name=$NAME" --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' || true

echo "--- GPU ---"
nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv 2>/dev/null || echo "nvidia-smi unavailable"

echo "--- RoCE / NCCL IB ---"
ibstat 2>/dev/null | grep -E 'State|Rate' | head -4 || echo "ibstat unavailable"

echo "--- serving check (:8888) ---"
if command -v curl >/dev/null && curl -sf --max-time 5 :8888/v1/models >/dev/null 2>&1; then
  echo "vLLM API :8888  -> OK"
  curl -sf --max-time 5 :8888/v1/models | python3 -c 'import sys,json; d=json.load(sys.stdin); print("  models:", [m["id"] for m in d.get("data",[])]); print("  max_model_len:", d["data"][0].get("max_model_len") if d.get("data") else "n/a")' 2>/dev/null || echo "  (models endpoint up, parse skipped)"
else
  echo "vLLM API :8888  -> DOWN"
fi
