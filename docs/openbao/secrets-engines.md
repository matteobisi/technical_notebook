# OpenBao — Secrets Engines

Secrets engines are components that store, generate, or encrypt data. They are mounted at a
path in OpenBao and expose a virtual filesystem-like API (`read`, `write`, `delete`, `list`).

Each secrets engine operates within a **barrier view**: a scoped, UUID-prefixed namespace in
the storage backend. An engine cannot access data from another engine, even if compromised.

---

## Lifecycle

```bash
# Enable a secrets engine at a path (default path = engine type name)
bao secrets enable kv-v2

# Enable at a custom path
bao secrets enable -path=myapp/secrets kv-v2

# List enabled engines
bao secrets list

# Tune a mount (e.g., change default TTL)
bao secrets tune -default-lease-ttl=24h kv/

# Disable (revokes all secrets and deletes all stored data for that mount)
bao secrets disable kv/

# Move a mount (revokes all secrets)
bao secrets move kv/ kv-old/
```

> **Note**: paths are case-sensitive. `kv/` and `KV/` are treated as distinct mounts.

---

## KV — Key/Value

### KV v1 (unversioned)

Simple key-value store. No versioning, no metadata.

```bash
bao secrets enable -version=1 kv
bao kv put kv/my-secret password=s3cr3t
bao kv get kv/my-secret
bao kv delete kv/my-secret
```

### KV v2 (versioned) — Recommended

Stores multiple versions of each secret. Supports soft-delete, undelete, and destroy.

```bash
bao secrets enable kv-v2
# or equivalently:
bao secrets enable -version=2 kv

# Write
bao kv put -mount=secret my-secret foo=bar
# Read latest version
bao kv get -mount=secret my-secret
# Read a specific version
bao kv get -mount=secret -version=2 my-secret
# Partial update (patch)
bao kv patch -mount=secret my-secret foo=newvalue
# Soft-delete latest version
bao kv delete -mount=secret my-secret
# Undelete a version
bao kv undelete -mount=secret -versions=2 my-secret
# Permanently destroy a version
bao kv destroy -mount=secret -versions=2 my-secret
# List keys
bao kv list -mount=secret /
```

#### ACL path differences (v1 vs v2)

KV v2 uses a prefixed API. Policies must be updated:

| Operation | v1 path | v2 path |
|-----------|---------|---------|
| Read/Write | `secret/foo` | `secret/data/foo` |
| List | `secret/` | `secret/metadata/` |
| Soft-delete | `secret/foo` (delete cap) | `secret/data/foo` (delete cap) |
| Hard-delete any version | — | `secret/delete/foo` (update cap) |
| Undelete | — | `secret/undelete/foo` (update cap) |
| Destroy | — | `secret/destroy/foo` (update cap) |

---

## PKI — Certificate Authority

Issues TLS certificates and manages certificate lifecycles. Can operate as a root CA or an
intermediate CA signed by an external root.

```bash
bao secrets enable pki
# Set max TTL for this mount
bao secrets tune -max-lease-ttl=87600h pki

# Generate internal root CA
bao write -field=certificate pki/root/generate/internal \
  common_name="My Root CA" ttl=87600h > root_ca.crt

# Configure CRL and issuing certificate URLs
bao write pki/config/urls \
  issuing_certificates="https://openbao:8200/v1/pki/ca" \
  crl_distribution_points="https://openbao:8200/v1/pki/crl"

# Create a role
bao write pki/roles/web-server \
  allowed_domains="example.com" \
  allow_subdomains=true \
  max_ttl="72h"

# Issue a certificate
bao write pki/issue/web-server \
  common_name="web.example.com" ttl="24h"
```

---

## Transit — Encryption as a Service

Provides encryption, decryption, signing, verification, and HMAC operations without exposing
the cryptographic keys to the caller. Keys never leave OpenBao.

```bash
bao secrets enable transit

# Create a named encryption key
bao write -f transit/keys/my-key

# Encrypt data (input must be base64-encoded)
bao write transit/encrypt/my-key \
  plaintext=$(echo -n "my secret data" | base64)

# Decrypt
bao write transit/decrypt/my-key \
  ciphertext="vault:v1:abc123..."

# Rotate the key (old ciphertext remains decryptable; new encryptions use new key version)
bao write -f transit/keys/my-key/rotate

# Rewrap ciphertext to latest key version
bao write transit/rewrap/my-key \
  ciphertext="vault:v1:abc123..."
```

---

## SSH — SSH Credentials

Two modes: **signed certificates** (recommended) and **OTP (one-time passwords)**.

### Signed Certificates

OpenBao acts as an SSH CA. It signs user/host public keys.

```bash
bao secrets enable ssh

# Create a CA signing key
bao write ssh/config/ca generate_signing_key=true

# Create a role for user certificates
bao write ssh/roles/my-role \
  key_type=ca \
  allowed_users="ubuntu,ec2-user" \
  ttl=30m

# Sign a user's public key
bao write ssh/sign/my-role \
  public_key=@$HOME/.ssh/id_ed25519.pub
```

---

## Database — Dynamic Credentials

Generates short-lived credentials for databases on demand. Supports PostgreSQL, MySQL/MariaDB,
MongoDB, Cassandra, Valkey, InfluxDB, and more.

```bash
bao secrets enable database

# Configure a PostgreSQL connection
bao write database/config/my-postgres \
  plugin_name=postgresql-database-plugin \
  connection_url="postgresql://{{username}}:{{password}}@postgres:5432/mydb?sslmode=disable" \
  allowed_roles="my-role" \
  username="vault_admin" \
  password="admin-password"

# Create a role that generates read-only credentials
bao write database/roles/my-role \
  db_name=my-postgres \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"

# Generate credentials
bao read database/creds/my-role
```

---

## TOTP — Time-Based One-Time Passwords

Generates TOTP codes compatible with RFC 6238 (e.g., compatible with Google Authenticator).

```bash
bao secrets enable totp

# Create a key
bao write totp/keys/my-key \
  generate=true \
  issuer=MyApp \
  account_name=user@example.com

# Generate a code
bao read totp/code/my-key

# Validate a code
bao write totp/code/my-key code=123456
```

---

## Kubernetes — Dynamic Service Account Tokens

Generates short-lived Kubernetes service account tokens.

```bash
bao secrets enable kubernetes

bao write kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
  service_account_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token

bao write kubernetes/roles/my-role \
  allowed_kubernetes_namespaces="app-ns" \
  service_account_name="myapp-sa" \
  token_default_ttl="10m"

bao write kubernetes/creds/my-role \
  kubernetes_namespace="app-ns"
```

---

## Cubbyhole

A per-token storage namespace. Only the token that writes to it can read from it. Used for
response wrapping. Cannot be disabled or mounted at multiple paths.

```bash
bao write cubbyhole/my-secret key=value
bao read cubbyhole/my-secret
```

---

## Sources

- https://openbao.org/docs/secrets/
- https://openbao.org/docs/secrets/kv/kv-v2/
- https://openbao.org/api-docs/2.3.x/secret/
