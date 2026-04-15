# OpenBao

> **Version tracked**: `v2.3.x`
> **Last updated**: `2026-04-15`

OpenBao is an identity-based secrets and encryption management system, forked from HashiCorp
Vault and managed by the Linux Foundation (LF Edge). It provides authentication-gated encryption
services accessible via UI, CLI, or HTTP API.

## Pages

| Page | Description |
|------|-------------|
| [Overview](./overview.md) | What it is, system requirements, key concepts |
| [Architecture](./architecture.md) | Internal components and dev/prod/HA deployment topologies |
| [Installation](./installation.md) | Package managers, containers, binary, Kubernetes (Helm) |
| [Configuration](./configuration.md) | Server config reference and annotated examples |
| [Secrets Engines](./secrets-engines.md) | KV, PKI, Transit, SSH, Database, and more |
| [Auth Methods](./auth-methods.md) | AppRole, Kubernetes, JWT/OIDC, LDAP, Token, and more |
| [Secrets Lifecycle](./secrets-lifecycle.md) | Leases, TTL, renewal, revocation, and response wrapping |
| [Use Cases](./use-cases.md) | K8s secret injection, PKI automation, dynamic DB creds, CI/CD |
| [API & CLI Reference](./api-cli-reference.md) | Key `bao` CLI commands and HTTP API endpoints |
| [FAQ & Links](./faq.md) | Common questions and useful links |

> Agent instructions (source URLs per page, custom section definitions, update notes) are in
> [`AGENTS.md`](./AGENTS.md).
