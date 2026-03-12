#!/usr/bin/env bash
# Pre-commit hook: reject age private keys from being committed.
set -euo pipefail

failed=0

for file in "$@"; do
  if [[ ! -f "$file" ]]; then
    continue
  fi

  if grep -q "AGE-SECRET-KEY-" "$file" 2>/dev/null; then
    echo "ERROR: $file contains an age private key — never commit private keys"
    failed=1
  fi
done

exit $failed
