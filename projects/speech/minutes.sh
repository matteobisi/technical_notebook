#!/bin/bash
set -euo pipefail

# Usage: ./minutes.sh <transcript.txt> [output.md] [--type auto|meeting|webinar] [--model model]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_FILE="${SPEECH_MINUTES_AGENT_FILE:-${SCRIPT_DIR}/minute_agent.yml}"
PROMPT_FILE="${SPEECH_MINUTES_PROMPT_FILE:-${SCRIPT_DIR}/prompts/minute_prompt.md}"
# Qwen2.5-14B-Instruct (Q4_K_M) is the default: it's a non-reasoning instruct
# model (no /no_think needed), faithful and strong at multilingual structured
# extraction, and at Q4 (~8.4 GB) it runs ~2x faster than qwen3:14B-Q6_K while
# leaving more memory headroom. Pulled from Hugging Face via Docker Model Runner.
# MUST match the model refs in minute_agent.yml (this script pulls and pre-warms
# it; the agent YAML binds it). When overridden (env or --model), the agent path
# passes docker agent's native `--model agent=dmr/<ref>` overrides instead of
# editing the YAML — MODEL_EXPLICIT tracks that.
MODEL="${SPEECH_MINUTES_MODEL:-huggingface.co/bartowski/qwen2.5-14b-instruct-gguf}"
MODEL_EXPLICIT=false
[ -n "${SPEECH_MINUTES_MODEL:-}" ] && MODEL_EXPLICIT=true
TYPE="auto"
OUTPUT_FILE=""
NO_PULL=false
# SINGLE-SHOT THRESHOLD. If the transcript is <= CHUNK_CHARS the whole thing is
# summarized in ONE model call (single-shot); above it, the two-pass map/reduce
# chunked path kicks in as a fallback. Single-shot is the default because it gives
# the cleanest, most faithful minutes (no cross-chunk structure loss, no merge
# bloat) and is fast (~6 min for a 47-min/48 KB Italian meeting). Sizing against the
# model's 32768-token context: reserve ~5K for the output + ~1.5K for the system
# prompt/directive → ~26K tokens for the transcript ≈ ~90 KB (Italian ~3.5 chars/tok).
# 80000 chars (~23K tokens → ~30K total, ~2.5K headroom) is the safe ceiling and
# covers ~90-min meetings; only 90-min+ (>80 KB) falls back to two-pass chunked.
# (Probe-verified stable to 60 KB; 60-80 KB is within the context math but past direct
# testing — validate on a long meeting.) Single-shot's long silent prefill can hit a
# transient idle/proxy stream drop — the run_agent retry (identical prompt, warm KV
# cache) recovers it (upstream fix: docker/docker-agent#3302, in docker-agent >= v1.90).
CHUNK_CHARS="${SPEECH_MINUTES_CHUNK_CHARS:-80000}"
# Two output caps: short for chunk/merge summaries (keeps them small so the
# reduce step stays inside the context window), large for the final document
# (avoids truncating the minutes). On the AGENT path these caps live in
# minute_agent.yml (condenser=768, root=5120) and are selected per stage via
# --agent; these variables drive only the direct-API path (and validation).
# SPEECH_MINUTES_MAX_TOKENS still sets the final cap for back-compat.
SUMMARY_MAX_TOKENS="${SPEECH_MINUTES_SUMMARY_MAX_TOKENS:-768}"
FINAL_MAX_TOKENS="${SPEECH_MINUTES_MAX_TOKENS:-${SPEECH_MINUTES_FINAL_MAX_TOKENS:-5120}}"
MAX_TOKENS="$SUMMARY_MAX_TOKENS"
# Default to the Docker Agent (cagent) path: it's the showcased pipeline (cagent +
# Docker Model Runner, fully local). Set SPEECH_MINUTES_USE_AGENT=false to use the
# lighter direct-API path (curl straight to DMR) instead.
USE_AGENT="${SPEECH_MINUTES_USE_AGENT:-true}"
# When true (or after any failure) the temp dir is kept so its error.log /
# .agent.jsonl survive for inspection instead of being wiped by the EXIT trap.
KEEP_TMP="${SPEECH_MINUTES_KEEP_TMP:-false}"
TMP_FAILED=0
# Output language. "auto" detects Italian/English from the transcript; set to a
# language name (e.g. Italian, English) to force it. Needed because Qwen2.5
# follows the (English) instruction language and otherwise translates the
# minutes to English; a soft "match the input" hint is too weak to override it.
OUTPUT_LANG="${SPEECH_MINUTES_LANG:-auto}"
# Proper-noun corrections. The ASR step garbles recurring brand names a few
# different ways per run (e.g. Auth0 -> Uzero/Auziro, Chainguard -> Cenger).
# Rather than destructively rewrite the (faithful) transcript, we hand the
# minutes agent a wrong => right map and let it normalize names while writing
# the document. Default covers commonly garbled product names; add your own
# company/brand names here or via SPEECH_MINUTES_CORRECTIONS, which
# is APPENDED for per-meeting names (e.g. customer/company names). Set
# SPEECH_MINUTES_NO_CORRECTIONS=true to disable entirely (fully faithful minutes).
DEFAULT_NAME_CORRECTIONS="Uzero, Zero, Auziro, Au0 => Auth0; Cubevirta, Cubevirt, Cube Virt, Kubevirta => KubeVirt; Sneeka, Synap, Snik => Snyk; Cenger, Cengage => Chainguard; Tegera => Tigera; Silium => Cilium"
if [ "${SPEECH_MINUTES_NO_CORRECTIONS:-false}" = true ]; then
    NAME_CORRECTIONS=""
