# Docker Agent Runbook

A hands-on walkthrough of `docker agent`: defining agents in YAML, running them against a local model through Docker Model Runner, wiring multi-agent teams, distributing definitions as OCI artefacts, and running evaluations as a regression gate. Commands and outputs come from a verified test journal, not from the docs.

Everything here was executed on a MacBook (Apple Silicon, macOS) against **Docker Desktop 4.92.0**, **Docker Engine 29.8.0**, **Docker Agent v1.140.0**, using Docker Model Runner on the llama.cpp Metal backend with `qwen3` 8.19B (IQ2_XXS, 4.68 GiB) and no cloud credentials configured. The current upstream release at the time of writing is v1.145.0. Re-verify with `docker agent version` before trusting any command here.

The companion proof of concept with the runnable example definitions lives at [github.com/matteobisi/POC-docker-agent](https://github.com/matteobisi/POC-docker-agent). The full test journal, including failed experiments, is in [`NOTES.md`](https://github.com/matteobisi/POC-docker-agent/blob/main/NOTES.md).

## Table of Contents

- [What Docker Agent is](#what-docker-agent-is)
- [Naming history](#naming-history)
- [Installation](#installation)
- [Verify the environment](#verify-the-environment)
- [Set up a local model](#set-up-a-local-model)
- [Write and validate an agent](#write-and-validate-an-agent)
- [Run a single agent](#run-a-single-agent)
- [Build a multi-agent team](#build-a-multi-agent-team)
- [Toolsets](#toolsets)
- [Distribute agents as OCI artefacts](#distribute-agents-as-oci-artefacts)
- [Tool approval and safety modes](#tool-approval-and-safety-modes)
- [Permissions](#permissions)
- [Lifecycle hooks](#lifecycle-hooks)
- [Evaluations](#evaluations)
- [Validate definitions in CI](#validate-definitions-in-ci)
- [Run the agent behind an API](#run-the-agent-behind-an-api)
- [Secrets](#secrets)
- [Gotchas](#gotchas)
- [What is not provided](#what-is-not-provided)
- [Sources](#sources)

---

## What Docker Agent is

Docker Agent is an open-source framework for defining and running teams of AI agents. An agent is a YAML file, not application code. The definition carries the model, the instruction, the tools, and any sub-agent delegation:

```yaml
agents:
  root:
    model: dmr/ai/qwen3
    description: A helpful coding assistant
    instruction: |
      You are an expert software developer. Help users write
      clean, efficient code. Explain your reasoning.
    toolsets:
      - type: filesystem
      - type: shell
      - type: think
```

Because the definition is a reviewable artefact, changing a model, widening tool access, or tightening an agent's instructions is a diff in a pull request rather than a code change. Definitions can also be pushed to an OCI registry and run by reference, the same way container images are.

## Naming history

- The project was called **cagent** in Docker Desktop 4.49 through 4.62, and was renamed to **Docker Agent** in 4.63. The internal config and data directories are still `~/.config/cagent` and `~/.cagent`.
- Docker Agent is **not** Gordon, Docker's built-in assistant exposed as `docker ai`.
- `docker agent` may resolve to two different binaries. The plugin bundled with Docker Desktop lives at `~/.docker/cli-plugins/docker-agent`, and a separate Homebrew binary may be at `/opt/homebrew/bin/docker-agent`. Both were present on the test machine at different versions (v1.140.0 and 1.143.0). Record which one was actually tested with `docker agent version`.

## Installation

Starting with Docker Desktop 4.63, Docker Agent is bundled. Nothing to install:

```bash
docker agent version
# v1.140.0
```

Standalone, on macOS or Linux:

```bash
brew install docker-agent
docker-agent version
```

Or download a release binary. Installing it as a CLI plugin makes `docker agent` work:

```bash
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m); case "$ARCH" in x86_64) ARCH=amd64;; aarch64) ARCH=arm64;; esac
curl -L "https://github.com/docker/docker-agent/releases/latest/download/docker-agent-${OS}-${ARCH}" -o docker-agent
chmod +x docker-agent
mkdir -p ~/.docker/cli-plugins
mv docker-agent ~/.docker/cli-plugins
docker agent version
```

On Windows, download `docker-agent-windows-amd64.exe` from the releases page, rename it to `docker-agent.exe`, and add it to `PATH` or to `~/.docker/cli-plugins`.

Binary installs can self-update, which is off by default. When enabled, a newer release is downloaded, checksum-verified, and the command restarts. In a non-interactive context such as CI, the update proceeds without asking:

```bash
export DOCKER_AGENT_AUTO_UPDATE=1
```

## Verify the environment

`doctor` reports which providers have credentials, whether Model Runner is reachable, and which model `auto` resolves to:

```bash
docker agent doctor
```

It exits non-zero when a run would be blocked, which makes it usable as a CI preflight. Verified both ways: exit 0 on a working setup, exit 1 with `no usable model: no provider credential was found and Docker Model Runner is unreachable` when the model endpoint is pointed at a dead port.

## Set up a local model

With Docker Model Runner enabled (Docker Desktop Settings, AI):

```bash
docker model pull ai/qwen3
docker model ls
docker model status
```

Local models are referenced with the `dmr/` prefix, for example `dmr/ai/qwen3`. With no cloud credentials configured, `auto` resolution falls back to a locally pulled Model Runner model. Confirm what it picked:

```bash
docker agent models
```

The `token_usage` event in `--json` output is the check that inference is local and free. It reports the model and a cost of zero:

```json
{"type":"token_usage","cost":0,"Model":"dmr/ai/qwen3"}
```

## Write and validate an agent

Create `agent.yaml`, then validate it without executing anything:

```bash
docker agent run --dry-run agent.yaml
# Dry run mode enabled. Agent initialized but will not execute.
```

`--dry-run` also catches configuration errors, not just schema problems. Verified failure cases:

```bash
# dangling sub-agent reference
# agent 'root' references non-existent sub-agent 'does_not_exist'   (exit 1)

# type error
# toolsets: 42                                                     (exit 1)
```

Validate every definition in a directory:

```bash
for f in examples/*.yaml; do
  printf '%s: ' "$f"
  docker agent run --dry-run "$f" >/dev/null 2>&1 && echo OK || echo FAIL
done
```

`docker agent new` scaffolds a config interactively, but see [Gotchas](#gotchas) before scripting it.

## Run a single agent

```bash
# Interactive TUI
docker agent run examples/01-single-agent.yaml

# One-shot, non-interactive
docker agent run --exec examples/01-single-agent.yaml \
  "List the files here and tell me in one sentence what this folder is for."
```

`--json` emits a newline-delimited event stream, which is what to use when parsing output:

```bash
docker agent run --exec --json examples/01-single-agent.yaml "Run 'uname -sm' and report exactly what it prints."
```

Observed event types: `agent_choice` token deltas, `message_added`, `token_usage`, `stream_stopped`.

## Build a multi-agent team

Sub-agents are declared with `sub_agents`. The `transfer_task` tool is auto-enabled, which is how a lead delegates:

```yaml
agents:
  lead:
    model: dmr/ai/qwen3
    description: Tech lead that coordinates a developer and a security reviewer.
    instruction: |
      You are a pragmatic tech lead. For any coding request:
        1. Delegate the implementation to the `developer`.
        2. Send the developer's code to the `security_reviewer`.
        3. If the reviewer finds issues, ask the developer to fix them.
        4. Present the final, reviewed code and a one-line security summary.
      Do not write code yourself; coordinate the specialists.
    sub_agents:
      - developer
      - security_reviewer
    toolsets:
      - type: think

  developer:
    model: dmr/ai/qwen3
    description: Writes clean, working code.
    instruction: |
      You are a senior developer. Write correct, minimal code for the task.
      When asked to fix review findings, apply the fix and explain what changed.
    toolsets:
      - type: filesystem
      - type: shell
      - type: think

  security_reviewer:
    model: dmr/ai/qwen3
    description: Reviews code for security problems (a devsecops gate).
    instruction: |
      You are a security reviewer. Inspect code for vulnerabilities such as
      path traversal, injection, unsafe deserialization, secrets in code, and
      missing input validation. Report concrete findings with severity and a
      suggested fix. If the code is safe, say so explicitly.
    toolsets:
      - type: filesystem
```

```bash
docker agent run --exec examples/02-multi-agent-team.yaml \
  "Write a Python function that reads a file whose path comes from user input and returns its text. Get it security-reviewed before you finalize."
```

Observed flow: the lead transferred the task to the developer, which wrote a `read_file_content` function with error handling but no path validation; the lead passed the code to the security reviewer, which flagged a path traversal issue with severity and a fix; the lead returned a hardened version using `os.path.abspath` confined to a base directory, plus a security summary.

Run a single member of the team with `-a`:

```bash
docker agent run examples/02-multi-agent-team.yaml --agent security_reviewer
```

Continue a previous session by ID or relative offset:

```bash
docker agent run --session -1 examples/02-multi-agent-team.yaml
```

Isolate changes in a fresh git worktree instead of the working checkout:

```bash
docker agent run -w --worktree=my-change examples/02-multi-agent-team.yaml
```

**Cost and iteration budget.** The delegation chain is the cost driver, since every hop is a separate model turn. Measured on the 8B local model, a single-agent directory summary took 25 seconds while the three-agent team took 5 minutes 16 seconds. Runs default to `--max-iterations 20`; keep tasks scoped or raise it deliberately.

## Toolsets

Toolsets are granted per agent under `toolsets`, and each entry is a `type` with optional settings. Verified working locally: `filesystem`, `shell`, `think`.

| Type | Purpose |
| :--- | :--- |
| `filesystem` | Read, write, list, search, navigate |
| `shell` | Execute shell commands |
| `think` | Reasoning scratchpad |
| `memory` | Persistent key-value storage in SQLite |
| `mcp` | Containerized third-party tools via the Docker MCP Gateway |
| `plan` | Shared persistent scratchpad for multi-agent collaboration |
| `git` | Read-only repository inspection |

Persistent memory, with the database path resolved relative to the config file:

```yaml
toolsets:
  - type: memory
    path: ./memory.db
```

A containerized MCP tool, with no local install required. Docker Desktop pulls and runs the image:

```yaml
toolsets:
  - type: mcp
    ref: docker:duckduckgo
```

Useful MCP properties: `ref` is a `docker:name` catalog reference, `tools` limits which tools are exposed, `config` passes server-specific settings, and `instruction` injects custom context. The full catalog is browsable at [hub.docker.com](https://hub.docker.com/search?q=&type=mcp).

Verified end to end: a local model called a containerized `duckduckgo` search, got a real result, then persisted it through the `memory` tool into a local SQLite file. Git-ignore `*.db`.

## Distribute agents as OCI artefacts

```bash
# publish
docker agent share push ./agent.yaml docker.io/username/my-agent:latest
docker agent share push ./agent.yaml ghcr.io/username/my-agent:v1.0

# fetch without running
docker agent share pull docker.io/username/my-agent:latest

# run directly from a registry
docker agent run docker.io/username/my-agent:latest

# override the model at run time
docker agent run docker.io/username/my-agent:latest --model dmr/ai/qwen3
```

Any OCI-compatible registry works, including Docker Hub and GitHub Container Registry. Tag a known-good version and run it by tag for rollback.

Pre-built agents are published under the `agentcatalog` namespace:

```bash
docker agent run agentcatalog/pirate
docker agent run agentcatalog/coder
```

A registry agent can also be referenced as a `sub_agents` entry, so a team can be assembled from definitions maintained elsewhere.

> **Tested:** the pull and run-from-registry paths were exercised against a local model (exit 0, real in-character response, roughly 10 seconds). Pushing to a private registry was not tested, so treat `share push` with your own registry as unverified until you run it.

## Tool approval and safety modes

`--safety` sets how tool calls are approved. There are four levels:

| Mode | Behaviour | Use for |
| :--- | :--- | :--- |
| `strict` | Ask for every tool call | Interactive work with a human present to approve. Blocks forever without a TTY. |
| `balanced` | Auto-approve safe calls. **This is the default.** | Interactive work. Not a boundary. |
| `restricted` | Auto-approve safe calls, deny the rest | Unattended and CI runs. |
| `autonomous` | Approve everything | Trusted, isolated runs only. |

`--yolo` is shorthand for `--safety autonomous`.

**The default is `balanced`, not `strict`, and this matters more than it sounds.** In a non-interactive `--exec` run the agent does not stop and ask. Verified on v1.140.0: an `--exec` run with a `filesystem` agent and no `--yolo` completed normally with the tool call auto-approved, while the same command under `--safety strict` hung indefinitely in a non-TTY shell, still running after 60 seconds and killed manually. There is no timeout and no non-interactive fallback.

The practical consequence is that an agent holding `shell` access runs commands unattended unless a flag says otherwise. For any scheduled or automated run, pass the mode explicitly:

```bash
docker agent run --exec --safety restricted agent.yaml "your task"
```

## Permissions

`--safety` is the coarse runtime switch. Fine-grained per-tool control lives in a `permissions:` section, evaluated in the order **deny, then allow, then ask**. Anything that matches no pattern falls through to asking.

```yaml
agents:
  root:
    model: dmr/ai/qwen3
    description: Agent with permission controls
    instruction: You are a helpful assistant.

permissions:
  allow:
    - "read_file"
    - "read_*"
    - "shell:cmd=ls*"
  ask:
    - "shell:cmd=git push*"
    - "write_file:path=/home/user/important/*"
  deny:
    - "shell:cmd=sudo*"
    - "shell:cmd=rm*-rf*"
```

Patterns support globs and argument matching. The same block works at user level in `~/.config/cagent/config.yaml` under `settings.permissions`, in which case it applies to every agent run on that machine, and both levels are merged at startup:

```yaml
# ~/.config/cagent/config.yaml
settings:
  permissions:
    deny:
      - "shell:cmd=sudo*"
      - "shell:cmd=rm*-rf*"
    allow:
      - "read_*"
```

## Lifecycle hooks

Hooks run shell commands at defined points in a session, which is the place to enforce policy on every tool call rather than relying on the model's judgement. As CLI flags on `docker agent run`:

| Flag | Fires |
| :--- | :--- |
| `--hook-pre-tool-use` | Before a tool call executes. Can block. |
| `--hook-post-tool-use` | After a tool completes, success or failure. Can block. |
| `--hook-session-start` | When a session begins or resumes. |
| `--hook-session-end` | When a session terminates. |
| `--hook-stop` | When the model finishes responding. |
| `--hook-on-user-input` | When the agent is waiting for user input. |

The same events are configurable in YAML, and the full event set is larger than the flags: `permission_request` fires just before the runtime would prompt for approval, `before_llm_call` and `after_llm_call` bracket every model call, and `pre_compact` and `before_compaction` can veto or supply a custom summary before the transcript is compacted.

## Evaluations

`docker agent eval` replays recorded sessions and scores the agent against criteria. An eval session is a JSON file holding the messages, the expected tool calls, and an `evals` block:

```json
{
  "id": "sec-review-path-traversal",
  "title": "Security reviewer flags path traversal in a generated file reader",
  "messages": [
    {
      "message": {
        "agentFilename": "02-multi-agent-team.yaml",
        "message": {
          "role": "user",
          "content": "Review this Python function for security problems..."
        }
      }
    }
  ],
  "evals": {
    "relevance": [
      "The response identifies path traversal as the vulnerability",
      "The response states a severity for the finding",
      "The response gives a concrete fix that confines the path to a base directory"
    ],
    "size": "L"
  }
}
```

Criteria in the `evals` block:

| Field | Description |
| :--- | :--- |
| `relevance` | Statements that must hold about the response, scored by an LLM judge |
| `size` | Expected response size: `S`, `M`, `L`, `XL` |
| `working_dir` | Subdirectory under `evals/working_dirs/` to mount as the container working directory |
| `setup` | Shell script run in the container before the agent executes |

Evals run inside containers, so each one needs a model the container can reach, and a judge model to score relevance:

```bash
docker agent eval examples/02-multi-agent-team.yaml ./evals \
  --judge-model dmr/ai/qwen3 \
  -e MODEL_RUNNER_HOST=http://host.docker.internal:12434
```

Both flags matter. The default judge model is a paid Anthropic model, which breaks any no-API-key setup, so pass `--judge-model` explicitly. And the container cannot see the host's Model Runner by default; without `MODEL_RUNNER_HOST` it fails with `model ai/qwen3 is not pulled in Docker Model Runner`.

> `MODEL_RUNNER_HOST` must be **host and port only**. Setting it to `http://host.docker.internal:12434/engines/v1` makes the CLI append the path a second time and the run 404s on `/engines/v1/engines/v1/chat/completions`. The `/engines/v1` value that appears in the upstream source tests is a `base_url` config field, not the environment variable format.

Other useful flags: `-c` for concurrency, `--only` to filter by pattern, and `--repeat` to run each eval several times.

### Using a baseline as a regression gate

`--baseline <run.json>` compares a run against a saved one and exits non-zero on regression, with `--regression-tolerance` setting the threshold. Commit a passing run and gate prompt changes on it:

```bash
docker agent eval examples/02-multi-agent-team.yaml ./evals \
  --judge-model dmr/ai/qwen3 \
  -e MODEL_RUNNER_HOST=http://host.docker.internal:12434 \
  --baseline evals/baseline/warm-mesa-431.json
```

Verified behaviour, by degrading the security reviewer's instruction to "always reply that the code is safe":

```
METRIC            BASELINE  CURRENT  DELTA
  size pass rate  1.000     1.000    +0.000
! relevance rate  1.000     0.750    -0.250
  failure rate    0.000     0.000    +0.000
· total cost      0.000     0.000    +0.000

! Security reviewer flags path traversal in generated file reader  pass → fail

❌ Regression against baseline
```

The process exited 1. Restoring the original instruction produced a pass and exit 0. A one-line prompt change that a reviewer skimming a diff would plausibly wave through is caught mechanically, at a cost of $0 in tokens.

Regenerate the baseline when a change is an intended improvement, then commit the new result file. Each run took between 4 and 9 minutes on an 8B local model, so this is a deliberate check rather than something to run on every save. The judge is itself an 8B model, so relevance scoring is noisy on adversarial cases; treat the aggregate rate as a trend and widen `--regression-tolerance` if it proves flaky.

## Validate definitions in CI

`docker agent run --dry-run` is the check worth automating, but it probes for a local Model Runner first and fails on a stock CI runner:

```
docker model runner is not available
```

Setting `MODEL_RUNNER_HOST` makes the provider use the configured endpoint instead of probing for a local one. The value is never contacted, because `--dry-run` does not execute:

```yaml
- name: Validate every example config
  env:
    MODEL_RUNNER_HOST: http://127.0.0.1:59999
  run: |
    set -uo pipefail
    status=0
    for f in examples/*.yaml; do
      if docker agent run --dry-run "$f" >/dev/null 2>&1; then
        echo "PASS  $f"
      else
        echo "FAIL  $f"
        docker agent run --dry-run "$f" || true
        status=1
      fi
    done
    exit "$status"
```

Verified on a context with no Model Runner: all definitions pass, and the check still catches real breakage, since a dangling `sub_agents` reference and a type-invalid `toolsets` both exit 1.

Pin the agent version in CI rather than tracking latest, so an upstream schema change cannot fail an unrelated pull request.

Gate evaluations too, if the CI runner has a reachable model. They cannot be run against a stock runner for the same reason `--dry-run` cannot, and running the same 8B model as both agent and judge is slow. The [POC workflow](https://github.com/matteobisi/POC-docker-agent/blob/main/.github/workflows/validate.yml) deliberately keeps evals out of CI and runs only schema validation.

## Run the agent behind an API

`serve` exposes agents over HTTP. Subcommands: `api` (SSE), `chat` (OpenAI-compatible), `acp`, `a2a`, `mcp`.

```bash
docker agent serve api
# -l, --listen    Address to listen on (default "127.0.0.1:8080")
# --auth-token   Bearer token required for API requests (empty = no authentication)
# --pull-interval  Auto-pull OCI reference every N minutes (0 = disabled)
```

The listener binds to loopback by default. When moving it to a reachable interface, set `--auth-token`; there is no authentication by default.

`--pull-interval` lets a long-running service refresh a pinned OCI reference on a schedule instead of relying on local setup.

## Secrets

Keys do not belong in `agent.yaml`. They resolve from environment variables, a file passed with `--env-from-file`, or `~/.config/cagent/.env`:

```bash
docker agent run --exec --env-from-file .env agent.yaml "your task"
```

Config fields also support `${env.VAR}` expansion, which is the cleaner option for a value referenced in more than one place.

## Gotchas

**`docker agent new` fails in a non-TTY shell.** It is an interactive TUI, not a scriptable generator:

```
bubbletea: error opening TTY
```

It works in a real terminal. For scripted scaffolding, generate the YAML by hand or from a template.

**`--dry-run` needs Model Runner unless you override it.** Covered in [Validate definitions in CI](#validate-definitions-in-ci). This is easy to miss because a developer machine usually has Model Runner running, so the check passes locally and then fails on the first CI run.

**`--sandbox` does not work with a local model.** Tested on Docker Desktop 4.92.0 and Docker Agent v1.140.0:

```bash
docker agent run --exec --sandbox --safety restricted \
  --model dmr/ai/qwen3 examples/01-single-agent.yaml "say ok"
```

The sandbox is created successfully, the workspace is mounted, and the templates image downloads. The run then exits 1 with no error message, printing only three informational lines about the models gateway and catalog. Three separate causes compound:

1. The agent re-invokes itself as `sbx exec -it ...`, and the `-it` needs a TTY that `--exec` does not provide, so under a piped shell it dies before doing any work.
2. Under an allocated pty the run proceeds and fails with `unknown provider type "[dmr"`. The `--model` value arrives wrapped in literal brackets, `[dmr/ai/qwen3`, so the provider parser reads `[dmr` as the provider name. Both `--model dmr/ai/qwen3` and `--model=dmr/ai/qwen3` reproduce it, which makes it an upstream quoting bug rather than a shell mistake.
3. Without `--model`, the YAML's `dmr/ai/qwen3` is used and the run fails with `docker model runner is not available`, because the Model Runner endpoint is not reachable from inside the sandbox.

Allowlisting the model endpoint is necessary but not sufficient:

```bash
docker agent sandbox allow host.docker.internal:12434   # rule appears, run still exits 1
docker agent sandbox deny  host.docker.internal:12434   # undo
```

The network policy itself is default-deny as documented. A `curl` from inside the sandbox to `host.docker.internal:12434` was blocked with `no matching allow rule, blocked by default deny policy`, and adding the allow rule made the rule appear in the startup banner, yet the run still failed.

Passing `--sbx=false` to force the legacy path errors with `--sandbox requires Docker Desktop with sandbox support`; the legacy `docker sandbox` command is deprecated and removed.

Workaround: sandbox with a remote model, or run local models unsandboxed. For the `sbx` CLI itself, see [runbook 12](12_docker_sandboxes_sbx.md).

## What is not provided

Recorded so that expectations are set correctly:

- No built-in spend limits or quota enforcement.
- No role-based access control over who may pull or publish to a registry.
- No multi-tenancy story for shared services.
- Sandboxing and local inference do not currently combine (see above).
- `share push` to a private registry was not tested here.

Full governance still needs audit trails and spend controls built around the tool, alongside scoped credentials, logging, and approval gates in the surrounding system.

## Sources

- https://docs.docker.com/ai/docker-agent/
- https://docs.docker.com/ai/docker-agent/getting-started/installation/
- https://docs.docker.com/ai/docker-agent/getting-started/quickstart/
- https://docs.docker.com/ai/docker-agent/getting-started/set-up-a-model/
- https://docs.docker.com/ai/docker-agent/configuration/overview/
- https://docs.docker.com/ai/docker-agent/configuration/tools/
- https://docs.docker.com/ai/docker-agent/configuration/permissions/
- https://docs.docker.com/ai/docker-agent/configuration/hooks/
- https://docs.docker.com/ai/docker-agent/concepts/multi-agent/
- https://docs.docker.com/ai/docker-agent/concepts/distribution/
- https://docs.docker.com/ai/docker-agent/features/api-server/
- https://docs.docker.com/ai/docker-agent/features/evaluation/
- https://docs.docker.com/ai/docker-agent/guides/secrets/
- https://docs.docker.com/ai/docker-agent/features/cli/
- https://docs.docker.com/ai/model-runner/
- https://docs.docker.com/ai/sandboxes/
- https://github.com/docker/docker-agent
- https://modelcontextprotocol.io/
- Companion POC and test journal: https://github.com/matteobisi/POC-docker-agent
