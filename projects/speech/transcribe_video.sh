#!/bin/bash
set -euo pipefail

# Usage: ./transcribe_video.sh <video_file> [language_code] [--stream|--batch] [--chunk-seconds seconds] [--diarize] [--diarize-engine pyannote|sortformer]
# Example: ./transcribe_video.sh my_video.mp4 en --diarize

if [ -z "${1:-}" ]; then
    echo "Usage: $0 <video_file> [language_code] [--stream|--batch] [--chunk-seconds seconds] [--diarize] [--diarize-engine pyannote|sortformer]"
    echo "Common language codes: auto, it, it-IT, en, en-US, en-GB"
    exit 1
fi

VIDEO_FILE="$1"
LANGUAGE="auto"
DIARIZE=false
DIARIZE_ENGINE="${SPEECH_DIARIZE_ENGINE:-pyannote}"
# Over-diarization controls. pyannote free-clusters and badly over-segments
# meeting audio (a 3-person, 47-min call produced 10-22 labels: a few real
# speakers plus crosstalk/backchannel fragments and one re-split voice). No
# num-speakers flag exists, so we curb it two ways:
# - cluster-threshold: measured HIGHER = fewer speakers (0.40->22, 0.715->10,
#   0.85->7), the OPPOSITE of what the CLI help claims. Default 0.85 collapses
#   most over-splitting while keeping the real speakers distinct. Raise toward
#   0.90+ to merge harder (risks fusing two real speakers); lower to split more.
# - min-speaker-seconds: post-filter that reassigns any speaker whose TOTAL
#   speech is below this floor to the temporally-nearest surviving speaker. Kills
#   the tiny phantom labels that survive at every threshold, without dropping any
#   transcript text. 0 disables.
# - VAD pre-filter: drops non-speech false alarms. On by default (measured: little
#   effect on this audio, but harmless); set SPEECH_DIARIZE_VAD_FILTER=false off.
# - min-silence: larger value merges adjacent segments into fewer/longer turns.
DIARIZE_VAD_FILTER="${SPEECH_DIARIZE_VAD_FILTER:-true}"
DIARIZE_CLUSTER_THRESHOLD="${SPEECH_DIARIZE_CLUSTER_THRESHOLD:-0.85}"
DIARIZE_MIN_SPEAKER_SECONDS="${SPEECH_DIARIZE_MIN_SPEAKER_SECONDS:-8}"
DIARIZE_MIN_SILENCE="${SPEECH_DIARIZE_MIN_SILENCE:-}"
# Batch (offline) decoding by default: more accurate than streaming and avoids
# dropped trailing words. Recorded files don't need streaming's low latency.
TRANSCRIBE_STREAM="${SPEECH_TRANSCRIBE_STREAM:-false}"
# ASR engine/model. qwen3 (Qwen3-ASR) handles Italian-with-English-jargon far
# better than nemotron; the 1.7B model is markedly more accurate than 0.6B at a
# near-identical real-time factor. --model only applies to the qwen3 engine.
ASR_ENGINE="${SPEECH_TRANSCRIBE_ENGINE:-qwen3}"
ASR_MODEL="${SPEECH_TRANSCRIBE_MODEL:-1.7B}"
# Context biasing ('speech transcribe --context') improves recognition of domain
# jargon and proper nouns. The default covers common cloud-native / security
# vocabulary; REPLACE the placeholder company names (Acme Corp, Example Labs)
# with your own recurring brands. SPEECH_TRANSCRIBE_CONTEXT is appended for
# per-meeting additions (e.g. participant names).
DEFAULT_ASR_CONTEXT="Riunione tecnica di cybersecurity e cloud-native security. Aziende e marchi: Acme Corp, Example Labs. Termini: cloud-native, Kubernetes, KubeVirt, container, hardened images, Docker, DevSecOps, Active Directory, API gateway, attack surface management, CTEM (continuous threat exposure management), OpenXDR, XDR, EDR, SIEM, SOC, hyperscaler, ISO 27001, pyannote, diarization. Normative e compliance: DORA, EBA, ACN, ENS, NIS2."
ASR_CONTEXT="$DEFAULT_ASR_CONTEXT"
if [ -n "${SPEECH_TRANSCRIBE_CONTEXT:-}" ]; then
    ASR_CONTEXT="${ASR_CONTEXT} ${SPEECH_TRANSCRIBE_CONTEXT}"
