#!/usr/bin/env bash
# Verifies image generation pipeline end-to-end.
# Runs three tiers of checks:
#   1. Unit tests (always)
#   2. Mock provider round-trip (always, no API keys needed)
#   3. Real provider smoke test (only if API keys are present)
#
# Usage:
#   bin/verify-image-gen.sh                  # tiers 1+2 only
#   bin/verify-image-gen.sh --live           # tiers 1+2+3 (needs API keys)

set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env ]; then
  set -a; source .env; set +a
fi

LIVE=false
if [[ "${1:-}" == "--live" ]]; then
  LIVE=true
fi

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# ── Tier 1: unit tests ────────────────────────────────────────────────────────

echo ""
echo "=== Tier 1: Unit tests ==="

if mix test test/slidething/image/ --no-start 2>&1 | tail -5; then
  pass "image unit tests"
else
  fail "image unit tests"
fi

# ── Tier 2: mock round-trip via Mix eval ──────────────────────────────────────

echo ""
echo "=== Tier 2: Mock provider round-trip ==="

MOCK_RESULT=$(mix run --no-start --no-compile - 2>&1 <<'ELIXIR'
Application.ensure_all_started(:slidething)

# 1. snap_aspect covers all 5 standard ratios
tests = [
  {1.0,       "1:1"},
  {16/9,      "16:9"},
  {9/16,      "9:16"},
  {4/3,       "4:3"},
  {3/4,       "3:4"},
]
Enum.each(tests, fn {ratio, expected} ->
  got = Slidething.Image.Provider.snap_aspect(ratio)
  if got == expected do
    IO.puts("snap_aspect(#{ratio}) => #{got} OK")
  else
    IO.puts("MISMATCH snap_aspect(#{ratio}) expected=#{expected} got=#{got}")
  end
end)

# 2. mock provider writes a valid PNG
{:ok, path} = Slidething.Image.Provider.Mock.generate("mock-model", "test prompt", "16:9")
full = Slidething.AssetStore.full_path(path)
bytes = File.read!(full)
<<137, 80, 78, 71, _rest::binary>> = bytes
IO.puts("mock_provider => #{path} (#{byte_size(bytes)} bytes, valid PNG signature) OK")

# 3. Tool.Registry.execute dispatches correctly
result = Slidething.Tool.Registry.execute(:generate_image, %{"prompt" => "a dog", "aspect_ratio" => "16:9"})
if result.success do
  IO.puts("registry.generate_image => asset_path=#{result.data.asset_path} OK")
else
  IO.puts("FAIL registry.generate_image error=#{result.error}")
end
ELIXIR
)

echo "$MOCK_RESULT"

if echo "$MOCK_RESULT" | grep -q "MISMATCH\|FAIL"; then
  fail "mock round-trip"
else
  pass "mock round-trip"
fi

# ── Tier 3: live provider smoke test ─────────────────────────────────────────

if [ "$LIVE" = false ]; then
  echo ""
  echo "=== Tier 3: Live provider tests SKIPPED (run with --live to enable) ==="
else
  echo ""
  echo "=== Tier 3: Live provider smoke tests ==="

  # Gemini
  if [ -n "${GOOGLE_API_KEY:-}" ]; then
    echo "  Testing Gemini..."
    GEMINI_RESULT=$(mix run --no-start - 2>&1 <<'ELIXIR'
Application.ensure_all_started(:slidething)
case Slidething.Image.Provider.Gemini.generate("imagen-3.0-generate-002", "a simple red circle on white background", "1:1") do
  {:ok, path} ->
    size = Slidething.AssetStore.full_path(path) |> File.read!() |> byte_size()
    IO.puts("gemini OK => #{path} (#{size} bytes)")
  {:error, reason} ->
    IO.puts("gemini FAIL => #{inspect(reason)}")
end
ELIXIR
    )
    echo "$GEMINI_RESULT"
    if echo "$GEMINI_RESULT" | grep -q "gemini OK"; then
      pass "gemini live"
    else
      fail "gemini live"
    fi
  else
    echo "  Gemini SKIPPED (GOOGLE_API_KEY not set)"
  fi

  # OpenRouter
  if [ -n "${OPENROUTER_API_KEY:-}" ]; then
    echo "  Testing OpenRouter..."
    OR_RESULT=$(mix run --no-start - 2>&1 <<'ELIXIR'
Application.ensure_all_started(:slidething)
case Slidething.Image.Provider.OpenRouter.generate("black-forest-labs/flux-schnell", "a simple red circle on white background", "1:1") do
  {:ok, path} ->
    size = Slidething.AssetStore.full_path(path) |> File.read!() |> byte_size()
    IO.puts("openrouter OK => #{path} (#{size} bytes)")
  {:error, reason} ->
    IO.puts("openrouter FAIL => #{inspect(reason)}")
end
ELIXIR
    )
    echo "$OR_RESULT"
    if echo "$OR_RESULT" | grep -q "openrouter OK"; then
      pass "openrouter live"
    else
      fail "openrouter live"
    fi
  else
    echo "  OpenRouter SKIPPED (OPENROUTER_API_KEY not set)"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
