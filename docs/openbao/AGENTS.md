# OpenBao — Documentation Spec

> This file is the single source of truth agents read before working on OpenBao docs.
> Repo-level rules are in `../../AGENTS.md`.

---

## Release Tracking

- **version_check_url**: https://github.com/openbao/openbao/releases/latest
- **changelog_url**: https://github.com/openbao/openbao/blob/main/CHANGELOG.md
- **version**: v2.3.x

---

## Standard Sections

### overview.md

**Description**: What OpenBao is, its fork history (from HashiCorp Vault, governed by LF Edge),
system requirements (OS, CPU, memory), and key concepts: seal/unseal, tokens, policies,
namespaces, the secret engine model.

**Sources**:
- https://openbao.org/docs/what-is-openbao/
- https://openbao.org/docs/concepts/tokens/
- https://openbao.org/docs/concepts/seal/
- https://openbao.org/docs/concepts/policies/

---

### architecture.md

**Description**: Internal server components (API/UI layer, auth broker, secret engine manager,
storage backend, expiration manager), data flow, and deployment topologies: dev mode,
single-node production, Raft HA cluster, Kubernetes via Helm. Mermaid diagrams are required
for at least the component diagram and the HA topology.

Includes a **Deployment Platform Comparison** section covering the security preference ordering
(Bare Metal > VM > Container > Kubernetes) for running a secrets manager, with a Mermaid
isolation-stack diagram, per-platform pros/cons tables, required hardening steps for Kubernetes,
and a six-criterion decision matrix. Update this section if the official hardening guidance,
Helm chart capabilities, or cloud KMS auto-unseal options change significantly.

**Sources**:
- https://openbao.org/docs/internals/architecture/
- https://openbao.org/docs/concepts/integrated-storage/
- https://openbao.org/docs/platform/k8s/helm/

---

### installation.md

**Description**: Installing OpenBao via package manager (apt/yum), official container image,
binary download from GitHub releases, and Kubernetes deployment via the official Helm chart.

**Sources**:
- https://openbao.org/docs/install/
- https://openbao.org/docs/platform/k8s/helm/

---

### configuration.md

**Description**: Server `config.hcl` reference: storage backends (Raft — primary recommended,
Consul, file for dev), listeners (TCP, TLS certificates), seal configuration (Shamir default,
auto-unseal via cloud KMS), telemetry, and logging. Include annotated real-world examples.

**Sources**:
- https://openbao.org/docs/configuration/
- https://openbao.org/docs/configuration/storage/raft/
- https://openbao.org/docs/configuration/seal/

---

### use-cases.md

**Description**: End-to-end scenarios: (1) Kubernetes pod secret injection via the Vault Agent
Injector / CSI driver, (2) dynamic database credentials with auto-rotation, (3) PKI automation
for internal TLS, (4) CI/CD pipeline secret injection. Each scenario must include a Mermaid
sequence diagram.

**Sources**:
- https://openbao.org/docs/auth/kubernetes/
- https://openbao.org/docs/secrets/pki/
- https://openbao.org/docs/secrets/databases/

---

### api-cli-reference.md

**Description**: Key `bao` CLI commands (operator init, operator unseal, login, read, write,
delete, kv get, kv put, lease renew, lease revoke) and commonly used HTTP API endpoints with
`curl` examples. Note: the binary is `bao`, not `vault`.

**Sources**:
- https://openbao.org/api-docs/2.3.x/
- https://openbao.org/docs/commands/

---

### faq.md

**Description**: Common questions (Vault migration, KV v1 vs v2, namespace OSS availability),
troubleshooting, and useful links: official site, GitHub repo, API docs, community channels.

**Sources**:
- https://openbao.org/docs/what-is-openbao/
- https://github.com/openbao/openbao

---

## Custom Sections

### secrets-engines.md

**Description**: All available secrets engines with enable, configure, and use examples:
KV v1 and v2 (important: KV v2 policies must use `secret/data/foo`, not `secret/foo`),
PKI (CA hierarchy, cert issuance, CRL), Transit (encryption-as-a-service, HMAC, signing),
SSH (OTP and CA modes), Database (dynamic credentials for PostgreSQL, MySQL, MongoDB),
TOTP. Cover the difference between v1 and v2 path semantics explicitly.

**Sources**:
- https://openbao.org/docs/secrets/
- https://openbao.org/docs/secrets/kv/kv-v2/
- https://openbao.org/docs/secrets/pki/
- https://openbao.org/docs/secrets/transit/
- https://openbao.org/docs/secrets/ssh/
- https://openbao.org/docs/secrets/databases/

---

### auth-methods.md

**Description**: All supported authentication methods with enable, configure, and login examples:
Token (root token, child tokens, orphan tokens, periodic tokens), AppRole (service-to-service
automation), Kubernetes (pod identity via service account JWT), JWT/OIDC (external IdP
integration), LDAP, GitHub, TLS Certificates, UserPass.

**Sources**:
- https://openbao.org/docs/auth/
- https://openbao.org/docs/auth/approle/
- https://openbao.org/docs/auth/kubernetes/
- https://openbao.org/docs/auth/jwt/
- https://openbao.org/docs/auth/ldap/

---

### secrets-lifecycle.md

**Description**: Complete lifecycle of a secret from creation to final revocation. Covers:
what a lease is and why it exists, TTL mechanics (creation TTL vs max TTL), the difference
between renewable and non-renewable leases, how to renew a lease (`bao lease renew`), how to
revoke a lease (`bao lease revoke`) — both individual and prefix-based, the expiration manager's
role, and response wrapping (single-use tokens wrapping a response). A Mermaid state diagram
showing lease states (active, expiring, expired, revoked) is required.

**Sources**:
- https://openbao.org/docs/concepts/lease/
- https://openbao.org/docs/concepts/response-wrapping/
- https://openbao.org/docs/concepts/tokens/

---

## Update Notes

- The CLI binary is `bao` (not `vault`). Verify all commands use the `bao` prefix.
- Environment variables use `BAO_` prefix: `BAO_ADDR`, `BAO_TOKEN`, `BAO_NAMESPACE`.
- OpenBao is API-compatible with HashiCorp Vault; do not reference Vault documentation.
- Namespace support is OSS in OpenBao v2.x (it was enterprise-only in Vault).
- KV v2 policy paths differ from KV v1: always use `secret/data/foo` in policy HCL, not `secret/foo`.
- Check the `version_check_url` to confirm the current stable version before updating.
- The `destroy` and `undelete` sub-commands in KV v2 use different path prefixes (`secret/destroy/`, `secret/undelete/`) — verify examples against official docs.
- Do not invent command flags or API parameters; verify each one against the API docs source.