else
    NAME_CORRECTIONS="$DEFAULT_NAME_CORRECTIONS"
    if [ -n "${SPEECH_MINUTES_CORRECTIONS:-}" ]; then
        NAME_CORRECTIONS="${NAME_CORRECTIONS}; ${SPEECH_MINUTES_CORRECTIONS}"
    fi
fi
DMR_API_URL="${SPEECH_MINUTES_DMR_API_URL:-http://localhost:12434/engines/v1/chat/completions}"
DMR_TIMEOUT_SECONDS="${SPEECH_MINUTES_DMR_TIMEOUT_SECONDS:-600}"
# Selected per stage: "root" (final secretary, large cap) or "condenser"
# (chunk/outline notes, small cap) — see minute_agent.yml and select_stage().
ACTIVE_AGENT="condenser"

# /no_think is a Qwen3 thinking-control token. Non-reasoning instruct models
# (Qwen2.5, Mistral, etc.) don't recognize it and would just see stray text, so
# emit it only for qwen3.
think_prefix() {
    case "$MODEL" in
        *qwen3* | *Qwen3*) printf '/no_think ' ;;
        *) printf '' ;;
    esac
}

usage() {
    cat <<EOF
Usage: $0 <transcript.txt> [output.md] [options]

Options:
  --type auto|meeting|webinar   Transcript type detection mode (default: auto)
  --model <model>               Docker Model Runner model (default: ${MODEL})
  --agent-file <path>           Docker Agent YAML file (default: ${AGENT_FILE})
  --prompt-file <path>          Secretary prompt file (default: ${PROMPT_FILE})
  --chunk-chars <number>        Single-shot threshold: transcripts up to this size are
                                summarized in one call; larger ones use the chunked
                                two-pass fallback (default: ${CHUNK_CHARS})
  --no-pull                     Do not run docker model pull automatically
  -h, --help                    Show this help

Examples:
  $0 meeting.txt
  $0 meeting.txt meeting_minutes.md --type meeting
  SPEECH_MINUTES_USE_AGENT=false $0 meeting.txt --type meeting   # direct-API path
  SPEECH_MINUTES_LANG=English $0 webinar.txt --type webinar
EOF
}

if [ $# -eq 0 ]; then
    usage
    exit 1
fi

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

TRANSCRIPT_FILE="$1"
shift

if [ "${1:-}" != "" ] && [[ ! "${1:-}" =~ ^-- ]]; then
    OUTPUT_FILE="$1"
    shift
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --type)
            TYPE="${2:-}"
            if [ -z "$TYPE" ]; then
                echo "Error: --type requires auto, meeting, or webinar." >&2
                exit 1
            fi
            shift 2
            ;;
        --model)
            MODEL="${2:-}"
            if [ -z "$MODEL" ]; then
                echo "Error: --model requires a Docker Model Runner model name." >&2
                exit 1
            fi
            MODEL_EXPLICIT=true
            shift 2
            ;;
        --agent-file)
            AGENT_FILE="${2:-}"
            if [ -z "$AGENT_FILE" ]; then
                echo "Error: --agent-file requires a path." >&2
                exit 1
            fi
            shift 2
            ;;
        --prompt-file)
            PROMPT_FILE="${2:-}"
            if [ -z "$PROMPT_FILE" ]; then
                echo "Error: --prompt-file requires a path." >&2
                exit 1
            fi
            shift 2
            ;;
        --chunk-chars)
            CHUNK_CHARS="${2:-}"
            if [ -z "$CHUNK_CHARS" ]; then
                echo "Error: --chunk-chars requires a positive integer." >&2
                exit 1
            fi
            shift 2
            ;;
        --no-pull)
            NO_PULL=true
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown argument '$1'." >&2
            usage
            exit 1
            ;;
    esac
done

case "$TYPE" in
    auto | meeting | webinar) ;;
    *)
        echo "Error: --type must be auto, meeting, or webinar." >&2
        exit 1
        ;;
esac

if [ ! -f "$TRANSCRIPT_FILE" ]; then
    echo "Error: Transcript file not found: $TRANSCRIPT_FILE" >&2
    exit 1
fi

if ! [[ "$CHUNK_CHARS" =~ ^[0-9]+$ ]] || [ "$CHUNK_CHARS" -lt 2000 ]; then
    echo "Error: --chunk-chars must be an integer >= 2000." >&2
    exit 1
fi

if ! [[ "$SUMMARY_MAX_TOKENS" =~ ^[0-9]+$ ]] || [ "$SUMMARY_MAX_TOKENS" -lt 512 ]; then
    echo "Error: SPEECH_MINUTES_SUMMARY_MAX_TOKENS must be an integer >= 512." >&2
    exit 1
fi

if ! [[ "$FINAL_MAX_TOKENS" =~ ^[0-9]+$ ]] || [ "$FINAL_MAX_TOKENS" -lt 512 ]; then
    echo "Error: SPEECH_MINUTES_MAX_TOKENS must be an integer >= 512." >&2
    exit 1
fi

if [ -z "$OUTPUT_FILE" ]; then
    BASENAME="$(basename "$TRANSCRIPT_FILE")"
    OUTPUT_FILE="${BASENAME%.*}_minutes.md"
