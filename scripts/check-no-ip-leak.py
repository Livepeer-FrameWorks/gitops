#!/usr/bin/env python3
"""Reject real IP addresses outside the public WireGuard mesh schema."""

from __future__ import annotations

import ipaddress
import re
import sys
from dataclasses import dataclass
from pathlib import Path


IPV4_LITERAL = re.compile(r"(?<![0-9.])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9.])")
IPV6_CANDIDATE = re.compile(
    r"(?<![0-9A-Za-z:.])[0-9A-Fa-f:.]*:[0-9A-Fa-f:.]*(?![0-9A-Za-z:.])"
)
MAPPING = re.compile(
    r"^(?P<indent> *)(?P<key>[A-Za-z0-9_.-]+|'[^']*'|\"[^\"]*\")\s*:\s*(?P<value>.*)$"
)
RFC1918_NETWORKS = (
    ipaddress.IPv4Network("10.0.0.0/8"),
    ipaddress.IPv4Network("172.16.0.0/12"),
    ipaddress.IPv4Network("192.168.0.0/16"),
)
DOCUMENTATION_NETWORKS = (
    ipaddress.IPv4Network("192.0.2.0/24"),
    ipaddress.IPv4Network("198.51.100.0/24"),
    ipaddress.IPv4Network("203.0.113.0/24"),
)
IPV6_DOCUMENTATION_NETWORK = ipaddress.IPv6Network("2001:db8::/32")


@dataclass(frozen=True)
class MeshValue:
    line_number: int
    start: int
    end: int
    value: str


def scalar_value(raw: str) -> tuple[str, int, int] | None:
    """Return a simple YAML scalar and its offsets, ignoring an optional comment."""
    quote: str | None = None
    comment_at = len(raw)
    for index, character in enumerate(raw):
        if quote:
            if character == quote:
                quote = None
        elif character in ("'", '"'):
            quote = character
        elif character == "#":
            comment_at = index
            break

    token = raw[:comment_at]
    left_trimmed = token.lstrip()
    start = len(token) - len(left_trimmed)
    value = left_trimmed.rstrip()
    if not value:
        return None
    end = start + len(value)

    if value[0] in ("'", '"'):
        if len(value) < 2 or value[-1] != value[0]:
            return None
        start += 1
        end -= 1
        value = value[1:-1]
    return value, start, end


def is_globally_allowed(
    address: ipaddress.IPv4Address | ipaddress.IPv6Address,
) -> bool:
    if isinstance(address, ipaddress.IPv6Address):
        return (
            address.is_loopback
            or address.is_unspecified
            or address in IPV6_DOCUMENTATION_NETWORK
        )
    return address.is_loopback or address.is_unspecified or any(
        address in network for network in DOCUMENTATION_NETWORKS
    )


def ip_literals(
    line: str,
) -> list[tuple[int, int, ipaddress.IPv4Address | ipaddress.IPv6Address]]:
    """Return valid IP literals, preferring a whole IPv6 token over its IPv4 tail."""
    literals: list[
        tuple[int, int, ipaddress.IPv4Address | ipaddress.IPv6Address]
    ] = []
    ipv6_spans: list[tuple[int, int]] = []

    for match in IPV6_CANDIDATE.finditer(line):
        parsed = parse_ipv6_candidate(match.group())
        if not parsed:
            continue
        relative_start, relative_end, address = parsed
        start = match.start() + relative_start
        end = match.start() + relative_end
        literals.append((start, end, address))
        ipv6_spans.append((start, end))

    for match in IPV4_LITERAL.finditer(line):
        if any(start <= match.start() and match.end() <= end for start, end in ipv6_spans):
            continue
        try:
            address = ipaddress.IPv4Address(match.group())
        except ipaddress.AddressValueError:
            continue
        literals.append((match.start(), match.end(), address))

    return sorted(literals, key=lambda literal: literal[0])


def parse_ipv6_candidate(
    candidate: str,
) -> tuple[int, int, ipaddress.IPv6Address] | None:
    """Strip adjacent colon/dot punctuation and return the longest valid address."""
    starts = [0]
    while starts[-1] < len(candidate) and candidate[starts[-1]] in ".:":
        starts.append(starts[-1] + 1)

    ends = [len(candidate)]
    while ends[-1] > 0 and candidate[ends[-1] - 1] in ".:":
        ends.append(ends[-1] - 1)

    spans = sorted(
        ((start, end) for start in starts for end in ends if start < end),
        key=lambda span: span[1] - span[0],
        reverse=True,
    )
    for start, end in spans:
        try:
            return start, end, ipaddress.IPv6Address(candidate[start:end])
        except ipaddress.AddressValueError:
            continue
    return None


