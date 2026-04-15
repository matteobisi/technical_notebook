# technical_notebook — Agent Instructions

This file governs how AI agents work in this repository.

---

## General Rules

- **No invention**: Only write content that can be verified from the provided source URLs. If information is missing or unclear, omit it rather than guess.
- **Cite sources**: Every documentation page must end with a `## Sources` section listing the full URLs used to produce that page.
- **Verified content**: All commands, configurations, and code examples must be sourced directly from official documentation. Do not paraphrase in a way that changes meaning.
- **Mermaid diagrams**: Required in `architecture.md` pages (dev/prod/HA topology). Encouraged anywhere a flow, sequence, or component relationship adds clarity. Use `mermaid` code blocks.
- **No marketing language**: Focus on technical facts. Avoid superlatives and promotional framing.
- **Language**: All documentation is written in English.

---

## `docs/` Section

The `docs/` directory contains standardized, AI-assisted, source-backed documentation for
DevSecOps tools and products. Each product lives in its own subdirectory and follows the
canonical template at `docs/_template/`.

### Directory layout

```
docs/
├── README.md              # section index — list all products
├── _template/             # canonical base template (never edit directly)
│   ├── AGENTS.md          # template product spec — copy and fill for each new product
│   ├── README.md
│   ├── overview.md
│   ├── architecture.md
│   ├── installation.md
│   ├── configuration.md
│   ├── use-cases.md
│   ├── api-cli-reference.md
│   └── faq.md
└── <product>/             # one directory per product
    ├── AGENTS.md          # product spec: per-page sources, custom sections, update notes
    ├── README.md          # human navigation index only
    ├── overview.md
    ├── architecture.md
    ├── installation.md
    ├── configuration.md
    ├── <product-specific pages...>
    ├── use-cases.md
    ├── api-cli-reference.md
    └── faq.md
```

### Layered AGENTS.md model

Agent instructions follow a three-layer hierarchy:

| Layer | File | Scope |
|-------|------|-------|
| Repo | `technical_notebook/AGENTS.md` | Global rules, protocols, commit conventions |
| Template | `docs/_template/AGENTS.md` | Base contract: 8 standard sections |
| Product | `docs/<product>/AGENTS.md` | Per-page source URLs + custom section definitions |

**When working on any product**, agents must read `docs/<product>/AGENTS.md` first. It is the
single operational source of truth for that product: which pages exist, which URLs feed each
page, what custom sections are defined, and any product-specific update instructions.

Custom sections (pages beyond the 8-page base template) are defined exclusively in the
product `AGENTS.md`. They are added when the product has domain-specific concepts that do not
map to the base template (e.g., `secrets-lifecycle.md` for a secrets manager, `policies.md`
for an access control system).

---

## Protocols

### Update docs for a product

**Trigger**: User says "update docs for `<product>`" or "refresh `<product>` docs".

Steps:
1. Read `docs/<product>/AGENTS.md` to find the per-page source URL mapping for every section
   (both standard and custom).
2. Re-fetch each listed source URL.
3. Compare the fetched content against each existing page.
4. Regenerate sections where content has changed; leave unchanged sections as-is.
5. Update the `last_updated` and `version` fields in `docs/<product>/README.md`.
6. If new major sections exist in the official docs that have no corresponding page, add a new
   custom section entry to `docs/<product>/AGENTS.md`, create the page, and add it to the
   product `README.md` index.
7. Commit with message: `docs(<product>): update to vX.Y.Z` (or `latest` if version unknown).

### Add docs for a new product

**Trigger**: User says "add docs for `<product>` from `<URL1>`, `<URL2>`, ...".

Steps:
1. Copy `docs/_template/` to `docs/<product-name>/`.
2. Fill in `docs/<product>/AGENTS.md`: add source URLs per standard section, add custom sections
   as needed, fill in release tracking URLs.
3. Populate each page from the source URLs defined in `docs/<product>/AGENTS.md`.
4. Add the product to `docs/README.md` (section index).
5. Add the product to the main `technical_notebook/README.md` under "Product Documentation".
6. Commit with message: `docs(<product>): initial documentation`.

---

## Commit conventions

- `docs(<product>): initial documentation` — first creation of a product's docs
- `docs(<product>): update to vX.Y.Z` — content refresh after a new release
- `docs: add <product> to index` — index-only changes
- `docs(template): <description>` — changes to the base template
- All commits must be signed off: `git commit --signoff`
- Do not add AI or Copilot as co-author unless explicitly asked