fi

TMPDIR="$(mktemp -d)"
cleanup() {
    if [ "$KEEP_TMP" = true ] || [ "$TMP_FAILED" = 1 ]; then
        echo "Temp files preserved for debugging in: $TMPDIR" >&2
        return
    fi
    rm -rf "$TMPDIR"
}
trap cleanup EXIT INT TERM

# The checked-in minute_agent.yml and prompts/minute_prompt.md are the single
# live sources (no generated fallbacks). A custom agent YAML must define the same
# two agents ("root" for the final document, "condenser" for chunk/outline notes).
if [ "$USE_AGENT" = true ] && [ ! -f "$AGENT_FILE" ]; then
    echo "Error: Docker Agent file not found: $AGENT_FILE" >&2
    exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
    echo "Error: Prompt file not found: $PROMPT_FILE" >&2
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "Error: Docker is required. Install and start Docker Desktop with Model Runner enabled." >&2
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "Error: Docker Desktop is not running or is not reachable." >&2
    exit 1
fi

if ! docker model status --json >/dev/null 2>&1; then
    echo "Error: Docker Model Runner is not available. Enable it in Docker Desktop and retry." >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 is required to build and parse local model requests." >&2
    exit 1
fi

if [ "$USE_AGENT" = true ]; then
    # Prefer the brew-installed docker-agent, which is user-managed and current, over
    # both Docker Desktop's embedded `docker agent` AND any `docker-agent` Desktop puts
    # on PATH — both lag the GitHub release (Desktop 4.80 still ships v1.79, which lacks
    # the #3302 stream-truncation retry fix; brew is v1.93). `brew --prefix docker-agent`
    # resolves to the active keg regardless of version and regardless of PATH order, so
    # we don't get shadowed by Desktop's binary. SPEECH_MINUTES_AGENT_CMD overrides all.
    BREW_AGENT=""
    if command -v brew >/dev/null 2>&1; then
        _brew_agent="$(brew --prefix docker-agent 2>/dev/null)/bin/docker-agent"
        [ -x "$_brew_agent" ] && BREW_AGENT="$_brew_agent"
    fi
    if [ -n "${SPEECH_MINUTES_AGENT_CMD:-}" ]; then
        # Force a specific binary. Word-split so "docker agent" or a full path both work.
        read -r -a DOCKER_AGENT_CMD <<<"$SPEECH_MINUTES_AGENT_CMD"
    elif [ -n "$BREW_AGENT" ]; then
        DOCKER_AGENT_CMD=("$BREW_AGENT")
    elif command -v docker-agent >/dev/null 2>&1; then
        DOCKER_AGENT_CMD=(docker-agent)
    elif docker agent version >/dev/null 2>&1; then
        DOCKER_AGENT_CMD=(docker agent)
    else
        echo "Error: Docker Agent is required. Use Docker Desktop 4.63+ or install it with: brew install docker-agent" >&2
        exit 1
    fi
    echo "Docker Agent: ${DOCKER_AGENT_CMD[*]} ($("${DOCKER_AGENT_CMD[@]}" version 2>/dev/null | head -1))"
elif ! command -v curl >/dev/null 2>&1; then
    echo "Error: curl is required to call Docker Model Runner's local API." >&2
    exit 1
fi

if [ "$NO_PULL" = false ]; then
    if ! docker model inspect "$MODEL" >/dev/null 2>&1; then
        echo "Pulling local model with Docker Model Runner: $MODEL"
        docker model pull "$MODEL"
    fi
fi

# Do NOT unload by default: a cold model load + a large single-shot prefill exceeds
# docker agent's stream timeout (the model loads for ~30s with no token streamed,
# the client gives up: "unexpected end of JSON input"). Keeping the model warm
# makes the timed call prefill-only. Set SPEECH_MINUTES_UNLOAD_BEFORE_RUN=true to
# force a cold load (e.g. to reclaim RAM).
if [ "${SPEECH_MINUTES_UNLOAD_BEFORE_RUN:-false}" = true ]; then
    docker model unload "$MODEL" >/dev/null 2>&1 || true
fi

detect_type() {
    if [ "$TYPE" != "auto" ]; then
        echo "$TYPE"
        return
    fi

    if grep -Eiq '(^|[[:space:]]|\])speaker_[0-9]+[[:space:]]*:|^speaker_[0-9]+[[:space:]]*=' "$TRANSCRIPT_FILE"; then
        echo "meeting"
    elif grep -Eiq '\[SPEAKER[_ -]?[0-9]+\]' "$TRANSCRIPT_FILE"; then
        echo "meeting"
    else
        echo "webinar"
    fi
}

TRANSCRIPT_TYPE="$(detect_type)"

# Heuristic Italian-vs-English detection by counting distinctively common,
# ASCII-only function words of each language. Returns a language name, or empty
# if it can't tell (callers then fall back to "same language as the transcript").
detect_language() {
    if [ "$OUTPUT_LANG" != "auto" ]; then
        echo "$OUTPUT_LANG"
        return
    fi
    local lower it en
    lower="$(tr 'A-Z' 'a-z' <"$TRANSCRIPT_FILE")"
    it=$(printf '%s' "$lower" | grep -owE 'che|di|il|la|per|non|sono|con|una|del|gli|come|questo|anche|dei|nella|sulla' | wc -l | tr -d ' ')
    en=$(printf '%s' "$lower" | grep -owE 'the|and|of|to|is|are|with|this|that|for|have|will|from|been|were' | wc -l | tr -d ' ')
    if [ "$it" -gt "$en" ]; then
        echo "Italian"
    elif [ "$en" -gt "$it" ]; then
        echo "English"
    else
        echo ""
    fi
}

