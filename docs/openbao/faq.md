# OpenBao — FAQ & Useful Links

## Frequently Asked Questions

### Q: What is the difference between sealed and initialized?

**A**: *Initialization* happens once per cluster: `bao operator init` generates the encryption
keys and returns unseal key shares + the initial root token. *Unsealing* happens every time the
server restarts: it loads the root key from the unseal key shares (Shamir) or from the KMS/HSM
(Auto Unseal) so that the encryption barrier can decrypt data in storage.

An uninitialized server has never been set up. A sealed server is initialized but the root key
is not in memory — it cannot serve any requests until unsealed.

---

### Q: How many unseal keys are needed?

**A**: By default `bao operator init` creates 5 key shares with a threshold of 3. You need to
run `bao operator unseal` 3 times with 3 different shares to unseal the server. Both values
are configurable at init time via `-key-shares` and `-key-threshold`.

For production, consider Auto Unseal (KMS/HSM) to avoid manual operator intervention at each
restart.

---

### Q: How do I avoid having to unseal manually after every restart?

**A**: Configure Auto Unseal in the server config using an `awskms`, `gcpckms`, `azurekeyvault`,
or `pkcs11` seal block. OpenBao will call the KMS/HSM at startup to unwrap the root key
automatically. See [configuration.md](./configuration.md) for examples.

Warning: if the KMS key is deleted or becomes unavailable, the cluster cannot be unsealed even
from a backup. Guard KMS key access carefully.

---

### Q: What happens to tokens when an auth method is disabled?

**A**: All users authenticated via that method are immediately logged out — their tokens are
revoked. All secrets that were created using those tokens (and whose leases were associated with
them) are also revoked.

---

### Q: My token expired. How do I renew it before expiry?

**A**:

```bash
# Renew the current token
bao token renew

# Renew a specific token
bao token renew <token>

# Renew via API
curl --header "X-Vault-Token: $BAO_TOKEN" \
  --request POST \
  https://openbao:8200/v1/auth/token/renew-self
```

Tokens with an explicit `max_ttl` cannot be renewed past that maximum. Periodic tokens
(created with `-period`) have no `max_ttl` by default and can be renewed indefinitely as long
as they are renewed before each period expires.

---

### Q: How do I migrate from HashiCorp Vault?

**A**: OpenBao is a fork of HashiCorp Vault and is largely API-compatible. The main differences:
- The CLI binary is `bao` instead of `vault`.
- Environment variables use `BAO_` prefix (though `VAULT_` is accepted for compatibility in
  some versions).
- Some enterprise-only Vault features are not present (namespaces were added in OpenBao as an
  open-source feature in v2.x).

For storage migration, take a Vault snapshot (`vault operator raft snapshot save`) and restore
it into an OpenBao cluster (`bao operator raft snapshot restore`). Always test in a non-production
environment first.

---

### Q: How do I back up and restore an OpenBao cluster?

**A**: For Raft (integrated) storage:

```bash
# Backup (from an authenticated client)
bao operator raft snapshot save backup.snap

# Restore (stops the cluster briefly)
bao operator raft snapshot restore backup.snap
```

Store snapshots encrypted and offsite. Schedule them via cron or an external tool.

---

### Q: Can standby nodes serve read requests?

**A**: Yes, unless `disable_standby_reads = true` is set in the configuration. By default,
standbys can serve reads, which helps distribute read load in HA deployments. Write requests
are always forwarded to the active node.

---

### Q: What is the `cubbyhole` secrets engine and when should I use it?

**A**: `cubbyhole` is a per-token private storage space: only the token that writes to it can
read from it. When the token is revoked, its cubbyhole is destroyed. It is primarily used for
**response wrapping** — a mechanism to securely transmit a secret by wrapping it in a
single-use token that only the intended recipient can unwrap:

```bash
# Wrap a secret (the output is a single-use wrapping token, not the secret itself)
bao kv get -wrap-ttl=60s -mount=secret myapp/config

# Unwrap (the recipient uses the wrapping token once to get the actual secret)
bao unwrap <wrapping-token>
```

---

### Q: What are batch tokens and when should I use them?

**A**: Batch tokens (`b.` prefix) are lightweight, encrypted blobs — not stored in the backend.
They are non-renewable and non-revocable, but have very low overhead. Use them for high-throughput
workloads (e.g., short-lived per-request tokens) where performance is critical and explicit
revocation is not needed. Service tokens (`s.` prefix) are persistent, renewable, and stored —
use them when you need renewability or need to revoke them individually.

---

## Useful Links

| Resource | URL |
|----------|-----|
| Official Website | https://openbao.org/ |
| Documentation | https://openbao.org/docs/ |
| API Documentation (v2.3.x) | https://openbao.org/api-docs/2.3.x/ |
| GitHub Repository | https://github.com/openbao/openbao |
| Helm Chart Repository | https://github.com/openbao/openbao-helm |
| Downloads | https://openbao.org/downloads/ |
| Changelog / Releases | https://github.com/openbao/openbao/releases |
| LF Edge Project Page | https://lfedge.org/projects/openbao/ |
| OpenSSF Membership | https://openbao.org/blog/openbao-joins-the-openssf/ |
| Community Discussions | https://github.com/openbao/openbao/discussions |
| Mailing List / LF Edge | https://lists.lfedge.org/g/openbao |
| FOSDEM 2025 Talk | https://openbao.org/blog/cipherboy-fosdem-25-talk/ |

---

## Sources

- https://openbao.org/docs/what-is-openbao/
- https://openbao.org/docs/concepts/seal/
- https://openbao.org/docs/concepts/tokens/
- https://openbao.org/docs/configuration/
- https://openbao.org/api-docs/2.3.x/