fi
CHUNK_SECONDS="${SPEECH_CHUNK_SECONDS:-60}"
TURN_MAX_SECONDS="${SPEECH_TURN_MAX_SECONDS:-30}"
TURN_MERGE_GAP_SECONDS="${SPEECH_TURN_MERGE_GAP_SECONDS:-1.0}"
# Wider padding so words straddling a diarization turn boundary aren't clipped.
TURN_PADDING_SECONDS="${SPEECH_TURN_PADDING_SECONDS:-0.40}"

shift || true
if [ "${1:-}" != "" ] && [[ ! "${1:-}" =~ ^-- ]]; then
    LANGUAGE="$1"
    shift || true
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --stream)
            TRANSCRIBE_STREAM=true
            shift
            ;;
        --batch)
            TRANSCRIBE_STREAM=false
            shift
            ;;
        --chunk-seconds)
            CHUNK_SECONDS="${2:-}"
            if [ -z "$CHUNK_SECONDS" ]; then
                echo "Error: --chunk-seconds requires a positive integer."
                exit 1
            fi
            shift 2
            ;;
        --diarize)
            DIARIZE=true
            shift
            ;;
        --diarize-engine)
            DIARIZE_ENGINE="${2:-}"
            if [ -z "$DIARIZE_ENGINE" ]; then
                echo "Error: --diarize-engine requires pyannote or sortformer."
                exit 1
            fi
            shift 2
            ;;
        *)
            echo "Error: Unknown argument '$1'."
            exit 1
            ;;
    esac
done

if [ ! -f "$VIDEO_FILE" ]; then
    echo "Error: File '$VIDEO_FILE' not found."
    exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "Error: ffmpeg is required. Install it with: brew install ffmpeg"
    exit 1
fi

if ! command -v speech >/dev/null 2>&1; then
    echo "Error: speech CLI is required."
    echo "Install it with: brew install soniqo/tap/speech"
    exit 1
fi

if ! [[ "$CHUNK_SECONDS" =~ ^[0-9]+$ ]] || [ "$CHUNK_SECONDS" -lt 10 ]; then
    echo "Error: chunk seconds must be an integer >= 10."
    exit 1
fi

if ! [[ "$TURN_MAX_SECONDS" =~ ^[0-9]+$ ]] || [ "$TURN_MAX_SECONDS" -lt 5 ]; then
    echo "Error: turn max seconds must be an integer >= 5."
    exit 1
fi

normalize_language() {
    case "$1" in
        auto) echo "" ;;
        it) echo "it-IT" ;;
        it-IT | en-US | en-GB) echo "$1" ;;
        en) echo "en-US" ;;
        *)
            echo "Error: Unsupported language '$1'. Use auto, it, it-IT, en, en-US, or en-GB." >&2
            return 1
            ;;
    esac
}

normalize_diarize_engine() {
    case "$1" in
        pyannote | sortformer) echo "$1" ;;
        *)
            echo "Error: Unsupported diarization engine '$1'. Use pyannote or sortformer." >&2
            return 1
            ;;
    esac
}

BASENAME=$(basename "$VIDEO_FILE")
NAME="${BASENAME%.*}"
OUTPUT_FILE="${NAME}.txt"
SPEECH_ERROR_LOG="${NAME}_speech_error.log"
DIARIZE_ERROR_LOG="${NAME}_diarization_error.log"
DIARIZE_STDOUT_LOG="${NAME}_diarization_output.log"
DIARIZE_RTTM_FILE="${NAME}_diarization.rttm"

TMPDIR=$(mktemp -d)
CHUNK_DIR="${TMPDIR}/chunks"
TURN_DIR="${TMPDIR}/turns"
mkdir -p "$CHUNK_DIR"
mkdir -p "$TURN_DIR"
AUDIO_FILE="${TMPDIR}/${NAME}_audio.wav"
RAW_OUTPUT="${TMPDIR}/${NAME}_speech_output.txt"
TRANSCRIPT_CHUNK_OUTPUT="${TMPDIR}/${NAME}_transcript_chunk.txt"
DIARIZE_OUTPUT="${TMPDIR}/${NAME}_diarization.rttm"
TURNS_FILE="${TMPDIR}/${NAME}_speaker_turns.tsv"
TURN_OUTPUT="${TMPDIR}/${NAME}_speaker_turn_output.txt"
TURN_TEXT="${TMPDIR}/${NAME}_speaker_turn_text.txt"

cleanup() {
    rm -rf "$TMPDIR"
}
trap cleanup EXIT INT TERM

ASR_LANGUAGE="$(normalize_language "$LANGUAGE")"
DIARIZE_ENGINE="$(normalize_diarize_engine "$DIARIZE_ENGINE")"

