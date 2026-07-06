# OpenBao — Configuration

OpenBao servers are configured via HCL or JSON files (outside of dev mode). Multiple files in
a directory are loaded alphabetically. Pass the config path with `bao server -config=<path>`.

---

## Core Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `storage` | block | **required** | Storage backend (see below) |
| `listener` | block | **required** | API listener (TCP/TLS) |
| `user_lockout` | block | `nil` | Failed-login lockout configuration for supported auth methods |
| `seal` | block | `nil` | Auto-unseal provider; if omitted, Shamir is used |
| `ha_storage` | block | `nil` | HA coordination backend if different from `storage` |
| `audit` | block | none | Audit device configuration (repeatable) |
| `initialize` | block | none | Declarative self-initialization requests run on first startup |
| `ui` | bool | `false` | Enable built-in web UI at `/ui` |
| `cluster_name` | string | generated | Identifier for the cluster |
| `default_lease_ttl` | string | `"768h"` | Default token/secret lease duration |
| `max_lease_ttl` | string | `"768h"` | Maximum allowed lease duration |
| `log_level` | string | `"info"` | `trace`, `debug`, `info`, `warn`, `error` |
| `disable_cache` | bool | `false` | Disable all caches (significant performance impact) |
| `plugin_directory` | string | `""` | Directory from which plugins may be loaded |
| `raw_storage_endpoint` | bool | `false` | Enable `sys/raw` (highly privileged; avoid in prod) |
| `introspection_endpoint` | bool | `false` | Enable `sys/internal/inspect` for root/sudo inspection |
| `disable_standby_reads` | bool | `false` | Disable read handling on standby nodes |

---

## Storage Backends

### Integrated (Raft) — Recommended

Built-in distributed storage. No external dependencies. Supports HA.

```hcl
storage "raft" {
  path    = "/opt/openbao/data"
  node_id = "node1"
}
```

| Parameter | Description |
|-----------|-------------|
| `path` | Local filesystem path where Raft data is stored |
| `node_id` | Unique identifier for this node in the cluster |
| `retry_join` | Repeated block to join an existing cluster (see HA example below) |

> **Deprecation note**: the `file` storage backend is deprecated for removal in OpenBao v2.7.0.
> Use Raft for persistent production deployments.

### Consul

External Consul cluster required. Provides HA coordination.

```hcl
storage "consul" {
  address = "127.0.0.1:8500"
  path    = "openbao/"
}
```

### File (non-HA)

Simple local file storage. No HA support.

```hcl
storage "file" {
  path = "/opt/openbao/data"
}
```

---

## Listener

### TCP (with TLS — recommended for production)

```hcl
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/etc/openbao/tls/server.crt"
  tls_key_file  = "/etc/openbao/tls/server.key"
}
```

### TCP (TLS disabled — dev/internal only)

```hcl
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}
```

---

## Seal

If no `seal` block is provided, Shamir's Secret Sharing is used (manual unseal required
on every restart).

### AWS KMS (Auto Unseal)

```hcl
seal "awskms" {
  region     = "us-east-1"
  kms_key_id = "alias/openbao-unseal"
}
```

### GCP Cloud KMS (Auto Unseal)

```hcl
seal "gcpckms" {
  project    = "my-gcp-project"
  region     = "global"
  key_ring   = "openbao-keyring"
  crypto_key = "openbao-unseal"
}
```

### PKCS11 / HSM (Auto Unseal)

```hcl
seal "pkcs11" {
  lib            = "/usr/lib/softhsm/libsofthsm2.so"
  slot           = "0"
  pin            = "1234"
  key_label      = "openbao-unseal"
  hmac_key_label = "openbao-hmac"
}
```

### KMS plugins (external Auto Unseal)

OpenBao v2.5 adds a `kms` plugin type for external Auto Unseal integrations. A registered KMS
plugin can then be referenced by name from a `seal` stanza. Built-in provider-specific seals are
planned for removal in v2.7.0 and remain available as external plugins.

```hcl
plugin "kms" "example" {}

seal "example" {}
```

---

## Annotated Examples

### Minimal: Single Node (dev-like, no TLS)

```hcl
storage "file" {
  path = "/opt/openbao/data"
}

listener "tcp" {
  address     = "127.0.0.1:8200"
  tls_disable = true
}

ui = true
```

### Production: Single Node with TLS

```hcl
storage "raft" {
  path    = "/opt/openbao/data"
  node_id = "openbao-prod-1"
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_cert_file = "/etc/openbao/tls/server.crt"
  tls_key_file  = "/etc/openbao/tls/server.key"
}

seal "awskms" {
  region     = "us-east-1"
  kms_key_id = "alias/openbao-unseal"
}

audit {
  type = "file"
  options = {
    file_path = "/var/log/openbao/audit.log"
  }
}

ui             = true
cluster_name   = "prod-cluster"
log_level      = "warn"
default_lease_ttl = "24h"
max_lease_ttl     = "720h"
```

### HA: 3-Node Raft Cluster

Each node gets an identical config with its own `node_id` and `retry_join` blocks pointing to
the other two nodes.

```hcl
# Node 1: /etc/openbao/config.hcl
storage "raft" {
  path    = "/opt/openbao/data"
  node_id = "node1"

  retry_join {
    leader_api_addr = "https://openbao-node2:8200"
    leader_ca_cert_file = "/etc/openbao/tls/ca.crt"
  }
  retry_join {
    leader_api_addr = "https://openbao-node3:8200"
    leader_ca_cert_file = "/etc/openbao/tls/ca.crt"
  }
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_cert_file   = "/etc/openbao/tls/server.crt"
  tls_key_file    = "/etc/openbao/tls/server.key"
}

seal "awskms" {
  region     = "us-east-1"
  kms_key_id = "alias/openbao-unseal"
}

cluster_name = "prod-ha"
ui           = true
log_level    = "warn"
```

> **Note**: Each node requires its own `node_id`. Use `cluster_addr` to advertise the Raft
> address to peers. Nodes join each other via `retry_join` on startup.

---

## Declarative Self-Initialization

The `initialize` stanza lets operators define one-time bootstrap requests that run automatically
on first startup. Current releases add stricter validation for unknown keys and extend
self-initialization with CEL expressions, `text/template` rendering, conditional `when`
execution, explicit request headers, and support in development server mode.

Use this for repeatable bootstrap tasks such as enabling audit devices, auth methods, or mounts
without manually replaying API calls after initialization.

---

## Environment Variables

OpenBao respects several environment variables that override config file values:

| Variable | Description |
|----------|-------------|
| `BAO_ADDR` | Client address (e.g., `https://openbao:8200`) |
| `BAO_TOKEN` | Client token |
| `BAO_NAMESPACE` | Namespace applied to client requests |
| `BAO_CACERT` | Path to CA certificate for TLS verification |
| `BAO_SKIP_VERIFY` | Skip TLS verification (`true`/`false`) — avoid in production |
| `BAO_LOG_LEVEL` | Overrides `log_level` in config |

---

## Sources

- https://openbao.org/docs/configuration/
- https://openbao.org/docs/configuration/storage/raft/
- https://openbao.org/docs/configuration/seal/
- https://openbao.org/docs/configuration/self-init/
- https://github.com/openbao/openbao/blob/main/CHANGELOG.md
