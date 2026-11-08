# OpenClaw Device Pairing and Maintenance Runbook

Approve a new client — a second browser or the OpenClaw iOS app — against an OpenClaw
Gateway that runs in a container behind a Cloudflare Tunnel, then keep it healthy with the
routine maintenance commands. All commands run **inside the OpenClaw container**, not on the
host.

Verified on OpenClaw **2026.11.1** in a container on TrueNAS, with the Gateway started as
`openclaw.mjs gateway --allow-unconfigured --bind lan --port 30262` and published at
`https://trimmy.msbiro.net`. Version strings, port numbers, and output text are quoted from
that run; anything not exercised there is marked **(not verified)**.

## Table of Contents

- [The two things that break the CLI](#the-two-things-that-break-the-cli)
- [Pair a mobile app with a setup code](#pair-a-mobile-app-with-a-setup-code)
- [Approve a pending client](#approve-a-pending-client)
- [Verify the pairing](#verify-the-pairing)
- [Node permissions are not pairing permissions](#node-permissions-are-not-pairing-permissions)
- [Maintenance commands](#maintenance-commands)
- [Gotchas](#gotchas)
- [Troubleshooting](#troubleshooting)
- [Security notes](#security-notes)
- [Verified in this environment](#verified-in-this-environment)
- [Quick reference](#quick-reference)
- [Sources](#sources)

---

## The two things that break the CLI

Almost every failure below comes from one of these.

### 1. The port is not the default

The image starts the Gateway with an explicit `--port 30262`, while the upstream default is
`18789`. Confirm the real port from the process arguments rather than from the docs:

```shell
ps aux | grep '[o]penclaw.mjs gateway'
```

```text
568  1  0.0 ... /sbin/docker-init -- tini -s -- node /app/docker-entrypoint.mjs node openclaw.mjs gateway --allow-unconfigured --bind lan --port 30262
```

`ss` and `netstat` are **not installed** in the image, so to check what is actually listening
read `/proc/net/tcp`. `30262` in hex is `0x7636`, and state `0A` is `LISTEN`:

```shell
grep -i ':7636' /proc/net/tcp
```

```text
0: 00000000:7636 00000000:0000 0A ...
```

`00000000` means the socket is bound to all interfaces, consistent with `--bind lan`.

In this container the port is also exported as `OPENCLAW_GATEWAY_PORT=30262`, which is why
commands run without `--url` find the Gateway on their own.

### 2. `--url` disables credential fallback

Passing `--url` is treated as an override, and an override requires explicit credentials.
The CLI does not fall back to the config file or the environment:

```shell
openclaw devices list --url ws://127.0.0.1:30262
```

```text
gateway url override requires explicit credentials
Fix: pass --token or --password *** --url (or gatewayToken in tools).
For the default local or SSH-tunneled Gateway, remove --url to use the configured target.
```

The practical conclusion: **inside the container, drop `--url` entirely.** The CLI already
knows the port and the token. Reach for `--url` plus `--token` only when a command must target
a different Gateway.

If you do need the explicit form, `OPENCLAW_GATEWAY_TOKEN` is already set in the container
environment; `openclaw gateway auth-token --show` is only needed when that variable is absent:

```shell
openclaw devices list --url ws://127.0.0.1:30262 --token "$OPENCLAW_GATEWAY_TOKEN"
```

`auth-token` refuses to be captured by command substitution, by design:

```shell
TOKEN="$(openclaw gateway auth-token --show)"
```

```text
Gateway auth token failed: Refusing to print the Gateway token outside an interactive terminal. Run `openclaw gateway auth-token --show` directly in a terminal on the Gateway host.
```

Use the environment variable instead of trying to work around that guard.

## Pair a mobile app with a setup code

The iOS app needs a setup code plus the public Gateway URL. One command produces both:

```shell
openclaw qr
```

`--setup-code-only` prints just the payload, which is what you want when the QR cannot be
displayed in the terminal:

```shell
openclaw qr --setup-code-only
```

```text
eyJ1cmwiOiJ3c3M6Ly90cmltbXkubXNiaXJvLm5ldCIsImJvb3RzdHJhcFRva2VuIjoi...","expiresAtMs":1794099235407}
```

The payload carries the public `wss://` URL and a single-use bootstrap token. Treat the whole
string as a credential: it expires, and it should not be pasted into chat, tickets, or logs.
Relevant flags: `--limited` (omit `operator.admin`), `--voice-node` (node + read + Talk only),
`--public-url <url>` and `--url <url>` (override the advertised endpoint).

## Approve a pending client

Two different approval paths exist, and they answer different questions:

| Command | Approves | Use it for |
|---------|----------|------------|
| `openclaw devices list` / `devices approve` | client identities and their device tokens | a browser or app connecting for the first time |
| `openclaw nodes status` / `nodes pending` / `nodes approve` | capability nodes | a paired app asking to raise its declared permissions |

Both are reachable from the same request, so when one reports nothing, check the other.
Practice: on the iOS re-approval described below, `openclaw devices list --json` reported
`"pending": []` while the node was in state `pending-reapproval` with a pending request id —
the node path was the correct one.

### List what is waiting

```shell
openclaw devices list
```

```text
Paired (3)
┌─────────────────────┬──────────────────────┬────────────────┬──────────────────────┐
│ Device              │ Device ID            │ Roles          │ Scopes               │
├─────────────────────┼──────────────────────┼────────────────┼──────────────────────┤
│ iPhone              │ a254124fa19d985370a8 │ node, operator │ operator.admin,      │
│ openclaw-control-ui │ 7d69924a38ad5e7e1902 │ operator       │ operator.admin,      │
└─────────────────────┴──────────────────────┴────────────────┴──────────────────────┘
```

Add `--json` for the machine-readable form, which separates `pending` and `paired` arrays and
is much easier to read than the wrapped table. With nothing waiting, the approve command says
so:

```shell
openclaw devices approve --latest
```

```text
No pending device pairing requests to approve
```

`--latest` avoids copying a request id at all; use it when exactly one request is open. With
several open, list first and pass the specific id — `--latest` picks the most recent, which may
not be the one you mean.

### Approve

```shell
openclaw devices approve <requestId>
```

Or, on the node path:

```shell
openclaw nodes pending
openclaw nodes approve <requestId>
```

An unknown id fails safely, without side effects:

```shell
openclaw devices approve 11111111-2222-3333-4444-555555555555
```

```text
No pending device request matches 11111111-2222-3333-4444-555555555555. Run openclaw devices list and retry with the current request ID.
```

## Verify the pairing

`devices` and `nodes` are different views and it is worth running both.

```shell
openclaw devices list
openclaw nodes status
```

```text
Known: 1 · Paired: 1 · Connected: 0
┌──────┬───────────────────────────────────────────┬────────────────┬────────┬──────────────────────────────────┐
│ Node │ ID                                        │ IP             │ Detail │ Status                           │
├──────┼───────────────────────────────────────────┼────────────────┼────────┼──────────────────────────────────┤
│ iPho │ a254124fa19d985370a8a93835119e030b421f685 │ 109.78.127.147 │ client │ paired · disconnected · approved │
└──────┴───────────────────────────────────────────┴────────────────┴────────┴──────────────────────────────────┘
```

`paired` and `connected` are independent. A phone with the app in the background shows
`paired · disconnected · approved` — that is healthy, and it means node command invocation will
fail with `node not connected` until the app is reopened.

For one node, the capability and permission summary:

```shell
openclaw nodes describe --node iPhone
```

```text
│ Perms │ [calendar=no, camera=yes, contacts=no, location=no, microphone=yes, motion=no,
│       │  photos=no, reminders=no, screenRecording=yes, speechRecognition=yes]
```

`--node` is mandatory here; the id is not a positional argument.

## Node permissions are not pairing permissions

Approving a node authorizes the connection. It does not grant iOS permissions. The two are
tracked separately, and the useful one is the OS-granted set:

- **Declared** — what the app build says it can do. Changes on app upgrade, and a change to the
  declared set puts the node back into `pending-reapproval` with a new request id.
- **Granted** — what the user actually allowed in iOS Settings. This is what the `Perms` line
  shows, and what the invoke commands obey.

A node can therefore be `approved` and still fail every calendar, contacts, photo, reminder, or
motion call. Grant them in **iOS Settings → OpenClaw**, then reopen the app, which reports the
new set on the next connection. Do not assume the declared list reflects reality; re-run
`nodes describe --node <name>` after every permission change.

## Maintenance commands

All of the following were executed in this environment.

### Health and status

```shell
openclaw health
```

```text
Telegram: configured
Gateway event loop: ok max=23ms p99=23ms util=0.012 cpu=0.016
Gateway check duration: 10ms
Agents: main (default)
Heartbeat interval: 30m (main)
Session store (main): /home/node/.openclaw/agents/main/agent/openclaw-agent.sqlite (5 entries)
```

Fast event-loop latency and low `util` are the numbers worth watching; a growing `max` under an
idle Gateway points at a blocking plugin or channel handler.

```shell
openclaw status
openclaw status --deep
```

The short form prints the port, bind mode, channel state, and session counts. The deep form adds
the security audit that `status` otherwise skips.

### Configuration and logs

```shell
openclaw config validate
```

```text
Config valid: ~/.openclaw/openclaw.json
```

Run it before and after any hand edit of `openclaw.json`. Note that an unset key is not an
error, it just reports the runtime default:

```shell
openclaw config get gateway.port
```

```text
Config path is valid but unset: gateway.port. The runtime default applies until you set an authored value with `openclaw config set gateway.port <value>`.
```

In this deployment `gateway.port` and `gateway.bind` are both unset — the real port comes from
the launch flag, which is exactly why grepping the config for the port finds nothing.

```shell
openclaw logs --limit 200 --plain
openclaw logs --follow
```

```text
Log file: /tmp/openclaw/openclaw-2026-11-08.log
```

`--plain` drops ANSI styling, which matters when piping into `grep` or saving a snippet. Log
files live under `/tmp`, so they do not survive a container recreate.

### Channels and agents

```shell
openclaw channels status --probe
```

```text
Gateway reachable.
- Telegram trimmyhomebot: enabled, configured, running, connected, in:8h ago, out:8h ago, transport:just now, mode:polling, bot:@TrimmyHomeBot, token:***, works
```

`--probe` performs a live connection check; plain `channels list` only reads local config and
credentials and will happily report a channel as fine when the token is rejected.

```shell
openclaw agents list
openclaw agents list --bindings
```

`--bindings` prints the channel-to-agent routing rules, which plain `list` summarizes as a count.

### Automations

```shell
openclaw automations list
openclaw automations get <jobId>
openclaw automations runs <jobId> --limit 10
```

`list` renders the schedule and a `Status` column; `get` shows the payload, trigger script, and
`state`; `runs` is the execution journal. See the staleness trap in [Gotchas](#gotchas).

### Node commands

```shell
openclaw nodes list
openclaw nodes status --connected
openclaw nodes invoke --node iPhone --command device.status --json
```

```json
{"ok": false, "error": {"type": "cli_error", "message": "node not connected"}}
```

`nodes status --connected` returns an empty `nodes` array whenever a phone is backgrounded, so
treat it as "currently reachable", not "known to the system".

### Backups and security

```shell
openclaw backup list --from <location>
openclaw backup create
openclaw security audit
```

`backup list` requires `--from <location>`; without it the command exits with
`Missing required option "--from <location>"`. `security audit` is the same check folded into
`status --deep`, and it flags real deployment choices — for instance
`gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback=true` is reported as
`DANGEROUS: Host-header origin fallback enabled`, with the fix being explicit
`gateway.controlUi.allowedOrigins`.

### Doctor

```shell
openclaw doctor
```

`doctor` exits `0` even when it prints warnings, so an automated check must inspect output, not
the exit code. In this environment it reported one real finding: the memory search provider is
`openai` with no API key, so new and changed memory files are not indexed.

## Gotchas

- **`--url` without `--token` always fails** — `gateway url override requires explicit credentials`. Inside the container, omit `--url` instead of adding a token.
- **`auth-token` cannot be captured** — it refuses command substitution and non-TTY runs. Use `$OPENCLAW_GATEWAY_TOKEN`.
- **Two ports exist** — the upstream default is `18789`, this image runs `30262`. `gateway.port` unset in config does not mean the default is in use.
- **`ss` and `netstat` are absent** — read `/proc/net/tcp` to confirm the listening socket.
- **`nodes describe` needs `--node`** — a bare id is rejected as a missing option.
- **`paired` is not `connected`** — backgrounded phones fail invocation with `node not connected`.
- **Node approval is not an OS permission grant** — check `Perms` in `nodes describe`, not the declared capability list.
- **A stale `lastRunStatus: error` outlives a fix** — for a triggered automation, `state.lastRunStatus` and `lastError` are only rewritten by a real run. After repairing a broken trigger, `lastTriggerEvalAtMs` and `triggerEvalCount` advance while `lastRunStatus` still shows the old failure. Judge the fix by the eval counters and `consecutiveErrors: 0`, not by the status field.
- **Automation `toolsAllow: []` disables the trigger's own tools** — an empty allowlist starves the trigger script as well as the agent turn, producing `ReferenceError: <tool> is not defined`. Grant the specific commands the trigger needs (`--tools exec`).
- **`gh` is not installed** — use `git` over HTTPS with `GH_TOKEN`, or the GitHub API with `Authorization: Bearer $GH_TOKEN`.
- **`doctor` exits 0 on warnings** — parse its output.

## Troubleshooting

### `gateway url override requires explicit credentials`

`--url` was passed without credentials. Remove `--url` inside the container, or add
`--token "$OPENCLAW_GATEWAY_TOKEN"`.

### `Gateway auth token failed: Refusing to print the Gateway token outside an interactive terminal`

`auth-token --show` was invoked inside `$()` or from a non-interactive shell. Use the
`OPENCLAW_GATEWAY_TOKEN` environment variable, or run the command in an interactive terminal
when you genuinely need to read the value.

### CLI reports the Gateway as unreachable on `127.0.0.1:18789`

The container runs the Gateway on `30262`. Confirm with `ps aux | grep '[o]penclaw.mjs gateway'`
and `grep -i ':7636' /proc/net/tcp`. Commands without `--url` pick the right port up
automatically.

### Approval reports that exclusive offline state ownership is required

Reported when the CLI falls back to local state handling while the Gateway is running
**(not verified)**: the reproduction did not occur here, because every attempt failed earlier at
the credential check. The documented workaround still applies — make sure the command targets
the running Gateway, and do not stop or restart it just to retry the local fallback.

### `node not connected`

The app is backgrounded or the network changed. Bring the app to the foreground and retry; no
re-pairing is needed. `nodes status` will show `paired · disconnected` until then.

### Invoke succeeds but a capability returns a permission error

The OS permission is not granted. Check `Perms` in `nodes describe --node <name>` and grant it in
iOS Settings.

## Security notes

- The Gateway token is a password. It is never printed by any command shown here except
  `auth-token --show` in an interactive terminal, and it must never be committed or pasted into
  a ticket.
- Setup codes and QR payloads contain a single-use bootstrap token. They expire; treat them as
  credentials while they are valid.
- Approve only requests from devices you recognise. A new browser profile, a second browser, or
  a reinstalled app creates a fresh request.
- `--limited` and `--voice-node` exist so a client that only needs to talk can be paired without
  `operator.admin`. Prefer the narrowest scope that works.
- Once paired, a device stays authorized until its pairing is revoked, its token is rotated, or
  its local identity is reset. `openclaw devices revoke`, `rotate`, and `remove` cover the
  lifecycle.
- Exposing a Gateway publicly puts the token and the approval flow on the internet. Keep token
  auth on, keep `allowedOrigins` explicit rather than relying on host-header fallback, and treat
  `security audit` warnings as tasks rather than noise.

## Verified in this environment

Run on 2026-11-08 against OpenClaw `2026.11.1 (4ffdd20)`, container on TrueNAS, iOS node app
`2026.10.90`:

| Area | Command | Result |
|------|---------|--------|
| Port and bind | `ps aux`, `/proc/net/tcp` | `--port 30262`, `0.0.0.0:30262` listening |
| Credential override | `devices list --url ...` without token | documented error reproduced |
| Token guard | `gateway auth-token --show` non-TTY | documented error reproduced |
| Device list | `devices list`, `devices list --json` | 3 paired, 0 pending |
| Approve with none pending | `devices approve --latest` | `No pending device pairing requests to approve` |
| Approve unknown id | `devices approve 1111…` | `No pending device request matches …` |
| Setup code | `qr --setup-code-only` | payload with public `wss://` URL |
| Node status | `nodes status`, `nodes list`, `nodes describe --node iPhone` | permission map as quoted above |
| Node invoke, backgrounded | `nodes invoke --node iPhone --command device.status` | `node not connected` |
| Node re-approval | node request `da66c615-…` | approved, state `approved` |
| Health | `health`, `status` | as quoted above |
| Channels | `channels status --probe` | `works` |
| Config | `config validate`, `config get gateway.port` | valid, key unset |
| Logs | `logs --limit 200 --plain` | log file path and lines |
| Doctor | `doctor` | exit 0 with memory-provider warning |
| Security | `security audit` | host-header fallback flagged |
| Backup | `backup list` without `--from` | `Missing required option` |

Approving a device through `openclaw devices approve` end to end — from a live pending client
request rather than the node path — was **not exercised** here, because the only open request was
a node re-approval.

## Quick reference

```shell
# What port is the Gateway really on?
ps aux | grep '[o]penclaw.mjs gateway'
grep -i ':7636' /proc/net/tcp

# Pair a phone
openclaw qr
openclaw qr --setup-code-only

# Who is waiting, and who is paired
openclaw devices list
openclaw nodes pending
openclaw nodes status

# Approve
openclaw devices approve --latest
openclaw nodes approve <requestId>

# Verify
openclaw nodes describe --node iPhone

# Daily maintenance
openclaw health
openclaw status --deep
openclaw config validate
openclaw channels status --probe
openclaw logs --limit 200 --plain
openclaw automations list
openclaw doctor
openclaw security audit
openclaw backup list --from <location>
```

## Sources

- https://docs.openclaw.ai/cli/devices
- https://docs.openclaw.ai/cli/nodes
- https://docs.openclaw.ai/cli/status
- https://docs.openclaw.ai/cli/health
- https://docs.openclaw.ai/cli/logs
- https://docs.openclaw.ai/cli/config
- https://docs.openclaw.ai/cli/doctor
- https://docs.openclaw.ai/cli/security
- https://docs.openclaw.ai/cli/backup
- https://docs.openclaw.ai/cli/cron
- https://docs.openclaw.ai/cli/gateway
- https://docs.openclaw.ai/gateway/security
- https://docs.openclaw.ai/gateway/security/exposure-runbook
- https://docs.openclaw.ai/gateway/config-gateway
- https://docs.openclaw.ai/nodes
