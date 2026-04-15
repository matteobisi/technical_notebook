# Product Documentation

Standardized, source-backed documentation for DevSecOps tools and products.
Content is generated from official sources by AI agents following the rules in
[`AGENTS.md`](../AGENTS.md). All pages cite their sources and do not invent content.

---

## Products

| Product | Description | Version | Last Updated |
|---------|-------------|---------|--------------|
| [OpenBao](./openbao/README.md) | Identity-based secrets and encryption management (LF Edge) | v2.3.x | 2026-04-15 |

---

## How to add a new product

Tell the agent:

> "Add docs for `<product>` from `<URL1>`, `<URL2>`, ..."

The agent will:
1. Copy `_template/` to `docs/<product>/`.
2. Fill in `docs/<product>/AGENTS.md` — per-page source URLs, release tracking, custom sections.
3. Populate all pages from the source URLs.
4. Add the product to this index and to `technical_notebook/README.md`.

---

## How to update an existing product

Tell the agent:

> "Update docs for `<product>`"  
> or: "Refresh `<product>` docs"

The agent will:
1. Read `docs/<product>/AGENTS.md` for the per-page source URL mapping.
2. Re-fetch every listed URL.
3. Regenerate sections where content has changed; leave unchanged sections as-is.
4. Update `last_updated` and `version` in `docs/<product>/README.md`.
5. If the official docs added new major sections with no matching page, create it and add it to the product index.

---

## How to add a custom section to an existing product

Edit `docs/<product>/AGENTS.md` and add an entry under `## Custom Sections`:

```markdown
### my-custom-page.md
**Description**: What this section covers and why it is specific to this product.
**Sources**:
  - https://...
```

Then tell the agent:

> "Create the `my-custom-page` section for `<product>`"

The agent will create the page from the listed sources and add it to `docs/<product>/README.md`.

---

## How to customize which sections a product has

Each product's `docs/<product>/AGENTS.md` is the single operational spec for that product.
It defines:
- **Standard sections** (overview, architecture, installation, configuration, use-cases,
  api-cli-reference, faq) — present in every product.
- **Custom sections** — product-specific pages added below the standard ones.
- **Release tracking** — where to find the current version and changelog.
- **Update notes** — product-specific quirks agents must follow (e.g., CLI binary name, path semantics).

To see what a product currently defines, read its `AGENTS.md`:

```
docs/<product>/AGENTS.md
```

The base template for new products is at [`_template/`](./_template/). It contains the
`AGENTS.md` template and all 8 standard page files.

---

## Layered AGENTS.md model

```
technical_notebook/AGENTS.md      ← global rules and protocols
docs/_template/AGENTS.md          ← base contract (standard sections template)
docs/<product>/AGENTS.md          ← product spec (sources + custom sections)
```

Agents always read the product-level `AGENTS.md` first when working on any product directory.

