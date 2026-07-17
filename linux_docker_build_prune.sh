#!/usr/bin/env bash
set -Eeuo pipefail

# Configurable through environment variables.
readonly CACHE_MAX_AGE="${CACHE_MAX_AGE:-168h}"
readonly LOG_DIR="${LOG_DIR:-/tmp}"
readonly TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
readonly LOG_FILE="${LOG_DIR}/docker-build-prune-${TIMESTAMP}.log"

# Resolve Docker from DOCKER_BIN or the current PATH.
docker_candidate="${DOCKER_BIN:-docker}"
if [[ "$docker_candidate" == */* ]]; then
    DOCKER_BIN="$docker_candidate"
else
    DOCKER_BIN="$(command -v "$docker_candidate" 2>/dev/null || true)"
fi
readonly DOCKER_BIN
unset docker_candidate

mkdir -p -- "$LOG_DIR"
touch -- "$LOG_FILE"

# Display output while also saving it to the log.
exec > >(tee -a "$LOG_FILE") 2>&1

finish() {
    local status=$?
    printf '\nFinished: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf 'Exit status: %d\n' "$status"
    printf 'Log saved to: %s\n' "$LOG_FILE"
}
trap finish EXIT

if [[ -z "$DOCKER_BIN" || ! -x "$DOCKER_BIN" ]]; then
    printf 'Error: Docker was not found. Install Docker or set DOCKER_BIN.\n' >&2
    exit 127
fi

# This also verifies that the selected daemon is reachable and permitted.
docker_info="$("$DOCKER_BIN" info --format '{{.DockerRootDir}}|{{.Driver}}')"
IFS='|' read -r DOCKER_ROOT DOCKER_DRIVER <<< "$docker_info"
readonly DOCKER_ROOT DOCKER_DRIVER
unset docker_info

if [[ -z "$DOCKER_ROOT" ]]; then
    printf 'Error: Docker did not report a data-root path.\n' >&2
    exit 1
fi

# Detect whether the selected Docker endpoint is local to this Linux host.
DOCKER_CONTEXT="$("$DOCKER_BIN" context show 2>/dev/null || true)"
DOCKER_ENDPOINT="${DOCKER_HOST:-}"
if [[ -z "$DOCKER_ENDPOINT" && -n "$DOCKER_CONTEXT" ]]; then
    DOCKER_ENDPOINT="$(
        "$DOCKER_BIN" context inspect "$DOCKER_CONTEXT" \
            --format '{{(index .Endpoints "docker").Host}}' 2>/dev/null || true
    )"
fi
readonly DOCKER_CONTEXT DOCKER_ENDPOINT

show_usage() {
    "$DOCKER_BIN" system df

    if [[ "$DOCKER_ENDPOINT" == unix://* ]]; then
        if ! df -h -- "$DOCKER_ROOT"; then
            printf 'Warning: Docker data root is not accessible at %s\n' \
                "$DOCKER_ROOT" >&2
        fi
    else
        printf 'Filesystem usage skipped: Docker endpoint is remote or unknown (%s).\n' \
            "${DOCKER_ENDPOINT:-unknown}"
    fi
}

printf 'Docker build-cache cleanup\n'
printf 'Host: %s\n' "$(hostname)"
printf 'Started: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
printf 'Docker CLI: %s\n' "$DOCKER_BIN"
printf 'Docker context: %s\n' "${DOCKER_CONTEXT:-unknown}"
printf 'Docker endpoint: %s\n' "${DOCKER_ENDPOINT:-unknown}"
printf 'Docker data root: %s\n' "$DOCKER_ROOT"
printf 'Docker storage driver: %s\n' "$DOCKER_DRIVER"
printf 'Removing unused build cache older than: %s\n' "$CACHE_MAX_AGE"
printf 'Log file: %s\n\n' "$LOG_FILE"

printf '%s\n' '--- Usage before cleanup ---'
show_usage

printf '\n%s\n' '--- Pruning build cache ---'
"$DOCKER_BIN" builder prune \
    --all \
    --force \
    --filter "until=${CACHE_MAX_AGE}"

printf '\n%s\n' '--- Usage after cleanup ---'
show_usage