RESOLVED_LANG="$(detect_language)"
if [ -n "$RESOLVED_LANG" ]; then
    LANG_INSTRUCTION="Write all content in ${RESOLVED_LANG}. Do not translate or switch to another language."
else
    LANG_INSTRUCTION="Write all content in the same language as the source transcript; do not translate."
fi

# Proper-noun normalization passed to the agent (see NAME_CORRECTIONS above).
if [ -n "$NAME_CORRECTIONS" ]; then
    CORRECTIONS_INSTRUCTION=" Spelling normalization ONLY: the transcript may misspell some recurring proper nouns; wherever such a name actually appears, use its correct spelling per this 'wrong => right' map: ${NAME_CORRECTIONS}. These are spelling fixes, NOT meeting topics — do NOT create any section, bullet, decision, action item, open question or risk about these names themselves, and never introduce a name that did not actually come up in the meeting."
else
    CORRECTIONS_INSTRUCTION=""
fi

run_agent() {
    local prompt_path="$1"
    local message="$2"
    local output_path="$3"
    local error_path="${output_path}.error.log"
    local json_path="${TMPDIR}/agent_output_$(basename "$output_path").jsonl"
    local parsed_path="${TMPDIR}/agent_output_$(basename "$output_path").md"

    # With SPEECH_MINUTES_DEBUG=true, turn on docker agent's own debug log so a
    # backend stream crash leaves a trace beyond "unexpected end of JSON input".
    local debug_args=()
    if [ "${SPEECH_MINUTES_DEBUG:-false}" = true ]; then
        debug_args=(--debug --log-file "${output_path}.agent.debug.log")
    fi

    # docker agent / DMR streaming intermittently drops a call ("unexpected end of
    # JSON input") even on small prompts (observed mid-run on a 9 KB chunk while the
    # previous chunk succeeded). cagent marks these "Non-retryable" and aborts. The
    # two-pass pipeline makes ~15 calls, so a single transient drop must not kill the
    # whole run — retry with a short backoff and a re-warm between attempts.
    # When the model is overridden (env/--model), use docker agent's native
    # per-agent override instead of editing the YAML. Format per `run --help`:
    # --model '[agent=]provider/model'; the DMR provider ref is dmr/<model>.
    local model_args=()
    if [ "$MODEL_EXPLICIT" = true ]; then
        model_args=(--model "root=dmr/${MODEL}" --model "condenser=dmr/${MODEL}")
    fi

    local attempts="${SPEECH_MINUTES_AGENT_RETRIES:-3}"
    local attempt=1
    while true; do
        if DOCKER_AGENT_HIDE_TELEMETRY_BANNER=1 "${DOCKER_AGENT_CMD[@]}" run "$AGENT_FILE" \
            --agent "$ACTIVE_AGENT" \
            --exec \
            --json \
            --hide-tool-calls \
            --hide-tool-results \
            ${model_args[@]+"${model_args[@]}"} \
            ${debug_args[@]+"${debug_args[@]}"} \
            --prompt-file "$prompt_path" \
            "$(think_prefix)${message}" >"$json_path" 2>"$error_path"; then
            break
        fi
        if [ "$attempt" -ge "$attempts" ]; then
            cp "$json_path" "${output_path}.agent.jsonl" 2>/dev/null || true
            TMP_FAILED=1
            echo "Error: Docker Agent call failed after ${attempts} attempts." >&2
            echo "Error log saved to: $error_path" >&2
            echo "Raw JSON output saved to: ${output_path}.agent.jsonl" >&2
            exit 1
        fi
        # Retry the IDENTICAL request immediately (after a brief pause), with no
        # intervening different prompt. The drop is a transient idle/proxy
        # disconnect during the silent prefill (see docker/docker-agent#3302); the
        # backend's KV cache from the just-attempted prefill makes the retry fast
        # enough to beat the idle limit. A re-warm call with a *different* prompt
        # here would evict that cache and defeat the mechanism, so we don't.
        echo "  Docker Agent stream dropped (attempt ${attempt}/${attempts}); retrying same prompt (warm KV cache)..." >&2
        attempt=$((attempt + 1))
        sleep 2
    done

    python3 - "$json_path" >"$parsed_path" <<'PY'
import json
import sys

# cagent streams the assistant answer as "agent_choice" events and any chain of
# thought as "agent_choice_reasoning". Prefer the answer; use generic
# OpenAI-style shapes next (forward-compatibility); fall back to reasoning only
# if there is no answer at all, so reasoning text never masquerades as minutes.
answer = []
generic = []
reasoning = []
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue
        etype = event.get("type")
        content = event.get("content")
        if etype == "agent_choice":
            if isinstance(content, str):
                answer.append(content)
            continue
        if etype == "agent_choice_reasoning":
            if isinstance(content, str):
                reasoning.append(content)
            continue
        message = event.get("message")
        if isinstance(message, dict) and isinstance(message.get("content"), str):
            generic.append(message["content"])
            continue
        choices = event.get("choices")
        if isinstance(choices, list):
            for choice in choices:
                if not isinstance(choice, dict):
                    continue
                delta = choice.get("delta")
                if isinstance(delta, dict) and isinstance(delta.get("content"), str):
                    generic.append(delta["content"])
                inner = choice.get("message")
                if isinstance(inner, dict) and isinstance(inner.get("content"), str):
                    generic.append(inner["content"])

text = "".join(answer).strip() or "".join(generic).strip() or "".join(reasoning).strip()
markers = ("# Meeting minutes", "# Webinar summary")
starts = [text.find(marker) for marker in markers if text.find(marker) != -1]
if starts:
    text = text[min(starts):].strip()
print(text)
PY

    mv "$parsed_path" "$output_path"

    if [ ! -s "$output_path" ]; then
        cp "$json_path" "${output_path}.agent.jsonl" 2>/dev/null || true
        TMP_FAILED=1
        echo "Error: Docker Agent produced an empty minutes output." >&2
        echo "Error log saved to: $error_path" >&2
        echo "Raw JSON output saved to: ${output_path}.agent.jsonl" >&2
        exit 1
    fi

    if [ "${SPEECH_MINUTES_DEBUG:-false}" = true ]; then
        cp "$json_path" "${output_path}.agent.jsonl" 2>/dev/null || true
        echo "Debug: raw Docker Agent JSONL saved to: ${output_path}.agent.jsonl" >&2
        echo "Debug: Docker Agent stderr saved to: $error_path" >&2
    else
        rm -f "$error_path"
    fi
}

