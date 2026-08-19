#!/usr/bin/env bash
# ============================================================
# smoke-test.sh — quick verify of a live DSpark 2x DGX Spark cluster
# 1. /v1/models up + max_model_len == 1M
# 2. streaming chat completion returns tokens
# 3. (optional) deep-context sanity
# ============================================================
set -euo pipefail
API="${API:-http://127.0.0.1:8888}"
MODEL="${MODEL:-deepseek-ai/DeepSeek-V4-Flash-0731}"

echo "=== [1] /v1/models ==="
curl -sf --max-time 10 "$API/v1/models" | python3 -c '
import sys, json
d = json.load(sys.stdin)
ids = [m["id"] for m in d.get("data", [])]
mlen = d["data"][0].get("max_model_len") if d.get("data") else None
print("models:", ids)
print("max_model_len:", mlen)
assert mlen == 1048576, f"expected 1048576, got {mlen}"
print("OK: 1M context confirmed")
' || { echo "SMOKE FAIL: /v1/models"; exit 1; }

echo "=== [2] streaming chat (thinking on) ==="
OUT=$(curl -sfN --max-time 60 "$API/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL\",\"stream\":true,\"messages\":[{\"role\":\"user\",\"content\":\"what is a hash map? answer in one short sentence\"}]}")
if echo "$OUT" | grep -q 'data:'; then
  echo "OK: streamed chunks received"
else
  echo "SMOKE FAIL: no streamed data"
  exit 1
fi

echo "=== [3] non-stream completion ==="
curl -sf --max-time 60 "$API/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL\",\"max_tokens\":32,\"messages\":[{\"role\":\"user\",\"content\":\"say OK\"}]}" \
  | python3 -c 'import sys,json; print("  content:", json.load(sys.stdin)["choices"][0]["message"]["content"][:40])' \
  || { echo "SMOKE FAIL: completion"; exit 1; }

echo "=== SMOKE TEST PASS ==="
