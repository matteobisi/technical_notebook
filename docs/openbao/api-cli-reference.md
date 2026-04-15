# OpenBao — API & CLI Reference

## CLI Quick Reference

The OpenBao CLI binary is `bao` (note: environment variables use `BAO_` prefix; some tools also
accept the legacy `VAULT_` prefix for compatibility with HashiCorp Vault clients).

### Environment Setup

```bash
export BAO_ADDR="https://openbao.example.com:8200"
export BAO_TOKEN="<your-token>"
export BAO_CACERT="/etc/openbao/tls/ca.crt"  # if using a custom CA
```

---

### Operator Commands

| Command | Description |
|---------|-------------|
| `bao operator init` | Initialize a new OpenBao cluster; generates unseal keys and root token |
| `bao operator init -key-shares=5 -key-threshold=3` | Init with 5 shares, threshold of 3 |
| `bao operator unseal` | Provide one unseal key share interactively |
| `bao operator unseal <key>` | Provide unseal key non-interactively |
| `bao operator seal` | Seal OpenBao (requires root or sudo policy) |
| `bao operator step-down` | Force the active node to step down as leader |
| `bao operator raft list-peers` | List Raft cluster members |
| `bao operator raft join https://leader:8200` | Join this node to a Raft cluster |
| `bao operator generate-root` | Generate a new root token (requires unseal key quorum) |
| `bao operator rotate-keys` | Rotate the barrier encryption key |
| `bao status` | Show seal status, cluster info, and leader |

```bash
# Example: initialize with 3-of-5 shares, output as JSON
bao operator init -key-shares=5 -key-threshold=3 -format=json > init-output.json

# Unseal loop (3 times with different key holders)
bao operator unseal $(jq -r '.unseal_keys_b64[0]' init-output.json)
bao operator unseal $(jq -r '.unseal_keys_b64[1]' init-output.json)
bao operator unseal $(jq -r '.unseal_keys_b64[2]' init-output.json)
```

---

### Auth Commands

| Command | Description |
|---------|-------------|
| `bao auth enable <type>` | Enable an auth method |
| `bao auth disable <path>` | Disable an auth method |
| `bao auth list` | List enabled auth methods |
| `bao auth tune -ttl=1h auth/approle/` | Tune mount configuration |
| `bao login -method=<type>` | Authenticate and store token |
| `bao token create -policy=<p> -ttl=1h` | Create a service token |
| `bao token renew <token>` | Renew a token |
| `bao token revoke <token>` | Revoke a token and all its children |
| `bao token lookup` | Look up the current token |
| `bao token capabilities <path>` | Show capabilities on a path for current token |

---

### Secrets Commands

| Command | Description |
|---------|-------------|
| `bao secrets enable <type>` | Enable a secrets engine |
| `bao secrets disable <path>` | Disable and delete all data at path |
| `bao secrets list` | List enabled secrets engines |
| `bao secrets move <src> <dst>` | Move a mount (revokes all secrets) |
| `bao kv put -mount=<m> <path> <k>=<v>` | Write a KV secret |
| `bao kv get -mount=<m> <path>` | Read a KV secret (latest version) |
| `bao kv get -mount=<m> -version=<n> <path>` | Read a specific version |
| `bao kv patch -mount=<m> <path> <k>=<v>` | Partial update of a KV secret |
| `bao kv delete -mount=<m> <path>` | Soft-delete latest version |
| `bao kv destroy -mount=<m> -versions=<n> <path>` | Permanently destroy versions |
| `bao kv list -mount=<m> <path>` | List keys |
| `bao kv metadata get -mount=<m> <path>` | Get metadata for all versions |

---

### Policy Commands

| Command | Description |
|---------|-------------|
| `bao policy write <name> <file.hcl>` | Create or update a policy |
| `bao policy read <name>` | Read a policy |
| `bao policy list` | List all policies |
| `bao policy delete <name>` | Delete a policy |

Example policy file (`my-policy.hcl`):