run_dmr_api() {
    local prompt_path="$1"
    local message="$2"
    local output_path="$3"
    local error_path="${output_path}.error.log"
    local payload_path="${TMPDIR}/dmr_payload_$(basename "$output_path").json"
    local response_path="${TMPDIR}/dmr_response_$(basename "$output_path").json"
    local parsed_path="${TMPDIR}/dmr_output_$(basename "$output_path").md"

    python3 - "$MODEL" "$MAX_TOKENS" "$PROMPT_FILE" "$prompt_path" "$message" "$payload_path" "$(think_prefix)" <<'PY'
import json
import sys
from pathlib import Path

model, max_tokens, prompt_file, prompt_path, message, payload_path, think = sys.argv[1:]
system_prompt = Path(prompt_file).read_text(encoding="utf-8")
prompt = Path(prompt_path).read_text(encoding="utf-8")
user_prefix = (think.strip() + "\n") if think.strip() else ""
payload = {
    "model": model,
    # Directive (message) goes AFTER the content (prompt), not before it. With a
    # large single-shot transcript, an instruction placed first sits tens of KB
    # before the generation point and gets lost to recency (the model drifted to
    # English and over-summarized). Putting it last keeps the language + format
    # rules adjacent to where the model starts writing.
    "messages": [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_prefix + prompt + "\n\n" + message},
    ],
    "temperature": 0.2,
    "top_p": 0.9,
    "max_tokens": int(max_tokens),
    "stream": False,
}
Path(payload_path).write_text(json.dumps(payload), encoding="utf-8")
PY

    if ! curl -sS --max-time "$DMR_TIMEOUT_SECONDS" \
        "$DMR_API_URL" \
        -H 'Content-Type: application/json' \
        -d @"$payload_path" >"$response_path" 2>"$error_path"; then
        cp "$response_path" "${output_path}.response.json" 2>/dev/null || true
        TMP_FAILED=1
        echo "Error: Docker Model Runner minutes generation failed." >&2
        echo "Error log saved to: $error_path" >&2
        echo "Response saved to: ${output_path}.response.json" >&2
        exit 1
    fi

    python3 - "$response_path" >"$parsed_path" <<'PY'
import json
import sys
from pathlib import Path

response_path = Path(sys.argv[1])
try:
    response = json.loads(response_path.read_text(encoding="utf-8"))
except json.JSONDecodeError as exc:
    raise SystemExit(f"Invalid JSON response from Docker Model Runner: {exc}")

if "error" in response:
    raise SystemExit(response["error"])

message = response["choices"][0]["message"]
text = (message.get("content") or message.get("reasoning_content") or "").strip()
markers = ("# Meeting minutes", "# Webinar summary")
starts = [text.find(marker) for marker in markers if text.find(marker) != -1]
if starts:
    text = text[min(starts):].strip()
print(text)
PY

    mv "$parsed_path" "$output_path"

    if [ ! -s "$output_path" ]; then
        cp "$response_path" "${output_path}.response.json" 2>/dev/null || true
        TMP_FAILED=1
        echo "Error: Docker Model Runner produced an empty minutes output." >&2
        echo "Error log saved to: $error_path" >&2
        echo "Response saved to: ${output_path}.response.json" >&2
        exit 1
    fi

    rm -f "$error_path"
}

run_model() {
    if [ "$USE_AGENT" = true ]; then
        run_agent "$@"
    else
        run_dmr_api "$@"
    fi
}

build_prompt() {
    local transcript_path="$1"
    local output_path="$2"
    local mode="$3"

    {
        cat "$PROMPT_FILE"
        echo ""
        echo "## Requested output type"
        echo ""
        echo "$mode"
        echo ""
        echo "## Transcript"
        echo ""
        cat "$transcript_path"
    } >"$output_path"
}

