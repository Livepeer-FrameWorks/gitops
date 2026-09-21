# Staging

Private, production-shaped environment for pre-production validation. It tracks the `candidate`
release channel.

## Topology

| VM | Host | Role |
| --- | --- | --- |
| 107 | `fw-stg-core` | control plane, support services, ClickHouse, observability |
| 108–110 | `fw-stg-eu-1..3` | YugabyteDB and EU regional services |
| 111–113 | `fw-stg-us-1..3` | US regional services |
| 114 | `fw-stg-edge-eu` | EU media edge |
| 115 | `fw-stg-edge-us` | US media edge |

## Policy

- Access is LAN/VPN only; there are no staging WAN port forwards.
- Public DNS reconciliation and external Alertmanager/Lookout notifications are disabled.
- ACME DNS-01 certificates and in-app Lookout incidents remain enabled.
- Edge Foghorn and telemetry traffic use the private addresses in `edge.yaml`.
- The logical US cell runs on the same EU infrastructure as the rest of staging.

## Apply and validate

```bash
frameworks mesh wg check \
  --gitops-dir . \
  --cluster staging

frameworks cluster provision \
  --gitops-dir . \
  --cluster staging

frameworks edge provision \
  --manifest clusters/staging/edge.yaml \
  --cluster-manifest cluster.yaml \
  --parallel 1

frameworks cluster doctor \
  --gitops-dir . \
  --cluster staging \
  --deep
```
