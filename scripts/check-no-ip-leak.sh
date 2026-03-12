#!/usr/bin/env bash
# Pre-commit hook: reject real IP addresses in plaintext manifests.
# Allows RFC 5737 documentation ranges (192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24).
set -euo pipefail

failed=0

for file in "$@"; do
  if [[ ! -f "$file" ]]; then
    continue
  fi

  # Skip encrypted files
  if [[ "$file" == *.enc.* ]]; then
    continue
  fi

  # Find IP addresses, excluding version: lines and port numbers
  ips=$(grep -v '^\s*version:' "$file" | grep -oE '\b[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b' 2>/dev/null || true)

  for ip in $ips; do
    # Allow RFC 5737 documentation ranges
    if [[ "$ip" =~ ^192\.0\.2\. ]] || [[ "$ip" =~ ^198\.51\.100\. ]] || [[ "$ip" =~ ^203\.0\.113\. ]]; then
      continue
    fi
    # Allow loopback and link-local
    if [[ "$ip" =~ ^127\. ]] || [[ "$ip" =~ ^0\. ]]; then
      continue
    fi
    echo "ERROR: $file contains IP address $ip — IPs belong in the SOPS-encrypted hosts file"
    failed=1
  done
done

exit $failed
