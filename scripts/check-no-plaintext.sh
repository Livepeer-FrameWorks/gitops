#!/usr/bin/env bash
# Pre-commit hook: reject unencrypted secrets and host files.
# Checks staged files for SOPS encryption markers.
set -euo pipefail

failed=0

for file in "$@"; do
  if [[ ! -f "$file" ]]; then
    continue
  fi

  content=$(cat "$file")

  # .env files: SOPS dotenv format uses "sops_version=" metadata
  if [[ "$file" == *.env ]]; then
    if ! echo "$content" | grep -q "sops_version="; then
      echo "ERROR: $file is not SOPS-encrypted (missing sops_version= marker)"
      failed=1
    fi
  fi

  # .enc.yaml files: SOPS YAML format uses "sops:" metadata key
  if [[ "$file" == *.enc.yaml ]]; then
    if ! echo "$content" | grep -q "^sops:"; then
      echo "ERROR: $file is not SOPS-encrypted (missing sops: metadata)"
      failed=1
    fi
  fi
done

exit $failed
