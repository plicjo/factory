#!/usr/bin/env bash
# Single chokepoint for the opt-in Grok review seat. Refuses to run unless
# FACTORY_GROK_SEAT=1 so environments that must not send code to non-Anthropic
# vendors never reach the CLI, and pins the read-only flags in one place.
# Exit codes: 2 seat not enabled, 3 grok CLI missing, 4 brief unreadable.
set -euo pipefail

brief="${1:-}"

if [[ "${FACTORY_GROK_SEAT:-}" != "1" ]]; then
  echo "grok-review: seat disabled, set FACTORY_GROK_SEAT=1 to enable" >&2
  exit 2
fi

if ! command -v grok >/dev/null 2>&1; then
  echo "grok-review: grok CLI not found on PATH" >&2
  exit 3
fi

if [[ -z "$brief" || ! -r "$brief" || ! -f "$brief" ]]; then
  echo "grok-review: brief file missing or unreadable: ${brief:-<none>}" >&2
  exit 4
fi

exec grok \
  -m "${FACTORY_GROK_MODEL:-grok-4.7}" \
  --prompt-file "$brief" \
  --output-format plain \
  --deny 'Write' --deny 'Edit' \
  --no-subagents \
  --max-turns "${FACTORY_GROK_MAX_TURNS:-15}" \
  --permission-mode dontAsk \
  --disable-web-search