# Forceful, type-pinned instruction for the final document. The combined
# secretary prompt describes both templates and asks the model to detect the
# type, so the requested --type was only a weak hint and the model drifted
# between meeting and webinar formats (dropping the Action items table). This
# hard-pins the resolved type, the exact title, and the section list.
final_directive() {
    if [ "$TRANSCRIPT_TYPE" = "webinar" ]; then
        printf '%s' "Produce ONLY a single-speaker webinar/presentation summary. Start the output with exactly this line and nothing before it: # Webinar summary. Then include these sections in this order, each as a ## heading: Executive summary, Main topics, Key points, Decisions or conclusions, Recommended follow-up, Open questions, Transcript quality notes. Do NOT use the meeting-minutes format. Be thorough and specific: capture all concrete details actually present in the source - product, feature and technology names, numbers, pricing/commercial terms, and named follow-ups - and prefer specifics over generic paraphrase; do not over-summarize. Deduplicate repeated items, keep only well-supported points, and do not invent anything. Keep the section headings and title exactly as written above. ${LANG_INSTRUCTION}${CORRECTIONS_INSTRUCTION}"
    else
        printf '%s' "Produce ONLY a meeting-minutes document. Start the output with exactly this line and nothing before it: # Meeting minutes. Then include these sections in this order, each as a ## heading: Participants / speaker mapping, Executive summary, Discussion by topic, Decisions made, Action items, Open questions, Risks / blockers, Next steps, Transcript quality notes. The Action items section MUST be a Markdown table with columns Owner, Action, Due date, Evidence / context (write Not specified when unknown). For Participants / speaker mapping, list the speaker labels found in the transcript (e.g. speaker_0, speaker_1) and use real names only if a mapping is provided; never invent names. When a mapping is provided, use the real names throughout the ENTIRE document (Discussion by topic, Action items, Next steps), not only in the Participants section. If two or more speaker labels map to the same name, treat them as one person and list that person only once. For any speaker label with no mapping, keep the bare label (e.g. speaker_5) as its attribution: never write '= Speaker_N', and never drop that speaker's contributions. Be exhaustive and concrete, not a high-level summary: in 'Discussion by topic', for EACH topic enumerate the SPECIFIC named features, products, technologies, integrations, numbers, pricing/commercial terms and certifications actually mentioned — name them explicitly (e.g. each distinct capability or product by its name), do not collapse several named features into one vague phrase. A reader who was not present must learn the concrete details, not just the themes. When in doubt, include a real detail rather than omit it; you have ample length budget, so do not truncate the detail to stay short. Always capture commercial and contractual specifics whenever mentioned — pricing or licensing tiers, trial terms and durations, user or volume limits, SLAs, and deployment options (e.g. SaaS vs self-hosted/enterprise) — these are easy to overlook but important. In 'Decisions made', list ONLY what the participants explicitly agreed or concluded; if the meeting was exploratory or informational with no firm decision, write a single line stating that no formal decision was made — never promote a product feature, an explanation, or a recommendation into a decision. In the Action items table, the Owner MUST be a real participant name whenever a mapping is provided (never 'speaker_N'), and include only concrete commitments someone actually took on (if there are none, write a single row saying so). Ignore off-topic small talk (weather, travel, personal chat, jokes): never list it as a topic, decision, action item, risk, or next step. Do NOT use the webinar format. Deduplicate repeated items, keep only well-supported decisions and actions, and do not invent anything. Keep the section headings and title exactly as written above. ${LANG_INSTRUCTION}${CORRECTIONS_INSTRUCTION}"
    fi
}

# Lean prompt for the map/reduce summary steps. It intentionally omits the full
# minutes specification so the model condenses the chunk instead of trying to
# emit a complete document for every chunk.
build_summary_prompt() {
    local content_path="$1"
    local output_path="$2"

    {
        echo "## Transcript chunk"
        echo ""
        cat "$content_path"
    } >"$output_path"
}

# Switch the output cap for the current stage. On the agent path the caps are
# fixed per agent in minute_agent.yml, so this just selects which agent to run
# (root = final document, condenser = chunk/outline notes); the direct-API path
# reads MAX_TOKENS per call.
select_stage() {
    case "$1" in
        final)
            ACTIVE_AGENT="root"
            MAX_TOKENS="$FINAL_MAX_TOKENS"
            ;;
        summary)
            ACTIVE_AGENT="condenser"
            MAX_TOKENS="$SUMMARY_MAX_TOKENS"
            ;;
        *)
            echo "Error: select_stage expects 'final' or 'summary'." >&2
            exit 1
            ;;
    esac
}

split_transcript() {
    awk -v max_chars="$CHUNK_CHARS" -v dir="$TMPDIR" '
        BEGIN {
            chunk = 1
            chars = 0
            path = sprintf("%s/chunk_%03d.txt", dir, chunk)
        }
        {
            line_len = length($0) + 1
            if (chars > 0 && chars + line_len > max_chars) {
                close(path)
                chunk++
                chars = 0
                path = sprintf("%s/chunk_%03d.txt", dir, chunk)
            }
            print $0 >> path
            chars += line_len
        }
    ' "$TRANSCRIPT_FILE"
}

