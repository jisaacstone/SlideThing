#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -f .env ]; then
  set -a; source .env; set +a
fi

if [ -z "${OPENROUTER_API_KEY:-}" ]; then
  echo "Error: OPENROUTER_API_KEY not set in .env"
  echo "  Get a key at https://openrouter.ai/keys"
  exit 1
fi

echo "Agent config: agents-openrouter.json"
echo "OpenRouter key: OK"
echo ""

exec env SLIDETHING_AGENT_CONFIG=agents-openrouter.json mix phx.server