# Docker Sandboxes (sbx) Runbook

A practical reference for running AI coding agents in isolated microVM sandboxes using the `sbx` CLI.

> **Note:** `sbx` is experimental software (v0.23.0 as of April 2026) distributed under a **proprietary license by Docker Inc.** A free Docker account is required to use it.

## Table of Contents

- [Installation](#installation)
- [Login and Initial Setup](#login-and-initial-setup)
- [Core Commands](#core-commands)
- [Supported Agents](#supported-agents)
- [Network Policy Management](#network-policy-management)
- [Secret Management](#secret-management)
- [Sandbox Lifecycle](#sandbox-lifecycle)
- [Fix: GitHub Copilot CLI (Individual Accounts)](#fix-github-copilot-cli-individual-accounts)
- [Fix: GitHub CLI (gh) Authentication](#fix-github-cli-gh-authentication)
- [Security Notes](#security-notes)
- [References](#references)

---

## Installation

macOS (Apple Silicon and Intel):

```bash
brew tap docker/tap
brew install docker/tap/sbx
```

Verify:

```bash
sbx version
# Client Version: v0.23.0
# Server Version: v0.23.0
```

---

## Login and Initial Setup

```bash
sbx login
```

This starts device-flow authentication (browser confirmation required), starts the background daemon, and prompts you to choose a default network policy:

| Option | Behaviour |
| :--- | :--- |
| `1` Open | All outbound traffic allowed |
| `2` Balanced | Default deny; common dev sites allowed (recommended) |
| `3` Locked Down | All traffic blocked unless explicitly allowed |

Change the policy at any time:

```bash
sbx policy reset        # re-run the interactive policy selector
sbx logout              # sign out and stop the daemon
```

---

## Core Commands

| Command | Description |
| :--- | :--- |
| `sbx run <agent> [PATH]` | Create sandbox (if needed) and attach agent interactively |
| `sbx create <agent> PATH` | Create sandbox without attaching |
| `sbx exec <name> <cmd>` | Run a command inside a sandbox |
| `sbx ls` | List all sandboxes |
| `sbx stop <name>` | Stop a sandbox without removing it |
| `sbx rm <name>` | Remove sandbox and its VM |
| `sbx reset` | Remove all sandboxes and clean up state |
| `sbx version` | Show client and server version |

Common flags for `sbx create` / `sbx run`:

| Flag | Description |
| :--- | :--- |
| `--name <name>` | Set sandbox name (default: `<agent>-<workdir>`) |
| `--memory <size>` | Memory limit, e.g. `4g`, `8g` (default: 50% of host, max 32 GiB) |
| `--branch auto` | Create a Git worktree on a new auto-named branch (safest mode) |
| `--branch <name>` | Create a Git worktree on a specific branch |
| `--template <image>` | Override the base container image |

---

## Supported Agents

| Agent | Template image |
| :--- | :--- |
| `claude` | `docker/sandbox-templates:claude-docker` |
| `codex` | `docker/sandbox-templates:codex-docker` |
| `copilot` | `docker/sandbox-templates:copilot-docker` |
| `docker-agent` | `docker/sandbox-templates:docker-agent-docker` |
| `gemini` | `docker/sandbox-templates:gemini-docker` |
| `kiro` | `docker/sandbox-templates:kiro-docker` |
| `opencode` | `docker/sandbox-templates:opencode-docker` |
| `shell` | `docker/sandbox-templates:shell-docker` |

The `copilot` template ships with: GitHub Copilot CLI v1.0.17, `gh` v2.46.0, Node.js 20, Python 3.13, Git 2.51, Docker 29.3.1.

---

## Network Policy Management

Inspect active policies:

```bash
sbx policy ls
```

Add an allow rule:

```bash
sbx policy allow network <host>          # e.g. api.example.com
sbx policy allow network '**.example.com' # double wildcard = all subdomains
```

Add a deny rule (takes precedence over allow):

```bash
sbx policy deny network <host>
```

> **Wildcard syntax:** `*` matches a single subdomain level; `**` matches multiple levels.
> Example: `*.githubcopilot.com` matches `api.githubcopilot.com` but NOT `api.individual.githubcopilot.com`. Use `**.githubcopilot.com` for the latter.

The Balanced policy ships five default categories: AI APIs, package managers, code hosting (GitHub/GitLab/registries), cloud infrastructure, and OS packages. Some rules are broad — `*.googleapis.com` and `*.amazonaws.com` wildcards cover many services. Review with `sbx policy ls` and tighten as needed.

---

## Secret Management

Secrets are stored on the host and injected by the proxy into outbound HTTP headers. The actual values never enter the VM.

```bash
sbx secret ls                          # list stored secrets
sbx secret set -g <service>            # store globally (all sandboxes)
sbx secret set <sandbox> <service>     # store for a specific sandbox
sbx secret rm <service>                # remove a secret
```

Supported services: `anthropic`, `aws`, `cursor`, `github`, `google`, `groq`, `mistral`, `nebius`, `openai`, `xai`.

Store from stdin (non-interactive, useful in scripts):

```bash
echo "$MY_API_KEY" | sbx secret set -g anthropic
gh auth token | sbx secret set -g github
```

Inside any sandbox, injected keys appear as:

```
ANTHROPIC_API_KEY=proxy-managed
OPENAI_API_KEY=proxy-managed
```

---

## Sandbox Lifecycle

Full workflow example:

```bash
# 1. Create sandbox with isolated git branch (safest for long autonomous sessions)
cd ~/my-project
sbx run claude --branch auto .

# 2. Inspect the sandbox while it runs
sbx ls
sbx exec my-sandbox sh -c "uname -a"

# 3. Stop without destroying (preserves VM state, installed packages, images)
sbx stop my-sandbox

# 4. Reattach later
sbx run my-sandbox

# 5. Destroy when done (also cleans up git worktree if --branch was used)
sbx rm my-sandbox
```

---

## Fix: GitHub Copilot CLI (Individual Accounts)

**Problem:** `sbx run copilot` fails for individual GitHub accounts with:

```
[ERROR] Error loading models: ProxyResponseError: HTTP 403 response does not appear
to originate from GitHub. Is a proxy or firewall intercepting this request?
```

**Root cause:** The Balanced policy only allows `**.business.githubcopilot.com`. Individual accounts use `api.individual.githubcopilot.com`, which is blocked.

**Fix:** Run these policy commands once (global, persists across sandboxes):

```bash
sbx policy allow network '**.githubcopilot.com'
sbx policy allow network copilot-proxy.githubusercontent.com
sbx policy allow network origin-tracker.githubusercontent.com
sbx policy allow network copilot-telemetry.githubusercontent.com
sbx policy allow network collector.github.com
sbx policy allow network default.exp-tas.com
```

Verify the policies are active:

```bash
sbx policy ls | grep githubcopilot
```

---

## Fix: GitHub CLI (gh) Authentication

**Problem:** The `gh` CLI inside a sandbox does not pick up GitHub credentials from the proxy — it checks its own config store. `gh auth status` returns "not logged in" even after `sbx secret set github`.

**Why:** The proxy injects the token into HTTP headers (so raw `curl` calls to `api.github.com` work), but `gh` CLI bypasses the proxy for its own auth checks.

**Fix — Option 1 (recommended):** Store globally and pass via env var:

```bash
gh auth token | sbx secret set -g github      # store once
TOKEN=$(gh auth token)
sbx exec -e GH_TOKEN="$TOKEN" my-sandbox sh -c "gh auth status"
```

**Fix — Option 2:** Pass inline per exec:

```bash
TOKEN=$(gh auth token)
sbx exec -e GH_TOKEN="$TOKEN" my-sandbox <command>
```

---

## Security Notes

| Layer | What is isolated | What is NOT isolated |
| :--- | :--- | :--- |
| Filesystem | Host files outside workspace; SSH keys; shell configs | Workspace dir (live read-write mount) |
| Docker | Host Docker daemon and socket | Agent has its own full Docker Engine |
| Network | Host localhost; raw TCP/UDP/ICMP; unlisted domains | HTTP/HTTPS to allow-listed domains |
| Credentials | Raw API key values (proxy-managed) | `gh` CLI token if passed via `-e GH_TOKEN` |

**Workspace trust:** Agent changes appear on your host in real time. Review Git hooks (`.git/hooks/`), `Makefile`, and CI configs after every session — especially in repos you do not fully control. Git hooks do not appear in `git diff`.

**`--branch auto` is the safest mode** for long autonomous sessions: the agent works on an isolated Git worktree and cannot touch your working branch until you explicitly merge.

**Telemetry:** `sbx` collects CLI subcommand invocations, success/failure, duration, and your Docker username. It does not read prompts or code. Opt out with:

```bash
export SBX_NO_TELEMETRY=1
```

---

## References

- [Docker Sandboxes documentation](https://docs.docker.com/ai/sandboxes)
- [sbx CLI reference](https://docs.docker.com/reference/cli/sbx/)
- [Docker Sandboxes security model](https://docs.docker.com/ai/sandboxes/security/)
- [Docker Sandboxes releases and issue tracker](https://github.com/docker/sbx-releases)
- [GitHub Copilot firewall domains](https://gh.io/copilot-firewall)