```hcl
# Allow read on a specific KV path
path "secret/data/myapp/*" {
  capabilities = ["read", "list"]
}

# Allow full access to PKI issuance
path "pki/issue/internal-services" {
  capabilities = ["create", "update"]
}

# Allow the token to renew itself
path "auth/token/renew-self" {
  capabilities = ["update"]
}
```

---

### Lease Management

| Command | Description |
|---------|-------------|
| `bao lease renew <lease_id>` | Renew a lease |
| `bao lease revoke <lease_id>` | Revoke a lease |
| `bao lease revoke -prefix <prefix>` | Revoke all leases under a prefix |
| `bao lease lookup <lease_id>` | Show lease metadata |

---

## HTTP API Reference

Base URL: `https://<host>:8200/v1`

All authenticated requests must include:
```
X-Vault-Token: <token>
```

or for namespace-aware requests:
```
X-Vault-Namespace: <namespace>
```

### System Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/sys/health` | Health check (unauthenticated) |
| `GET` | `/sys/seal-status` | Seal status |
| `PUT` | `/sys/unseal` | Submit one unseal key share |
| `PUT` | `/sys/seal` | Seal the server |
| `GET` | `/sys/init` | Check initialization status |
| `PUT` | `/sys/init` | Initialize the server |
| `GET` | `/sys/leader` | Active node info |
| `GET` | `/sys/ha-status` | HA cluster status |
| `LIST` | `/sys/mounts` | List mounted secrets engines |
| `POST` | `/sys/mounts/<path>` | Enable a secrets engine |
| `DELETE` | `/sys/mounts/<path>` | Disable a secrets engine |
| `LIST` | `/sys/auth` | List enabled auth methods |
| `POST` | `/sys/auth/<path>` | Enable an auth method |
| `DELETE` | `/sys/auth/<path>` | Disable an auth method |
| `LIST` | `/sys/policies/acl` | List ACL policies |
| `GET` | `/sys/policies/acl/<name>` | Read a policy |
| `PUT` | `/sys/policies/acl/<name>` | Create/update a policy |
| `DELETE` | `/sys/policies/acl/<name>` | Delete a policy |

### Token Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/auth/token/create` | Create a token |
| `POST` | `/auth/token/lookup-self` | Look up the current token |
| `POST` | `/auth/token/renew-self` | Renew the current token |
| `POST` | `/auth/token/revoke-self` | Revoke the current token |

### KV v2 Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/secret/data/<path>` | Read the latest version of a secret |
| `POST` | `/secret/data/<path>` | Write a new version |
| `PATCH` | `/secret/data/<path>` | Partial update |
| `DELETE` | `/secret/data/<path>` | Soft-delete the latest version |
| `LIST` | `/secret/metadata/<path>` | List keys |
| `GET` | `/secret/metadata/<path>` | Read metadata (all versions) |
| `POST` | `/secret/delete/<path>` | Delete specific versions |
| `POST` | `/secret/undelete/<path>` | Undelete specific versions |
| `POST` | `/secret/destroy/<path>` | Permanently destroy specific versions |

### Example: Read a KV v2 Secret

```bash
curl -s \
  --header "X-Vault-Token: $BAO_TOKEN" \
  https://openbao:8200/v1/secret/data/myapp/config

# Response structure:
# {
#   "data": {
#     "data": { "key": "value", ... },
#     "metadata": { "version": 3, "created_time": "...", "destroyed": false, ... }
#   }
# }
```

### Example: Write a KV v2 Secret

```bash
curl -s \
  --header "X-Vault-Token: $BAO_TOKEN" \
  --request POST \
  --data '{"data":{"db_password":"s3cr3t","api_key":"abc123"}}' \
  https://openbao:8200/v1/secret/data/myapp/config
```

### Example: AppRole Login

```bash
curl -s \
  --request POST \
  --data "{\"role_id\":\"$ROLE_ID\",\"secret_id\":\"$SECRET_ID\"}" \
  https://openbao:8200/v1/auth/approle/login \
  | jq -r '.auth.client_token'
```

---

## Sources

- https://openbao.org/api-docs/2.3.x/
- https://openbao.org/docs/secrets/kv/kv-v2/
- https://openbao.org/docs/auth/approle/
