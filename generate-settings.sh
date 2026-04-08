#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# 1. Resolve paths
# ──────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
OUTPUT_FILE="$SCRIPT_DIR/settings.json"

# ──────────────────────────────────────────────
# 2. Read SYMLINK_NAME from .env
# ──────────────────────────────────────────────
parse_env_var() { grep -m1 "^$2=" "$1" 2>/dev/null | cut -d= -f2- | tr -d "\"'"; }

SYMLINK_NAME="$(parse_env_var "$ENV_FILE" SYMLINK_NAME)"
[[ -z "$SYMLINK_NAME" ]] && { echo "ERROR: SYMLINK_NAME is not set in .env" >&2; exit 1; }

# ──────────────────────────────────────────────
# 3. Validate dependencies
# ──────────────────────────────────────────────
if ! command -v gitleaks &>/dev/null; then
  echo "ERROR: gitleaks is not installed. Install it with: brew install gitleaks" >&2
  exit 1
fi

# ──────────────────────────────────────────────
# 4. Resolve symlink → real file path
# ──────────────────────────────────────────────
SYMLINK_PATH="$SCRIPT_DIR/$SYMLINK_NAME"

if [[ ! -L "$SYMLINK_PATH" ]]; then
  echo "ERROR: Symlink not found at '$SYMLINK_PATH'" >&2
  exit 1
fi

REAL_SETTINGS="$(readlink "$SYMLINK_PATH")"

# readlink on macOS returns the raw target — make absolute if relative
if [[ "$REAL_SETTINGS" != /* ]]; then
  REAL_SETTINGS="$(cd "$(dirname "$SYMLINK_PATH")" && pwd)/$REAL_SETTINGS"
fi

if [[ ! -f "$REAL_SETTINGS" ]]; then
  echo "ERROR: Symlink target does not exist: '$REAL_SETTINGS'" >&2
  exit 1
fi

echo "Source file: $REAL_SETTINGS"

# ──────────────────────────────────────────────
# 5. Set up temp directory (cleaned up on exit)
# ──────────────────────────────────────────────
TMPDIR_WORK="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_WORK"' EXIT

TEMP_SETTINGS="$TMPDIR_WORK/settings.json"
REPORT_FILE="$TMPDIR_WORK/gitleaks-report.json"

cp "$REAL_SETTINGS" "$TEMP_SETTINGS"

# ──────────────────────────────────────────────
# 6. Run gitleaks
#    Exit 0 = no secrets, exit 1 = secrets found (both expected)
#    Exit ≥ 2 = gitleaks error → abort
# ──────────────────────────────────────────────
echo "Running gitleaks..."
gitleaks_exit=0
gitleaks detect \
  --no-git \
  --source "$TMPDIR_WORK" \
  --report-format json \
  --report-path "$REPORT_FILE" \
  2>/dev/null \
  || gitleaks_exit=$?

if [[ $gitleaks_exit -ge 2 ]]; then
  echo "ERROR: gitleaks encountered an unexpected error (exit code $gitleaks_exit)." >&2
  exit 1
fi

# ──────────────────────────────────────────────
# 7. Redact secrets with Python
#    str.replace() handles all special characters safely
# ──────────────────────────────────────────────
if [[ -f "$REPORT_FILE" && -s "$REPORT_FILE" ]]; then
  echo "Redacting secrets..."
  python3 - "$TEMP_SETTINGS" "$REPORT_FILE" "$OUTPUT_FILE" <<'PYEOF'
import json, sys

settings_path = sys.argv[1]
report_path   = sys.argv[2]
output_path   = sys.argv[3]

with open(settings_path, "r", encoding="utf-8") as f:
    content = f.read()

with open(report_path, "r", encoding="utf-8") as f:
    findings = json.load(f)

count = 0
for finding in findings:
    secret = finding.get("Secret", "")
    if secret and secret in content:
        content = content.replace(secret, "REDACTED")
        count += 1

print(f"  Redacted {count} secret(s).")

with open(output_path, "w", encoding="utf-8") as f:
    f.write(content)
PYEOF
else
  echo "No secrets found by gitleaks. Copying file as-is."
  cp "$TEMP_SETTINGS" "$OUTPUT_FILE"
fi

# ──────────────────────────────────────────────
# 8. Strip quotes surrounding REDACTED (e.g. "REDACTED" → REDACTED)
# ──────────────────────────────────────────────
sed -i '' 's/"REDACTED"/REDACTED/g' "$OUTPUT_FILE"

echo "Done. Redacted settings written to: $OUTPUT_FILE"
