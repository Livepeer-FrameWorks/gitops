# Remote development

`remotedev` is the shared high-throughput build and test host. It is management-plane
infrastructure, not a miniature production cluster: do not add it to a cluster manifest and do not
install Privateer on it.

Access is key-only SSH over the office LAN or management VPN. The canonical endpoint is stored in
`hosts.enc.yaml`; split DNS should resolve `remotedev.dev.frameworks.network` only for LAN/VPN
clients. Do not publish this name in Cloudflare, add an IPv4 port forward, or allow unsolicited WAN
IPv6. Each developer receives a separate Unix account and workspace. SOPS access alone does not
create an OS account.

From a monorepo checkout:

```bash
FRAMEWORKS_GITOPS_DIR=../gitops scripts/remote-dev.sh sync my-task
scripts/remote-dev.sh run my-task pnpm runtime set node 24 -g
scripts/remote-dev.sh doctor
scripts/remote-dev.sh run my-task make test-cli
scripts/remote-dev.sh shell my-task
```

The slot name isolates concurrent conversations. Use one slot per task and keep no irreplaceable
state there. `sync` checks out the exact local commit, including unpublished commits, then mirrors
uncommitted changes while honoring repository ignore rules. Shared compiler/package caches live
outside every slot. Node 24 is installed once in the developer's isolated cache; `doctor` rejects
unsupported Node versions.

For VS Code, install Remote - SSH, connect to `remotedev.dev.frameworks.network` (or the endpoint
reported by `doctor`), and open the path reported by `scripts/remote-dev.sh path <slot>`. VS Code
Server stays in the developer's home directory; source and build output stay on NVMe.

## Onboarding

1. Create the developer's Unix account, install their SSH public key, disable password
   authentication, and add the account to `docker` and
   `frameworks-dev`. Do not grant passwordless root for normal build/test work.
2. Create `/srv/frameworks-dev/workspaces/<username>` owned by the user and group
   `frameworks-dev`, mode `2770`.
3. Grant management-VPN access to TCP/22 only and add the split-DNS record.
4. Give the developer the GitOps checkout and SOPS age key through the normal secure channel.
5. Sync a new slot, install Node 24 with the command above, run `scripts/remote-dev.sh doctor`, then
   run a small compile.

The wrapper enforces at most two concurrent `run` jobs. Additional light shells and editor sessions
are fine.
