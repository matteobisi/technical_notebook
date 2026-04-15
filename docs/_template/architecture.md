# Architecture

## Component Overview

<!-- Brief description of the main components and how they interact. -->

## Development Deployment

<!-- Single-node, no persistence, for local testing only. -->

```mermaid
graph TD
    Client --> Server["Server (dev mode)"]
    Server --> Memory["In-Memory Storage"]
```

## Production Deployment

<!-- Single-node production setup with persistent storage. -->

```mermaid
graph TD
    Client --> Server
    Server --> Storage["Persistent Storage"]
```

## High Availability (HA)

<!-- Multi-node cluster for fault tolerance. -->

```mermaid
graph TD
    LB["Load Balancer"] --> Active
    LB --> Standby1
    LB --> Standby2
    Active <-->|Replication| Standby1
    Active <-->|Replication| Standby2
    Active --> Storage[(Storage Backend)]
    Standby1 --> Storage
    Standby2 --> Storage
```

## Data Flow

<!-- How a typical request flows through the system. -->

---

## Sources

- `<source URL>`