# Build the speech-CLI transcription command into SPEECH_CMD for a given file,
# shared by the chunked and per-turn paths so engine/model/context/language stay
# consistent.
build_asr_cmd() {
    local file="$1"
    SPEECH_CMD=(speech transcribe "$file" --engine "$ASR_ENGINE")
    if [ "$ASR_ENGINE" = "qwen3" ] && [ -n "$ASR_MODEL" ]; then
        SPEECH_CMD+=(--model "$ASR_MODEL")
    fi
    if [ -n "$ASR_LANGUAGE" ]; then
        SPEECH_CMD+=(--language "$ASR_LANGUAGE")
    fi
    if [ -n "$ASR_CONTEXT" ]; then
        SPEECH_CMD+=(--context "$ASR_CONTEXT")
    fi
    if [ "$TRANSCRIBE_STREAM" = true ]; then
        SPEECH_CMD+=(--stream)
    fi
    if [ -n "${SPEECH_TRANSCRIBE_EXTRA_ARGS:-}" ]; then
        local extra
        # shellcheck disable=SC2206
        extra=($SPEECH_TRANSCRIBE_EXTRA_ARGS)
        SPEECH_CMD+=("${extra[@]}")
    fi
}

# One decode of the source, shaped for the path that follows: the diarize path
# needs the single full-file WAV (diarization + per-turn extraction); the
# non-diarize path needs only fixed-size segments, so it segments directly in
# the same decode instead of extracting a full WAV it would never use.
if [ "$DIARIZE" = true ]; then
    echo "Step 1: Extracting audio from $VIDEO_FILE..."
    ffmpeg \
        -i "$VIDEO_FILE" \
        -vn \
        -ar 16000 \
        -ac 1 \
        -c:a pcm_s16le \
        "$AUDIO_FILE" \
        -y
else
    echo "Step 1: Extracting and segmenting audio from $VIDEO_FILE..."
    ffmpeg \
        -i "$VIDEO_FILE" \
        -vn \
        -ar 16000 \
        -ac 1 \
        -c:a pcm_s16le \
        -f segment \
        -segment_time "$CHUNK_SECONDS" \
        -reset_timestamps 1 \
        "${CHUNK_DIR}/${NAME}_chunk_%03d.wav" \
        -y
fi

