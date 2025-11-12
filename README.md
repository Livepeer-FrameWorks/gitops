# FrameWorks GitOps Repository

This repository contains deployment manifests and configuration for FrameWorks platform releases.

## Structure

```
.
├── releases/          # Release manifests (one per version tag)
│   ├── v1.0.0.yaml
│   ├── v1.0.1.yaml
│   └── ...
├── channels/          # Channel pointers (stable, rc, dev)
│   ├── stable.yaml    # Points to latest stable release
│   ├── rc.yaml        # Points to release candidate
│   └── dev.yaml       # Points to development builds
├── base/              # Base Kubernetes/Docker manifests
│   └── (TBD)
└── environments/      # Environment-specific overlays
    ├── development/
    ├── staging/
    └── production/
```

## Release Manifests

Release manifests are automatically generated and pushed by the CI/CD pipeline when a new version tag is created in the monorepo.

Each manifest contains:
- Platform version
- Git commit SHA
- Release timestamp
- Service versions (from VERSION files)
- Docker image references with SHA256 digests
- External dependencies (MistServer, etc.)

## Channels

Channels provide stable references to specific release versions:

- **stable**: Latest production-ready release
- **rc**: Release candidate for staging environments
- **dev**: Latest development build (not for production)

## Usage

### Deploying a Specific Version

```bash
# Download the manifest for a specific version
curl -O https://raw.githubusercontent.com/Livepeer-FrameWorks/gitops/main/releases/v1.0.0.yaml

# Use with docker-compose or Kubernetes
```

### Deploying via Channel

```bash
# Get the stable channel manifest
curl -O https://raw.githubusercontent.com/Livepeer-FrameWorks/gitops/main/channels/stable.yaml

# This points to the current stable release
```
