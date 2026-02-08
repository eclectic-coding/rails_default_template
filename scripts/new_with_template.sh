#!/usr/bin/env bash
# Helper script to create a new Rails app using this template while preventing
# Rails' core JS installers (importmap) from running before the template.
#
# Usage:
#   ./scripts/new_with_template.sh APP_NAME [other rails new args]
#
# By default this script will add --skip-javascript unless you set
# RAILS_TEMPLATE_NO_SKIP_JS=1 or explicitly pass --javascript or --skip-javascript.

set -euo pipefail

# Resolve repo root (script lives under scripts/)
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE_PATH="$REPO_ROOT/template.rb"

if [ ! -f "$TEMPLATE_PATH" ]; then
  echo "ERROR: template.rb not found at $TEMPLATE_PATH" >&2
  exit 1
fi

# Collect args
ARGS=("$@")

# If user sets this env var, do not auto-add --skip-javascript
if [ -z "${RAILS_TEMPLATE_NO_SKIP_JS:-}" ]; then
  add_skip_js=true
  for a in "${ARGS[@]:-}"; do
    if [[ "$a" == --javascript* || "$a" == --skip-javascript ]]; then
      add_skip_js=false
      break
    fi
  done
  if $add_skip_js; then
    ARGS+=("--skip-javascript")
  fi
fi

# Run rails new with the template
# If no app name provided, rails will error as usual
exec rails new "${ARGS[@]}" -m "$TEMPLATE_PATH"

