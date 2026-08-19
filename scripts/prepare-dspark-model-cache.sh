#!/usr/bin/env bash
# ============================================================
# prepare-dspark-model-cache.sh — fetch + verify the official
# DeepSeek V4 Flash 0731 checkpoint on a DGX Spark (GB10) host.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=/dev/null
[ -f "$ROOT_DIR/.env.dspark" ] && . "$ROOT_DIR/.env.dspark"

HF_MODEL="${HF_MODEL:-deepseek-ai/DeepSeek-V4-Flash-0731}"
HF_CACHE="${HF_CACHE:-/root/.cache/huggingface}"
CHECKPOINT_COMMIT="${CHECKPOINT_COMMIT:-9e165c30}"

usage() { echo "Usage: $0 [--official|--local /path/to/model]"; exit 1; }
MODE="${1:---official}"

case "$MODE" in
  --official)
    echo ">>> Downloading official checkpoint: $HF_MODEL @ $CHECKPOINT_COMMIT"
    echo ">>> (uses ONLY official deepseek-ai weights — NOT MiaAI-Lab HF models)"
    huggingface-cli download "$HF_MODEL" --revision "$CHECKPOINT_COMMIT" \
      --local-dir "$HF_CACHE/$HF_MODEL" || {
        echo "huggingface-cli failed, retrying via HF_HOME direct:" >&2
        HF_HOME="$HF_CACHE" python -m huggingface_hub.snapshot_download \
          repo_id="$HF_MODEL" revision="$CHECKPOINT_COMMIT"
      }
    echo ">>> Cached to: $HF_CACHE/$HF_MODEL"
    ;;
  --local)
    [ -n "${2:-}" ] || usage
    echo ">>> Using local model dir: $2 (skip download)"
    ;;
  *) usage ;;
esac

echo ">>> Done. Set HF_CACHE=$HF_CACHE in .env.dspark on BOTH hosts."