def is_rfc1918(network: ipaddress.IPv4Network) -> bool:
    return any(network.subnet_of(private) for private in RFC1918_NETWORKS)


def check_file(filename: str) -> bool:
    path = Path(filename)
    if not path.is_file() or ".enc." in path.name:
        return True

    lines = path.read_text(encoding="utf-8").splitlines()
    stack: list[tuple[int, str]] = []
    mesh_cidrs: list[MeshValue] = []
    wireguard_ips: list[MeshValue] = []

    for line_number, line in enumerate(lines, start=1):
        match = MAPPING.match(line)
        if not match:
            continue

        indent = len(match.group("indent"))
        key = match.group("key").strip("'\"")
        while stack and stack[-1][0] >= indent:
            stack.pop()
        yaml_path = tuple(item[1] for item in stack) + (key,)

        parsed_scalar = scalar_value(match.group("value"))
        mesh_value = MeshValue(line_number, -1, -1, "")
        if parsed_scalar:
            value, relative_start, relative_end = parsed_scalar
            value_start = match.start("value") + relative_start
            value_end = match.start("value") + relative_end
            mesh_value = MeshValue(line_number, value_start, value_end, value)

        if yaml_path == ("wireguard", "mesh_cidr"):
            mesh_cidrs.append(mesh_value)
        elif (
            len(yaml_path) == 3
            and yaml_path[0] == "hosts"
            and yaml_path[2] == "wireguard_ip"
        ):
            wireguard_ips.append(mesh_value)

        if parsed_scalar is None:
            stack.append((indent, key))

    errors: list[str] = []
    mesh_network: ipaddress.IPv4Network | None = None

    if len(mesh_cidrs) > 1:
        errors.append("wireguard.mesh_cidr must be declared exactly once")
    elif mesh_cidrs:
        cidr = mesh_cidrs[0]
        try:
            candidate = ipaddress.ip_network(cidr.value, strict=True)
        except ValueError:
            errors.append(
                f"line {cidr.line_number}: wireguard.mesh_cidr must be a valid IPv4 network"
            )
        else:
            if not isinstance(candidate, ipaddress.IPv4Network) or not is_rfc1918(candidate):
                errors.append(
                    f"line {cidr.line_number}: wireguard.mesh_cidr must be an RFC1918 IPv4 network"
                )
            else:
                mesh_network = candidate

    parsed_wireguard_ips: list[tuple[MeshValue, ipaddress.IPv4Address]] = []
    for entry in wireguard_ips:
        try:
            address = ipaddress.IPv4Address(entry.value)
        except ipaddress.AddressValueError:
            errors.append(
                f"line {entry.line_number}: hosts.<host>.wireguard_ip must be a valid IPv4 address"
            )
            continue
        parsed_wireguard_ips.append((entry, address))

    if parsed_wireguard_ips and not mesh_cidrs:
        errors.append("wireguard.mesh_cidr is required when WireGuard IPs are declared")
    seen: dict[ipaddress.IPv4Address, int] = {}
    for entry, address in parsed_wireguard_ips:
        if mesh_network:
            if address not in mesh_network:
                errors.append(
                    f"line {entry.line_number}: WireGuard IP {address} is outside {mesh_network}"
                )
        if address in seen:
            errors.append(
                f"line {entry.line_number}: duplicate WireGuard IP {address} "
                f"(first declared on line {seen[address]})"
            )
        else:
            seen[address] = entry.line_number

    permitted_spans = {
        (entry.line_number, entry.start, entry.end)
        for entry in mesh_cidrs + wireguard_ips
        if entry.start >= 0
    }
    for line_number, line in enumerate(lines, start=1):
        for start, end, address in ip_literals(line):
            if is_globally_allowed(address):
                continue
            if any(
                span_line == line_number and span_start <= start and end <= span_end
                for span_line, span_start, span_end in permitted_spans
            ):
                continue
            errors.append(
                f"line {line_number}: IP address {address} is only allowed at "
                "hosts.<host>.wireguard_ip or wireguard.mesh_cidr; "
                "host-reachability addresses belong in SOPS"
            )

    for error in errors:
        print(f"ERROR: {filename}: {error}", file=sys.stderr)
    return not errors


def main() -> int:
    failed = False
    for filename in sys.argv[1:]:
        if not check_file(filename):
            failed = True
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
