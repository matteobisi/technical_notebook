#!/bin/bash
set -euo pipefail

# speech.sh — interactive helper for native speech CLI transcription and local minutes.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}ℹ ${RESET}${*}"; }
success() { echo -e "${GREEN}${BOLD}✔ ${RESET}${*}"; }
warn()    { echo -e "${YELLOW}${BOLD}⚠ ${RESET}${*}"; }
error()   { echo -e "${RED}${BOLD}✖ ${RESET}${*}" >&2; }
step()    { echo -e "\n${BOLD}${*}${RESET}"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

install_with_brew() {
    local command_name="$1"
    local package_name="$2"

    if command -v "$command_name" >/dev/null 2>&1; then
        return 0
    fi

    error "'${command_name}' not found."
    echo ""
    echo "  Install it with:"
    echo "    brew install ${package_name}"
    echo ""

    if ! command -v brew >/dev/null 2>&1; then
        error "Homebrew is not installed or not in PATH."
        exit 1
    fi

    echo -n "  Install ${command_name} now with Homebrew? [y/N]: "
    read -r INSTALL_CONFIRM
    INSTALL_CONFIRM="${INSTALL_CONFIRM:-n}"

    if [[ ! "$INSTALL_CONFIRM" =~ ^[Yy]$ ]]; then
        error "${command_name} is required."
        exit 1
    fi

    brew install "$package_name"
    success "${command_name} installed."
}

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║    🎙  Speech Transcription & Minutes    ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${RESET}"
echo ""
echo "  Runs native Apple Silicon transcription via the speech CLI."
echo "  Optionally creates minutes locally with Docker Model Runner."
echo "  No audio, transcript, or prompt leaves your machine."
echo ""

install_with_brew "speech" "soniqo/tap/speech"
install_with_brew "ffmpeg" "ffmpeg"

step "Step 1/4 — Input file"
VIDEO_FILE=""
while [ -z "$VIDEO_FILE" ]; do
    echo -n "  Path to the meeting video or audio file: "
    read -r VIDEO_FILE
    VIDEO_FILE="${VIDEO_FILE/#\~/$HOME}"

    if [ -z "$VIDEO_FILE" ]; then
        warn "File path cannot be empty. Please try again."
        continue
    fi

    if [ ! -f "$VIDEO_FILE" ]; then
        error "File not found: $VIDEO_FILE"
        VIDEO_FILE=""
    fi
done
success "File: $VIDEO_FILE"

step "Step 2/4 — Language"
echo ""
echo "  Common codes: auto  it  it-IT  en  en-US  en-GB"
echo ""

LANGUAGE=""
while [ -z "$LANGUAGE" ]; do
    echo -n "  Language code (default: auto): "
    read -r LANGUAGE
    LANGUAGE="${LANGUAGE:-auto}"

    case "$LANGUAGE" in
        auto | it | it-IT | en | en-US | en-GB) ;;
        *)
            warn "Use auto, it, it-IT, en, en-US, or en-GB."
            LANGUAGE=""
            ;;
    esac
done
success "Language: $LANGUAGE"

step "Step 3/4 — Speaker diarization"
echo ""
echo "  Diarization identifies who spoke when, then transcribes each speaker turn."
echo "  The output uses speaker_N labels so you can map them to real names manually."
echo ""

DIARIZE="n"
echo -n "  Add speaker diarization? [y/N]: "
read -r DIARIZE
DIARIZE="${DIARIZE:-n}"

ARGS=("$VIDEO_FILE" "$LANGUAGE")

if [[ "$DIARIZE" =~ ^[Yy]$ ]]; then
    # sortformer is broken on this build of the speech CLI: its CoreML model has a
    # fixed input window (expects 1x3048x128, gets 1x112x128) and fails every chunk,
    # producing an empty RTTM. Only pyannote works for offline meeting files, so we
    # no longer offer the engine choice. transcribe_video.sh still accepts
    # --diarize-engine for power users if the binary is ever fixed.
    ARGS+=(--diarize --diarize-engine pyannote)
    success "Diarization: pyannote"
else
    success "Diarization: disabled"
fi

echo ""
info "Starting transcription..."
echo ""

"${SCRIPT_DIR}/transcribe_video.sh" "${ARGS[@]}"

BASENAME="$(basename "$VIDEO_FILE")"
TRANSCRIPT_FILE="${BASENAME%.*}.txt"

step "Step 4/4 — Local minutes"
echo ""
echo "  Minutes generation uses Docker Desktop Model Runner and Docker Agent locally."
# Display-only fallback: keep in sync with the MODEL default in minutes.sh.
echo "  Default model: ${SPEECH_MINUTES_MODEL:-huggingface.co/bartowski/qwen2.5-14b-instruct-gguf}"
echo ""

CREATE_MINUTES="n"
echo -n "  Create minutes from the transcript now? [y/N]: "
read -r CREATE_MINUTES
CREATE_MINUTES="${CREATE_MINUTES:-n}"

if [[ "$CREATE_MINUTES" =~ ^[Yy]$ ]]; then
    if [ ! -f "$TRANSCRIPT_FILE" ]; then
        error "Transcript not found: $TRANSCRIPT_FILE"
        exit 1
    fi

    MINUTES_TYPE="webinar"
    if [[ "$DIARIZE" =~ ^[Yy]$ ]]; then
        MINUTES_TYPE="meeting"
        echo ""
        warn "Before minutes generation, map speaker_N labels to real names if you know them."
        echo "  Transcript: $TRANSCRIPT_FILE"
        echo ""
        EDIT_MAPPING="y"
        echo -n "  Open the transcript to edit speaker mapping now? [Y/n]: "
        read -r EDIT_MAPPING
        EDIT_MAPPING="${EDIT_MAPPING:-y}"
        if [[ "$EDIT_MAPPING" =~ ^[Yy]$ ]]; then
            if [ -n "${EDITOR:-}" ]; then
                "$EDITOR" "$TRANSCRIPT_FILE"
            elif command -v open >/dev/null 2>&1; then
                open -e "$TRANSCRIPT_FILE"
                echo -n "  Press Enter after saving the transcript mapping..."
                read -r _
            else
                warn "No editor found. Edit $TRANSCRIPT_FILE manually before rerunning minutes.sh if needed."
            fi
        fi
    fi

    echo ""
    echo "  Proper-noun corrections fix names the transcription garbles in the minutes."
    echo "  Commonly garbled product names (Auth0, KubeVirt, Snyk, ...) are corrected automatically."
    echo "  Add per-meeting names here as 'wrong => right', separated by ';'."
    echo "  Example: Acme Crop, Acme Corpse => Acme Corp; Jhon => John"
    echo ""
    echo -n "  Extra corrections (leave empty for none): "
    read -r EXTRA_CORRECTIONS

    if [ -n "$EXTRA_CORRECTIONS" ]; then
        SPEECH_MINUTES_CORRECTIONS="$EXTRA_CORRECTIONS" "${SCRIPT_DIR}/minutes.sh" "$TRANSCRIPT_FILE" --type "$MINUTES_TYPE"
    else
        "${SCRIPT_DIR}/minutes.sh" "$TRANSCRIPT_FILE" --type "$MINUTES_TYPE"
    fi
fi

echo ""
success "Done."
