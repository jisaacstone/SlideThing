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

PROMPT="${1:-}"
MODEL="${2:-}"

if [ -z "$PROMPT" ]; then
  echo "Usage: bin/generate-openrouter.sh \"Your book prompt\" [model]"
  echo "  Uses agents-openrouter.json (gpt-4o-mini) for agent settings"
  echo "  Optional model override for all agents (e.g. openai/gpt-4o-mini)"
  exit 1
fi

echo "Agent config: agents-openrouter.json"

if [ -n "$MODEL" ]; then
  echo "Model override: $MODEL"
  exec env SLIDETHING_AGENT_CONFIG=agents-openrouter.json \
    mix slidething.generate "$PROMPT" --model "$MODEL"
else
  exec env SLIDETHING_AGENT_CONFIG=agents-openrouter.json \
    mix slidething.generate "$PROMPT"
fi