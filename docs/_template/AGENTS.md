# <Product Name> — Documentation Spec

> Copy this file to `docs/<product-name>/AGENTS.md` and fill in every placeholder.
> Remove this instruction block once the file is complete.
> This file is the **single source of truth** agents read before working on this product.
> Repo-level rules are in `../../AGENTS.md`.

---

## Release Tracking

- **version_check_url**: <!-- e.g. https://github.com/<org>/<repo>/releases/latest -->
- **changelog_url**: <!-- e.g. https://github.com/<org>/<repo>/blob/main/CHANGELOG.md -->
- **version**: <!-- current tracked version, e.g. v2.3.x -->

---

## Standard Sections

These 8 pages are required for every product. Fill in the source URLs that feed each page.
Multiple URLs are allowed — list the most specific and authoritative ones first.

### overview.md

**Description**: What the product is, why it exists, system requirements, key concepts and
terminology the reader needs before going deeper.

**Sources**:
- <!-- URL: product home page or "what is X" documentation page -->

---

### architecture.md

**Description**: Internal components, data flow between layers, and deployment topologies
(dev/single-node, production, high availability). Mermaid diagrams are **required**.

**Sources**:
- <!-- URL: architecture or internals documentation -->

---

### installation.md

**Description**: Installing the product via package managers, container images, binary
download, and Kubernetes/Helm. Cover both Linux and container-based paths at minimum.

**Sources**:
- <!-- URL: official install guide -->

---

### configuration.md

**Description**: Configuration file reference and annotated real-world examples covering the
most important options (storage, networking, TLS, logging).

**Sources**:
- <!-- URL: configuration reference -->

---

### use-cases.md

**Description**: Practical end-to-end scenarios showing how the product solves real problems.
Each scenario must include commands and a Mermaid sequence or flow diagram.

**Sources**:
- <!-- URL: use cases, tutorials, or getting-started guide -->

---

### api-cli-reference.md

**Description**: Key CLI commands and HTTP API endpoints with usage examples. Only the most
commonly used operations — not a full reference dump.

**Sources**:
- <!-- URL: API reference -->
- <!-- URL: CLI reference -->

---

### faq.md

**Description**: Common questions, troubleshooting steps, and useful links (official site,
GitHub repo, documentation, community forum or chat).

**Sources**:
- <!-- URL: FAQ, troubleshooting, or community page -->

---

## Custom Sections

Add product-specific pages here. These are pages that go beyond the standard 8-page base
because the product has domain-specific concepts that deserve dedicated coverage.

Remove the example entry below and replace with real custom sections, or delete this block
entirely if no custom sections are needed.

### example-custom-page.md

**Description**: <!-- What this page covers and why it is specific to this product.
Be explicit: what sub-topics are in scope, what is intentionally out of scope. -->

**Sources**:
- <!-- URL -->

---

## Update Notes

<!-- Product-specific instructions agents must follow during an update cycle:
- How to determine the current version (GitHub releases? Docs header? Package metadata?)
- Any naming differences (e.g., CLI binary name differs from product name)
- Sections that are stable vs. sections that change frequently with releases
- Any sources that require authentication or are behind a paywall (skip those)
- Known gotchas or things that differ from similar products
-->