# Merge two or more partial summaries into one consolidated summary.
# Usage: merge_summaries_file <output_path> <summary_file> [<summary_file> ...]
merge_summaries_file() {
    local merge_output="$1"
    shift
    local merge_prompt="${merge_output}.prompt.txt"
    {
        echo "## Partial summaries to merge"
        echo ""
        local f
        for f in "$@"; do
            cat "$f"
            echo ""
            echo "---"
            echo ""
        done
    } >"$merge_prompt"
    run_model "$merge_prompt" "Merge these partial meeting summaries into one consolidated summary. Deduplicate repeated points and preserve all decisions, action items, speaker contributions, risks, and open questions. Output Markdown only. ${LANG_INSTRUCTION}" "$merge_output"
}

TRANSCRIPT_SIZE=$(wc -c <"$TRANSCRIPT_FILE" | tr -d ' ')

if [ "$USE_AGENT" = true ]; then
    echo "Generating local minutes via Docker Agent + Docker Model Runner..."
else
    echo "Generating local minutes via Docker Model Runner (direct API)..."
fi
echo "Context: model default; summary cap: $SUMMARY_MAX_TOKENS tokens; final cap: $FINAL_MAX_TOKENS tokens; chunk size: $CHUNK_CHARS characters"
echo "Transcript: $TRANSCRIPT_FILE"
echo "Detected type: $TRANSCRIPT_TYPE"
echo "Output language: ${RESOLVED_LANG:-same as transcript}"
echo "Model: $MODEL"

# Pre-warm the model on the agent path so the (timed, streaming) generation call
# is prefill-only. A cold load mid-call streams no token for ~30s and docker agent
# aborts the stream ("unexpected end of JSON input"). One tiny non-streaming
# request loads the model into DMR with its default config — which the agent then
# reuses (we no longer override context/runtime_flags, so no reload). Best-effort.
if [ "$USE_AGENT" = true ]; then
    echo "Pre-warming model (avoids a cold-load stream timeout on the agent path)..."
    WARM_PAYLOAD="${TMPDIR}/warmup_payload.json"
    python3 - "$MODEL" "$WARM_PAYLOAD" <<'PY'
import json, sys
model, out = sys.argv[1], sys.argv[2]
json.dump({"model": model, "messages": [{"role": "user", "content": "ok"}],
           "max_tokens": 1, "stream": False}, open(out, "w"))
PY
    curl -sS --max-time "$DMR_TIMEOUT_SECONDS" "$DMR_API_URL" \
        -H 'Content-Type: application/json' -d @"$WARM_PAYLOAD" >/dev/null 2>&1 || true
fi

if [ "$TRANSCRIPT_SIZE" -le "$CHUNK_CHARS" ]; then
    select_stage final
    FULL_PROMPT="${TMPDIR}/minutes_prompt.txt"
    build_prompt "$TRANSCRIPT_FILE" "$FULL_PROMPT" "$TRANSCRIPT_TYPE"
    run_model "$FULL_PROMPT" "$(final_directive)" "$OUTPUT_FILE"
else
    echo "Transcript is large (${TRANSCRIPT_SIZE} bytes); summarizing in local chunks first."
    split_transcript

    shopt -s nullglob
    CHUNK_FILES=("${TMPDIR}"/chunk_*.txt)
    shopt -u nullglob

    if [ "${#CHUNK_FILES[@]}" -eq 0 ]; then
        echo "Error: Unable to split transcript for chunked summarization." >&2
        exit 1
    fi

    # Two-pass, outline-guided map/reduce — the fallback for transcripts too big
    # for a single-shot call. Plain per-chunk summaries lose cross-cutting
    # structure (topics/framing/decisions spanning the whole meeting) because no
    # chunk sees the others — that produced shallow, miscategorized minutes. So:
    # PASS 1 builds a compact GLOBAL OUTLINE from lightweight per-chunk notes;
    # PASS 2 re-summarizes each chunk WITH that outline injected, so each chunk
    # is placed in the meeting's overall structure. Every call stays small, which
    # also keeps time-to-first-token low (streaming-friendly).

    # --- Pass 1: global outline ---
    echo "Pass 1/2: building a global outline from ${#CHUNK_FILES[@]} chunks..."
    OUTLINE_PARTS=()
    chunk_index=1
    for CHUNK_FILE in "${CHUNK_FILES[@]}"; do
        OUTLINE_PROMPT="${TMPDIR}/outline_prompt_${chunk_index}.txt"
        OUTLINE_OUT="${TMPDIR}/outline_part_${chunk_index}.md"
        build_summary_prompt "$CHUNK_FILE" "$OUTLINE_PROMPT"
        run_model "$OUTLINE_PROMPT" "From THIS transcript chunk, extract only a terse outline: the speakers/people who appear, the high-level topics touched, and anything stated as a decision or as a recommendation/suggestion (label which). A few Markdown bullets, no prose, no full sentences, invent nothing. ${LANG_INSTRUCTION}" "$OUTLINE_OUT"
        OUTLINE_PARTS+=("$OUTLINE_OUT")
        chunk_index=$((chunk_index + 1))
    done

    OUTLINE_CONCAT="${TMPDIR}/outline_concat.txt"
    GLOBAL_OUTLINE_FILE="${TMPDIR}/global_outline.md"
    { for f in "${OUTLINE_PARTS[@]}"; do cat "$f"; echo ""; done; } >"$OUTLINE_CONCAT"
    run_model "$OUTLINE_CONCAT" "Merge these per-chunk outline notes into ONE compact meeting outline with these labelled parts: Participants (the distinct speakers/people); Main topics (in the order discussed); Decisions vs recommendations (keep the two separate). Terse bullets, deduplicate, invent nothing. ${LANG_INSTRUCTION}" "$GLOBAL_OUTLINE_FILE"
    GLOBAL_OUTLINE="$(cat "$GLOBAL_OUTLINE_FILE" 2>/dev/null || true)"

    # --- Pass 2: detailed per-chunk summaries, guided by the outline ---
    echo "Pass 2/2: detailed summaries with global context..."
    SUMMARY_FILES=()
    chunk_index=1
    for CHUNK_FILE in "${CHUNK_FILES[@]}"; do
        CHUNK_PROMPT="${TMPDIR}/chunk_prompt_${chunk_index}.txt"
        CHUNK_OUTPUT="${TMPDIR}/chunk_summary_${chunk_index}.md"
        build_summary_prompt "$CHUNK_FILE" "$CHUNK_PROMPT"
        run_model "$CHUNK_PROMPT" "GLOBAL OUTLINE of the whole meeting (for context only):
