#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage:
  sops-env.sh delete <encrypted-env-file> <KEY> [KEY...]
  sops-env.sh set <encrypted-env-file> <KEY> <VALUE>
  sops-env.sh insert-after <encrypted-env-file> <AFTER_KEY> <KEY> <VALUE>
  sops-env.sh insert-before <encrypted-env-file> <BEFORE_KEY> <KEY> <VALUE>
EOF
  exit 1
}

if [[ $# -lt 3 ]]; then
  usage
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

op="$1"
target="$2"
shift 2

cd "${repo_root}"

target_dir="$(dirname "${target}")"
target_base="$(basename "${target}")"
plain="${target_dir}/.${target_base}.tmp.plain.env"
enc="${target_dir}/.${target_base}.tmp.encrypted.env"

cleanup() {
  rm -f "${plain}" "${enc}"
}
trap cleanup EXIT

sops -d "${target}" > "${plain}"

case "${op}" in
  delete)
    if [[ $# -lt 1 ]]; then
      usage
    fi
    tmp="${plain}.next"
    cp "${plain}" "${tmp}"
    for key in "$@"; do
      awk -v key="${key}" '
        BEGIN { prefix = key "=" }
        index($0, prefix) != 1 { print }
      ' "${tmp}" > "${tmp}.filtered"
      mv "${tmp}.filtered" "${tmp}"
    done
    mv "${tmp}" "${plain}"
    ;;
  set)
    if [[ $# -ne 2 ]]; then
      usage
    fi
    key="$1"
    value="$2"
    awk -v key="${key}" -v value="${value}" '
      BEGIN { prefix = key "="; replaced = 0 }
      index($0, prefix) == 1 {
        if (!replaced) {
          print key "=" value
          replaced = 1
        }
        next
      }
      { print }
      END {
        if (!replaced) {
          print key "=" value
        }
      }
    ' "${plain}" > "${plain}.next"
    mv "${plain}.next" "${plain}"
    ;;
  insert-after|insert-before)
    if [[ $# -ne 3 ]]; then
      usage
    fi
    anchor_key="$1"
    key="$2"
    value="$3"
    awk -v op="${op}" -v anchor_key="${anchor_key}" -v key="${key}" -v value="${value}" '
      BEGIN {
        anchor_prefix = anchor_key "="
        key_prefix = key "="
        found_anchor = 0
      }
      index($0, key_prefix) == 1 { next }
      {
        if (op == "insert-before" && index($0, anchor_prefix) == 1) {
          print key "=" value
          found_anchor = 1
        }
        print
        if (op == "insert-after" && index($0, anchor_prefix) == 1) {
          print key "=" value
          found_anchor = 1
        }
      }
      END {
        if (!found_anchor) {
          exit 17
        }
      }
    ' "${plain}" > "${plain}.next" || {
      status=$?
      rm -f "${plain}.next"
      if [[ ${status} -eq 17 ]]; then
        echo "anchor key not found: ${anchor_key}" >&2
      fi
      exit ${status}
    }
    mv "${plain}.next" "${plain}"
    ;;
  *)
    usage
    ;;
esac

sops -e "${plain}" > "${enc}"
mv "${enc}" "${target}"
