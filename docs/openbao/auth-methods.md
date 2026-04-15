# OpenBao — Auth Methods

Auth methods perform authentication and assign identity (token + policies) to clients. OpenBao
supports multiple concurrent auth methods, each mounted at a path under `auth/`.

```bash
# Enable an auth method
bao auth enable approle

# Enable at a custom path
bao auth enable -path=my-approle approle

# List enabled auth methods
bao auth list

# Disable an auth method (all authenticated users are logged out)
bao auth disable approle
```

There are two authentication flows:
- **Standard**: client calls the login endpoint, gets a token, uses it in subsequent requests.
- **Inline**: authentication headers are sent with each request; no persistent token is created
  (better for high-throughput, stateless workloads).

---

## AppRole — Machine / Service Authentication

Designed for automated workflows (services, CI/CD pipelines). Credentials are a `role_id`
(non-secret, identifies the role) and a `secret_id` (secret, one-time or TTL-limited).

### Configure

```bash
# Enable
bao auth enable approle

# Create a role
bao write auth/approle/role/my-role \
  secret_id_ttl=10m \
  token_num_uses=10 \
  token_ttl=20m \
  token_max_ttl=30m \
  secret_id_num_uses=40 \
  token_policies="my-policy"

# Retrieve the role_id (distribute to your service)
bao read auth/approle/role/my-role/role-id

# Generate a secret_id (generated at deployment time, kept secret)
bao write -f auth/approle/role/my-role/secret-id
```

### Authenticate

```bash
bao write auth/approle/login \
  role_id=<role_id> \
  secret_id=<secret_id>
# Returns a token
```

```bash
# API equivalent
curl --request POST \
  --data '{"role_id":"<role_id>","secret_id":"<secret_id>"}' \
  http://openbao:8200/v1/auth/approle/login
```

### Pull vs Push SecretID mode

| Mode | Description | When to use |
|------|-------------|-------------|
| **Pull** (default) | SecretID is fetched from OpenBao by an authorized deployer and handed to the app | Most cases; most secure |
| **Push** | Client supplies its own SecretID | Legacy App-ID compatibility |

> **Security pattern**: use Pull mode with [Response Wrapping](/docs/concepts/response-wrapping/)
> so that even the deployer never sees the SecretID in plain text.

---

## Kubernetes — Pod Authentication

Allows Kubernetes pods to authenticate using their ServiceAccount JWT token. OpenBao verifies
the JWT against the Kubernetes TokenReview API.

### Configure

```bash
bao auth enable kubernetes

# Configure OpenBao to talk to Kubernetes
bao write auth/kubernetes/config \
  kubernetes_host="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
  # token_reviewer_jwt omitted: OpenBao uses its own pod's SA token

# Create a role
bao write auth/kubernetes/role/myapp \
  bound_service_account_names=myapp \
  bound_service_account_namespaces=default \
  policies=myapp-policy \
  ttl=1h
```

### Authenticate (from a Pod)

```bash
JWT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
bao write auth/kubernetes/login \
  role=myapp \
  jwt=$JWT
```

> **Kubernetes 1.21+**: set `disable_iss_validation=true` (it is the default) because pod tokens
> are short-lived and bound to the pod lifecycle. Consider using OpenBao's own SA token as the
> reviewer JWT to handle token rotation automatically.

---

## JWT / OIDC — Workload and Human Authentication

The `jwt` auth method supports both static JWTs (for CI/CD systems like GitHub Actions, GitLab)
and the OIDC authorization code flow (for human operators).

```bash
bao auth enable jwt

# Configure with an OIDC provider (e.g., Keycloak)
bao write auth/jwt/config \
  oidc_discovery_url="https://keycloak.example.com/realms/myrealm" \
  oidc_client_id="openbao" \
  oidc_client_secret="<secret>" \
  default_role="reader"

# Create a role
bao write auth/jwt/role/reader \
  bound_audiences="openbao" \
  user_claim="sub" \
  policies="reader-policy" \
  ttl=1h

# Login via OIDC (opens browser)
bao login -method=oidc role=reader
```

For CI/CD JWT (e.g., GitHub Actions):

```bash
bao write auth/jwt/config \
  jwks_url="https://token.actions.githubusercontent.com/.well-known/jwks" \
  bound_issuer="https://token.actions.githubusercontent.com"

bao write auth/jwt/role/github-actions \
  role_type=jwt \
  bound_claims='{"repository":"myorg/myrepo"}' \
  user_claim=repository \
  policies=ci-policy \
  ttl=15m
```

---

## LDAP — Directory Authentication

Authenticates users against an LDAP or Active Directory server.

```bash
bao auth enable ldap

bao write auth/ldap/config \
  url="ldaps://ldap.example.com" \
  userdn="ou=users,dc=example,dc=com" \
  groupdn="ou=groups,dc=example,dc=com" \
  groupattr="cn" \
  binddn="cn=vault,dc=example,dc=com" \
  bindpass="ldap-password" \
  userattr="uid" \
  certificate=@/etc/openbao/ldap-ca.crt

# Map an LDAP group to a policy
bao write auth/ldap/groups/ops policies=ops-policy

# Login
bao login -method=ldap username=john.doe
```

---

## Token — Direct Token Management

The `token` auth method is always enabled and cannot be disabled. It is the underlying mechanism
for all authentication in OpenBao; other auth methods ultimately create tokens via the token store.

```bash
# Create a token with a specific policy and TTL
bao token create \
  -policy=my-policy \
  -ttl=1h \
  -display-name="my-service"

# Create an orphan token (no parent; not revoked when parent expires)
bao token create -orphan -policy=my-policy

# Renew a token
bao token renew <token>

# Revoke a token and all its children
bao token revoke <token>

# Look up token metadata
bao token lookup <token>
```

Token types:

| Type | Prefix | Characteristics |
|------|--------|-----------------|
| Service | `s.` | Persistent, renewable, stored in backend |
| Batch | `b.` | Ephemeral, non-renewable, high performance, not stored |

---

## Userpass — Username/Password (Human Operators)

Simple username/password authentication. Best for developer machines.

```bash
bao auth enable userpass

# Create a user
bao write auth/userpass/users/john \
  password=changeme \
  policies=developer-policy

# Login
bao login -method=userpass username=john
```

---

## TLS Certificates

Authenticates clients using TLS client certificates.

```bash
bao auth enable cert

bao write auth/cert/certs/my-cert \
  display_name="my-service" \
  policies=my-policy \
  certificate=@/etc/openbao/client-ca.crt \
  ttl=3600

# Login (provide client cert and key to curl/bao)
bao login -method=cert -client-cert=client.crt -client-key=client.key
```

---

## Sources

- https://openbao.org/docs/auth/
- https://openbao.org/docs/auth/approle/
- https://openbao.org/docs/auth/kubernetes/
- https://openbao.org/api-docs/2.3.x/auth/
