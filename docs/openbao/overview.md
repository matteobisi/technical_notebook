# OpenBao — Overview

## Description

OpenBao is an identity-based secrets and encryption management system. A _secret_ is anything
requiring tightly controlled access: API keys, passwords, database credentials, TLS certificates,
and encryption keys. OpenBao provides encryption services gated by authentication and authorization
methods, making access to sensitive data secure, restricted, and auditable.

OpenBao is a fork of HashiCorp Vault and is managed by the Linux Foundation under the LF Edge
project. It is open-source, community-driven, and vendor-neutral.

Modern systems require access to a multitude of secrets across many services and platforms.
Without a centralized secrets manager, credentials end up in plain text, in application source
code, or in config files — scattered and hard to audit. OpenBao solves this by validating and
authorizing clients (users, machines, applications) before providing them access to secrets or
stored sensitive data.

## Why use it?

- **Centralized secrets management**: single source of truth for all credentials and keys.
- **Dynamic secrets**: generate short-lived credentials on demand (e.g., database passwords,
  cloud credentials) instead of long-lived static ones.
- **Encryption as a service**: encrypt/decrypt data without exposing keys to the application.
- **Fine-grained access control**: path-based ACL policies control exactly who can do what.
- **Auditability**: every request and response is logged by audit devices.
- **Open-source / vendor-neutral**: no proprietary licensing; LF Edge governance.

## System Requirements

### Hardware

| Component | Minimum (dev) | Recommended (production) |
|-----------|--------------|--------------------------|
| CPU | 1 core | 2+ cores |
| RAM | 256 MB | 1 GB+ |
| Disk | 100 MB (binary only) | Depends on storage backend (SSD recommended for Raft) |
| Network | — | Low-latency between cluster nodes for Raft replication |

### Software

| Dependency | Notes |
|------------|-------|
| OS | Linux (amd64, arm64), macOS, Windows, FreeBSD |
| Go | Required only when compiling from source (see install docs) |
| Kubernetes | 1.30–1.33 supported for Helm chart deployment |

> **Note**: OpenBao has no external runtime dependencies when running as a binary. Storage
> backends such as Raft (integrated) require no additional services; Consul requires a running
> Consul cluster.

## Key Concepts

- **Seal / Unseal**: OpenBao starts in a *sealed* state. Data is encrypted at rest and the
  decryption key (root key) is not in memory. *Unsealing* loads the root key using unseal key
  shares (Shamir) or an auto-unseal provider (KMS/HSM).
- **Shamir's Secret Sharing**: the root key is split into *N* shares; a *threshold* of shares is
  required to reconstruct it. This prevents any single operator from having full access.
- **Auto Unseal**: delegates unseal responsibility to a trusted KMS (AWS, GCP, Azure) or HSM,
  removing manual operator intervention at startup.
- **Token**: the core authentication artifact in OpenBao. Every client interaction uses a token,
  which has policies attached, a TTL, and optionally a renewal mechanism. Token types: `service`
  (persistent, renewable) and `batch` (ephemeral, high-performance).
- **Policy**: a named ACL rule using path-based allow/deny logic. OpenBao operates in
  *default-deny* mode — access is only permitted when a policy explicitly grants it.
- **Secrets Engine**: a plugin mounted at a path that stores, generates, or encrypts data (e.g.,
  `kv/`, `pki/`, `transit/`).
- **Auth Method**: a plugin that performs authentication and returns a token with policies (e.g.,
  `approle`, `kubernetes`, `jwt`).
- **Lease**: most secrets in OpenBao have a lease — a TTL after which the secret is revoked.
  Clients can renew leases before expiry.
- **Barrier**: OpenBao's encryption layer. All storage backend writes pass through the barrier
  and are encrypted before leaving OpenBao's trust boundary.
- **Audit Device**: logs every request and response (after HMAC-ing sensitive values) to a file,
  syslog, or socket.

---

## Sources

- https://openbao.org/docs/what-is-openbao/
- https://openbao.org/docs/concepts/seal/
- https://openbao.org/docs/concepts/tokens/
- https://openbao.org/docs/internals/architecture/