if [ "$DIARIZE" = false ]; then
shopt -s nullglob
CHUNK_FILES=("${CHUNK_DIR}"/*.wav)
shopt -u nullglob

if [ "${#CHUNK_FILES[@]}" -eq 0 ]; then
    echo "Error: ffmpeg produced no audio chunks."
    exit 1
fi

echo "Step 2: Transcribing ${#CHUNK_FILES[@]} audio chunk(s) with ${ASR_ENGINE} ASR..."
: >"$OUTPUT_FILE"

chunk_index=1
for CHUNK_FILE in "${CHUNK_FILES[@]}"; do
    printf '  Chunk %d/%d: %s\n' "$chunk_index" "${#CHUNK_FILES[@]}" "$(basename "$CHUNK_FILE")"
    build_asr_cmd "$CHUNK_FILE"

    if ! "${SPEECH_CMD[@]}" >"$RAW_OUTPUT" 2>"$SPEECH_ERROR_LOG"; then
        echo "Error: ${ASR_ENGINE} transcription failed on chunk $chunk_index."
        echo "speech command: ${SPEECH_CMD[*]}"
        echo "Error log saved to: $SPEECH_ERROR_LOG"
        echo "Try a smaller chunk size, for example: --chunk-seconds 30"
        exit 1
    fi

    awk '
        /^\[FINAL\] / {
            sub(/^\[FINAL\] /, "")
            print
            next
        }
        /^Result: / {
            sub(/^Result: /, "")
            print
            next
        }
    ' "$RAW_OUTPUT" >"$TRANSCRIPT_CHUNK_OUTPUT"

    if [ ! -s "$TRANSCRIPT_CHUNK_OUTPUT" ]; then
        echo "Error: ${ASR_ENGINE} transcription produced no output on chunk $chunk_index."
        echo "speech command: ${SPEECH_CMD[*]}"
        echo "Error log saved to: $SPEECH_ERROR_LOG"
        exit 1
    fi

    cat "$TRANSCRIPT_CHUNK_OUTPUT" >>"$OUTPUT_FILE"
    printf '\n\n' >>"$OUTPUT_FILE"
    chunk_index=$((chunk_index + 1))
done

rm -f "$SPEECH_ERROR_LOG"
fi

if [ "$DIARIZE" = true ]; then
    echo "Step 2: Running full-file speaker diarization (Engine: $DIARIZE_ENGINE)..."
    : >"$DIARIZE_OUTPUT"
    : >"$DIARIZE_STDOUT_LOG"

    DIARIZE_CMD=(speech diarize "$AUDIO_FILE" --engine "$DIARIZE_ENGINE" --rttm)
    if [ "$DIARIZE_VAD_FILTER" = true ]; then
        DIARIZE_CMD+=(--vad-filter)
    fi
    if [ -n "$DIARIZE_CLUSTER_THRESHOLD" ]; then
        DIARIZE_CMD+=(--cluster-threshold "$DIARIZE_CLUSTER_THRESHOLD")
    fi
    if [ -n "$DIARIZE_MIN_SILENCE" ]; then
        DIARIZE_CMD+=(--min-silence "$DIARIZE_MIN_SILENCE")
    fi
    echo "  Diarization command: ${DIARIZE_CMD[*]}"
    if ! "${DIARIZE_CMD[@]}" >"$DIARIZE_STDOUT_LOG" 2>"$DIARIZE_ERROR_LOG"; then
        echo "Error: Speaker diarization failed."
        echo "speech command: ${DIARIZE_CMD[*]}"
        echo "Output log saved to: $DIARIZE_STDOUT_LOG"
        echo "Error log saved to: $DIARIZE_ERROR_LOG"
        if [ "$DIARIZE_ENGINE" = "sortformer" ]; then
            echo "Sortformer uses CoreML and may fail on memory allocation; retry with --diarize-engine pyannote."
        fi
        exit 1
    fi

    awk '/^SPEAKER / { print }' "$DIARIZE_STDOUT_LOG" >"$DIARIZE_OUTPUT"

    if [ ! -s "$DIARIZE_OUTPUT" ]; then
        echo "Error: Speaker diarization produced no RTTM speaker segments."
        echo "speech command: ${DIARIZE_CMD[*]}"
        echo "Output log saved to: $DIARIZE_STDOUT_LOG"
        echo "Error log saved to: $DIARIZE_ERROR_LOG"
        if [ "$DIARIZE_ENGINE" = "sortformer" ]; then
            echo "Retry with --diarize-engine pyannote; it is the default and is better suited for offline meeting files."
        fi
        exit 1
    fi

    # Consolidate over-diarization: reassign segments of any speaker below the
    # total-duration floor to the temporally-nearest surviving speaker. This
    # removes the tiny crosstalk/backchannel phantom labels (which persist at
    # every cluster threshold) while preserving their transcript text.
    if [ "$DIARIZE_MIN_SPEAKER_SECONDS" != 0 ]; then
        if ! python3 - "$DIARIZE_OUTPUT" "$DIARIZE_MIN_SPEAKER_SECONDS" <<'PY'
import sys

path, floor = sys.argv[1], float(sys.argv[2])
segs = []
with open(path) as f:
    for line in f:
        p = line.split()
        if len(p) < 8 or p[0] != "SPEAKER":
            continue
        # [start, end, speaker, field_list]
        segs.append([float(p[3]), float(p[3]) + float(p[4]), p[7], p])

totals = {}
for s in segs:
    totals[s[2]] = totals.get(s[2], 0.0) + (s[1] - s[0])
majors = {spk for spk, t in totals.items() if t >= floor}

# Only filter if there is at least one major speaker and something to drop.
if majors and len(majors) < len(totals):
    major_segs = [(s[0], s[1], s[2]) for s in segs if s[2] in majors]

    def nearest(start, end):
        best, best_d = None, None
        for ms, me, msp in major_segs:
            d = ms - end if end < ms else (start - me if start > me else 0.0)
            if best_d is None or d < best_d:
                best, best_d = msp, d
        return best

    moved = 0
    for s in segs:
        if s[2] not in majors:
            nb = nearest(s[0], s[1])
            if nb is not None:
                s[3][7] = nb
                s[2] = nb
                moved += 1
    segs.sort(key=lambda x: x[0])
    with open(path, "w") as f:
        for s in segs:
            f.write(" ".join(s[3]) + "\n")
    sys.stderr.write(
        "  Consolidated diarization: %d speakers -> %d "
        "(reassigned %d phantom segments under %gs)\n"
        % (len(totals), len(majors), moved, floor)
    )
else:
    sys.stderr.write("  Diarization: %d speaker(s), no phantom labels to filter\n" % len(totals))
PY
        then
            echo "Warning: phantom-speaker consolidation failed; using raw diarization." >&2
        fi
    fi

    cp "$DIARIZE_OUTPUT" "$DIARIZE_RTTM_FILE"

    awk \
        -v gap="$TURN_MERGE_GAP_SECONDS" \
        -v max_duration="$TURN_MAX_SECONDS" \
        -v pad="$TURN_PADDING_SECONDS" '
        function ts(seconds,    h,m,s) {
            h = int(seconds / 3600)
            m = int((seconds % 3600) / 60)
            s = seconds - (h * 3600) - (m * 60)
            return sprintf("%02d:%02d:%06.3f", h, m, s)
        }
        function emit() {
            if (speaker == "") {
                return
            }
            padded_start = start - pad
            if (padded_start < 0) {
                padded_start = 0
            }
            padded_duration = (end - padded_start) + pad
            printf "%s\t%.3f\t%.3f\t%s\t%s\n", speaker, padded_start, padded_duration, ts(start), ts(end)
        }
        /^SPEAKER / {
            current_start = $4 + 0
            current_end = current_start + ($5 + 0)
            current_speaker = $8

            if (speaker == "") {
                speaker = current_speaker
                start = current_start
                end = current_end
                next
            }

            if (current_speaker == speaker && current_start - end <= gap && current_end - start <= max_duration) {
                if (current_end > end) {
                    end = current_end
                }
                next
            }

            emit()
            speaker = current_speaker
            start = current_start
            end = current_end
        }
        END {
            emit()
        }
    ' "$DIARIZE_OUTPUT" >"$TURNS_FILE"

    if [ ! -s "$TURNS_FILE" ]; then
        echo "Error: Unable to build speaker turns from diarization output."
        echo "RTTM saved to: $DIARIZE_RTTM_FILE"
        exit 1
    fi

    echo "Step 3: Transcribing speaker turns with ${ASR_ENGINE} ASR..."
    : >"$OUTPUT_FILE"
    {
        echo "# Speaker-attributed transcript"
        echo ""
        echo "Map speaker labels manually before creating meeting minutes, for example:"
        echo "speaker_0 = Matteo"
        echo "speaker_1 = Michele"
        echo "speaker_2 = Customer"
        echo ""
        echo "---"
        echo ""
    } >>"$OUTPUT_FILE"

    turn_index=1
    total_turns=$(wc -l <"$TURNS_FILE" | tr -d ' ')
    while IFS=$'\t' read -r speaker start duration start_label end_label; do
        TURN_AUDIO="${TURN_DIR}/turn_$(printf '%04d' "$turn_index").wav"
        printf '  Turn %d/%d: %s [%s - %s]\n' "$turn_index" "$total_turns" "$speaker" "$start_label" "$end_label"

        ffmpeg \
            -ss "$start" \
            -t "$duration" \
            -i "$AUDIO_FILE" \
            -ar 16000 \
            -ac 1 \
            -c:a pcm_s16le \
            "$TURN_AUDIO" \
            -y >/dev/null 2>&1

        build_asr_cmd "$TURN_AUDIO"

        if ! "${SPEECH_CMD[@]}" >"$TURN_OUTPUT" 2>"$SPEECH_ERROR_LOG"; then
            echo "Error: ${ASR_ENGINE} transcription failed on speaker turn $turn_index."
            echo "speech command: ${SPEECH_CMD[*]}"
            echo "Error log saved to: $SPEECH_ERROR_LOG"
            echo "RTTM saved to: $DIARIZE_RTTM_FILE"
            exit 1
        fi

        awk '
            /^\[FINAL\] / {
                sub(/^\[FINAL\] /, "")
                print
                next
            }
            /^Result: / {
                sub(/^Result: /, "")
                print
                next
            }
        ' "$TURN_OUTPUT" >"$TURN_TEXT"

        if [ -s "$TURN_TEXT" ]; then
            {
                printf '[%s - %s] %s: ' "$start_label" "$end_label" "$speaker"
                tr '\n' ' ' <"$TURN_TEXT" | sed -E 's/[[:space:]]+$//'
                printf '\n\n'
            } >>"$OUTPUT_FILE"
        fi

        turn_index=$((turn_index + 1))
    done <"$TURNS_FILE"

    rm -f "$DIARIZE_ERROR_LOG"
    rm -f "$DIARIZE_STDOUT_LOG"
    rm -f "$SPEECH_ERROR_LOG"
fi

echo "Transcription complete!"
echo "Transcript saved to: $OUTPUT_FILE"
