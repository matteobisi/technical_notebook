# OpenBao — Architecture

## Internal Components

OpenBao is composed of several distinct layers. From the outside in:

```mermaid
graph TB
    subgraph Clients
        UI["Web UI"]
        CLI["bao CLI"]
        API["HTTP API"]
    end

    subgraph Core["OpenBao Core"]
        Router["Router"]
        ACL["ACL Engine"]
        TokenStore["Token Store"]
        PolicyStore["Policy Store"]
        ExpMgr["Expiration Manager"]
        AuditBroker["Audit Broker"]

        subgraph Plugins["Plugins (mounted paths)"]
            AuthMethods["Auth Methods\n(approle, k8s, jwt…)"]
            SecretsEngines["Secrets Engines\n(kv, pki, transit…)"]
            SysBackend["sys/ backend"]
        end
    end

    subgraph Barrier["Encryption Barrier (AES-GCM)"]
        Storage["Storage Backend\n(Raft / Consul / File)"]
    end

    subgraph AuditDevices["Audit Devices"]
        FileAudit["File"]
        SyslogAudit["Syslog"]
    end

    Clients --> Router
    Router --> ACL
    ACL --> TokenStore
    ACL --> PolicyStore
    Router --> Plugins
    Plugins --> ExpMgr
    ExpMgr --> Barrier
    Router --> AuditBroker
    AuditBroker --> AuditDevices
    Barrier --> Storage
```

Key points from the official architecture documentation:

- The **barrier** encrypts all data before it reaches the storage backend. The storage backend is
  considered *untrusted*.
- When OpenBao starts it is **sealed**: it knows where storage is but cannot decrypt it. The root
  key must be provided via unseal shares before any operation is possible.
- **Auth methods** validate identity and return a set of applicable policies. A token is then
  generated and managed by the **token store**.
- **Secrets engines** receive a *barrier view* (scoped to a random UUID prefix) — they can only
  read/write their own data, not data from other engines.
- The **expiration manager** handles lease TTLs and automatically revokes secrets whose leases
  expire.
- Every request and response passes through the **audit broker**, which distributes logs to all
  configured audit devices.

---

## Development Deployment

For local testing only. Uses in-memory storage; data is lost on restart. The server
auto-initializes and auto-unseals. Do not use in production.

```mermaid
graph LR
    Developer -->|bao CLI / HTTP| DevServer["bao server -dev\n(127.0.0.1:8200)"]
    DevServer --> InMemory["In-Memory Storage\n(Raft embedded)"]
```

```bash
# Start a dev server (auto-unsealed, root token printed to stdout)
bao server -dev
export BAO_ADDR='http://127.0.0.1:8200'
export BAO_TOKEN='<root token from output>'
bao status
```

---

## Production Deployment (Single Node)

A single node with persistent Raft storage. Suitable for low-scale or non-critical environments.

```mermaid
graph TD
    Clients["Clients\n(UI / CLI / API)"] -->|HTTPS :8200| Node["OpenBao Node\n(bao server)"]
    Node --> Barrier["Encryption Barrier"]
    Barrier --> Raft["Integrated Storage\n(Raft — local disk)"]
    Node --> AuditFile["Audit Log\n(/var/log/openbao/audit.log)"]
```

Lifecycle:
1. Start `bao server -config=/etc/openbao/config.hcl`
2. Run `bao operator init` (once) — generates unseal keys and initial root token.
3. Run `bao operator unseal` (3× by default with threshold=3) after each restart.

---

## High Availability (HA) with Integrated Raft Storage

The recommended production topology. One active node handles all write requests; standby nodes
forward writes to the active node and can serve read requests (if `disable_standby_reads = false`).

```mermaid
graph TD
    Clients["Clients\n(UI / CLI / API)"]
    LB["Load Balancer\n(:8200)"]

    subgraph Cluster["OpenBao HA Cluster (3 or 5 nodes)"]
        Active["Active Node\n(leader)"]
        Standby1["Standby Node 1"]
        Standby2["Standby Node 2"]
    end

    RaftLog[("Raft Log\n(replicated)")]
    AuditDevices["Audit Devices"]

    Clients --> LB
    LB --> Active
    LB --> Standby1
    LB --> Standby2

    Standby1 -->|"forward writes"| Active
    Standby2 -->|"forward writes"| Active

    Active <-->|"Raft replication"| Standby1
    Active <-->|"Raft replication"| Standby2
    Standby1 <-->|"Raft replication"| Standby2

    Active --> RaftLog
    Standby1 --> RaftLog
    Standby2 --> RaftLog

    Active --> AuditDevices
```

Requirements for HA with Raft:
- Odd number of nodes (3 or 5) to maintain quorum.
- Each node must be able to reach the others on the Raft cluster address (default `:8201`).
- All nodes share the same `cluster_addr` advertised address configuration.
- Each node needs its own data directory (not shared).

### Failure scenarios

| Scenario | Behaviour |
|----------|-----------|
| Active node dies | Raft elects a new leader from standbys; service interruption < 30 s |
| Standby node dies | Cluster remains operational as long as quorum (N/2+1) is maintained |
| Split brain (network partition) | Minority partition becomes unavailable; majority continues |

---

## Kubernetes Deployment

OpenBao can be deployed on Kubernetes using the official Helm chart. The recommended pattern
uses the Vault Agent Injector sidecar for secret injection into Pods.

```mermaid
graph TD
    subgraph Kubernetes Cluster
        subgraph openbao-ns["Namespace: openbao"]
            BAO["OpenBao StatefulSet\n(HA Raft, 3 pods)"]
            Injector["Agent Injector\n(MutatingWebhook)"]
        end

        subgraph app-ns["Namespace: app"]
            Pod["Application Pod"]
            Agent["bao agent sidecar\n(auto-injected)"]
        end
    end

    KubeAPI["Kubernetes API\n(TokenReview)"]

    Pod <-->|"secret files\n(/vault/secrets/)"| Agent
    Agent -->|"Kubernetes auth\n(ServiceAccount JWT)"| BAO
    BAO -->|"verify JWT"| KubeAPI
    Injector -->|"mutate Pod spec"| Pod
```

---

## Sources

- https://openbao.org/docs/internals/architecture/
- https://openbao.org/docs/concepts/seal/
- https://openbao.org/docs/configuration/
- https://openbao.org/docs/platform/k8s/helm/
