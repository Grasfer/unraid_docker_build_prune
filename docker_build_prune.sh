#!/usr/bin/env bash
set -Eeuo pipefail

# Configurable through environment variables.
readonly DOCKER_BIN="/usr/bin/docker"
readonly CACHE_MAX_AGE="${CACHE_MAX_AGE:-168h}"
readonly LOG_DIR="${LOG_DIR:-/tmp}"
readonly TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
readonly LOG_FILE="${LOG_DIR}/docker-build-prune-${TIMESTAMP}.log"

mkdir -p -- "$LOG_DIR"
touch -- "$LOG_FILE"

# Display output in Unraid while also saving it to the log.
exec > >(tee -a "$LOG_FILE") 2>&1

finish() {
    local status=$?
    printf '\nFinished: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf 'Exit status: %d\n' "$status"
    printf 'Log saved to: %s\n' "$LOG_FILE"
}
trap finish EXIT

if [[ ! -x "$DOCKER_BIN" ]]; then
    printf 'Error: Docker was not found at %s\n' "$DOCKER_BIN" >&2
    exit 127
fi

printf 'Docker build-cache cleanup\n'
printf 'Host: %s\n' "$(hostname)"
printf 'Started: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
printf 'Removing unused build cache older than: %s\n' "$CACHE_MAX_AGE"
printf 'Log file: %s\n\n' "$LOG_FILE"

printf '%s\n' '--- Usage before cleanup ---'
"$DOCKER_BIN" system df
df -h /var/lib/docker

printf '\n%s\n' '--- Pruning build cache ---'
"$DOCKER_BIN" builder prune \
    --all \
    --force \
    --filter "until=${CACHE_MAX_AGE}"

printf '\n%s\n' '--- Usage after cleanup ---'
"$DOCKER_BIN" system df
df -h /var/lib/docker
