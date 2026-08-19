#!/usr/bin/env bash
# ============================================================
# stop-deepseek-v4-flash-dspark.sh — stop the DSpark vLLM container
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
[ -f "$ROOT_DIR/.env.dspark" ] && . "$ROOT_DIR/.env.dspark"

NAME="${DSPARK_CONTAINER_NAME:-dspark-vllm}"
echo ">>> Stopping container: $NAME"
docker stop "$NAME" 2>/dev/null || echo "  (not running)"
docker rm "$NAME" 2>/dev/null || echo "  (no container to remove)"
echo ">>> Stopped. Note: #72 — after reboot, an already-up container exits 3,"
echo ">>> so systemd must use SuccessExitStatus=3 to avoid a retry storm."