${GLOBAL_OUTLINE}

Now condense THIS chunk into concise Markdown notes for later consolidation, placing its content within that overall structure. Capture every decision, action item, owner, due date, speaker attribution, number, risk, and open question, and keep decisions distinct from mere recommendations. No full minutes, no section headings, invent nothing, keep it brief, bullets only. ${LANG_INSTRUCTION}" "$CHUNK_OUTPUT"
        SUMMARY_FILES+=("$CHUNK_OUTPUT")
        chunk_index=$((chunk_index + 1))
    done

    # Reduce step: merge summaries hierarchically in small batches, but only
    # until everything fits in one final consolidation prompt. Batching keeps
    # every merge call as small and fast as the per-chunk calls (a flat
    # merge-everything-at-once prompt grows with meeting length and gets slow
    # and drop-prone); 4000 chars ~ two condenser outputs per merge.
    MERGE_BUDGET="${SPEECH_MINUTES_MERGE_BUDGET:-4000}"
    merge_round=1
    while [ "${#SUMMARY_FILES[@]}" -gt 1 ]; do
        combined_chars=0
        for SUMMARY_FILE in "${SUMMARY_FILES[@]}"; do
            combined_chars=$((combined_chars + $(wc -c <"$SUMMARY_FILE" | tr -d ' ')))
        done
        if [ "$combined_chars" -le "$MERGE_BUDGET" ]; then
            break
        fi

        echo "Consolidating ${#SUMMARY_FILES[@]} partial summaries (merge round ${merge_round})..."
        NEXT_FILES=()
        BATCH=()
        batch_chars=0
        batch_seq=1

        for SUMMARY_FILE in "${SUMMARY_FILES[@]}"; do
            file_chars=$(wc -c <"$SUMMARY_FILE" | tr -d ' ')
            # Flush once the batch holds at least two summaries and adding the
            # next one would exceed the budget. The "at least two" rule
            # guarantees each round makes progress even with large summaries.
            if [ "${#BATCH[@]}" -ge 2 ] && [ $((batch_chars + file_chars)) -gt "$MERGE_BUDGET" ]; then
                MERGE_OUTPUT="${TMPDIR}/merge_r${merge_round}_${batch_seq}.md"
                merge_summaries_file "$MERGE_OUTPUT" "${BATCH[@]}"
                NEXT_FILES+=("$MERGE_OUTPUT")
                batch_seq=$((batch_seq + 1))
                BATCH=()
                batch_chars=0
            fi
            BATCH+=("$SUMMARY_FILE")
            batch_chars=$((batch_chars + file_chars))
        done

        if [ "${#BATCH[@]}" -eq 1 ]; then
            NEXT_FILES+=("${BATCH[0]}")
        elif [ "${#BATCH[@]}" -ge 2 ]; then
            MERGE_OUTPUT="${TMPDIR}/merge_r${merge_round}_${batch_seq}.md"
            merge_summaries_file "$MERGE_OUTPUT" "${BATCH[@]}"
            NEXT_FILES+=("$MERGE_OUTPUT")
        fi

        if [ "${#NEXT_FILES[@]}" -ge "${#SUMMARY_FILES[@]}" ]; then
            echo "Error: summary consolidation is not converging; raise SPEECH_MINUTES_MERGE_BUDGET." >&2
            exit 1
        fi
        SUMMARY_FILES=("${NEXT_FILES[@]}")
        merge_round=$((merge_round + 1))
    done

    # Final step: produce the actual minutes document from all remaining
    # summaries, using the larger final output cap so the document is not
    # truncated.
    select_stage final
    FINAL_PROMPT="${TMPDIR}/final_minutes_prompt.txt"
    {
        cat "$PROMPT_FILE"
        echo ""
        echo "## Requested output type"
        echo ""
        echo "$TRANSCRIPT_TYPE"
        echo ""
        if [ -n "${GLOBAL_OUTLINE:-}" ]; then
            echo "## Meeting outline (overall structure — use to order and frame the document)"
            echo ""
            echo "$GLOBAL_OUTLINE"
            echo ""
        fi
        echo "## Consolidated summaries"
        echo ""
        for SUMMARY_FILE in "${SUMMARY_FILES[@]}"; do
            cat "$SUMMARY_FILE"
            echo ""
        done
    } >"$FINAL_PROMPT"
    run_model "$FINAL_PROMPT" "$(final_directive)" "$OUTPUT_FILE"
fi

echo "Minutes saved to: $OUTPUT_FILE"
