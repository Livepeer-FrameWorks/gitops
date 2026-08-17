#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
checker="$repo_root/scripts/check-no-ip-leak.py"
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT

passed=0

expect_pass() {
  local name=$1
  local file=$2
  if ! "$checker" "$file"; then
    echo "FAIL: expected $name to pass" >&2
    exit 1
  fi
  passed=$((passed + 1))
}

expect_fail() {
  local name=$1
  local file=$2
  if "$checker" "$file" 2>/dev/null; then
    echo "FAIL: expected $name to fail" >&2
    exit 1
  fi
  passed=$((passed + 1))
}

write_fixture() {
  local name=$1
  local content=$2
  printf '%s\n' "$content" >"$fixture_dir/$name.yaml"
}

expect_pass "the production manifest" "$repo_root/clusters/production/cluster.yaml"

write_fixture outside 'hosts:
  first:
    wireguard_ip: 10.89.0.2
wireguard:
  mesh_cidr: 10.88.0.0/16'
expect_fail "a WireGuard IP outside mesh_cidr" "$fixture_dir/outside.yaml"

write_fixture duplicate 'hosts:
  first:
    wireguard_ip: 10.88.0.2
  second:
    wireguard_ip: 10.88.0.2
wireguard:
  mesh_cidr: 10.88.0.0/16'
expect_fail "duplicate WireGuard IPs" "$fixture_dir/duplicate.yaml"

write_fixture external_ip 'hosts:
  first:
    external_ip: 10.88.0.2
wireguard:
  mesh_cidr: 10.88.0.0/16'
expect_fail "external_ip in the mesh range" "$fixture_dir/external_ip.yaml"

write_fixture service_url 'service:
  url: http://10.88.0.2:8080'
expect_fail "an IP embedded in a URL" "$fixture_dir/service_url.yaml"

write_fixture public_cidr 'wireguard:
  mesh_cidr: 8.8.8.0/24'
expect_fail "a public mesh CIDR" "$fixture_dir/public_cidr.yaml"

write_fixture malformed_cidr 'wireguard:
  mesh_cidr: 10.88.0.1/16'
expect_fail "a malformed mesh CIDR" "$fixture_dir/malformed_cidr.yaml"

write_fixture documentation 'examples:
  first: 192.0.2.10
  second: http://198.51.100.20:8080
  third: 203.0.113.30
  loopback: 127.0.0.1
  unspecified: 0.0.0.0'
expect_pass "documentation, loopback, and unspecified addresses" "$fixture_dir/documentation.yaml"

write_fixture comment 'hosts:
  first:
    wireguard_ip: 10.88.0.2 # reachable at 10.88.0.3
wireguard:
  mesh_cidr: 10.88.0.0/16'
expect_fail "an unexpected IP in a comment" "$fixture_dir/comment.yaml"

write_fixture wrong_path 'services:
  first:
    wireguard_ip: 10.88.0.2
wireguard:
  mesh_cidr: 10.88.0.0/16'
expect_fail "a WireGuard IP outside hosts.<host>" "$fixture_dir/wrong_path.yaml"

write_fixture arbitrary_field 'version: 10.88.0.2'
expect_fail "an IP in an arbitrary field" "$fixture_dir/arbitrary_field.yaml"

write_fixture ipv6_field 'hosts:
  first:
    external_ip: 2606:4700:4700::1111'
expect_fail "an IPv6 host-reachability field" "$fixture_dir/ipv6_field.yaml"

write_fixture ipv6_url 'service:
  url: https://[2606:4700:4700::1111]:8443/status'
expect_fail "an IPv6 address embedded in a URL" "$fixture_dir/ipv6_url.yaml"

write_fixture ipv6_comment 'service:
  enabled: true # reachable at 2606:4700:4700::1111.'
expect_fail "an unexpected IPv6 address in a comment" "$fixture_dir/ipv6_comment.yaml"

write_fixture ipv6_ula 'hosts:
  first:
    internal_ip: fd00::2'
expect_fail "an IPv6 unique-local host address" "$fixture_dir/ipv6_ula.yaml"

write_fixture ipv6_allowances 'examples:
  unspecified: "::"
  loopback: "::1"
  documentation: 2001:db8::1234
  documentation_url: https://[2001:db8::5678]:8443/status'
expect_pass "IPv6 unspecified, loopback, and documentation addresses" "$fixture_dir/ipv6_allowances.yaml"

echo "PASS: $passed no-IP-leak checks"
