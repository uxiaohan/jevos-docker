#!/bin/sh
set -eu

PORT="${PORT:-8017}"
THREADS="${THREADS:-}"
MODEL_DIR="/opt/jev/model"

log() { printf '[jevos] %s\n' "$*" >&2; }

if [ -n "${JEV_API_KEY:-}" ]; then
    AUTH="key ${JEV_API_KEY}"
else
    AUTH="no auth"
fi

# The binary counts host CPUs and ignores a cgroup CPU quota, so a container
# limited to 2 cores would still start 8 threads and oversubscribe.
# nproc already honours an affinity mask; take the quota into account too.
detect_threads() {
    n=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
    if [ -r /sys/fs/cgroup/cpu.max ]; then
        read -r quota period < /sys/fs/cgroup/cpu.max || true
        if [ "$quota" != "max" ] && [ "${period:-0}" -gt 0 ] 2>/dev/null; then
            q=$((quota / period))
            if [ "$q" -lt 1 ]; then q=1; fi
            if [ "$q" -lt "$n" ]; then n=$q; fi
        fi
    elif [ -r /sys/fs/cgroup/cpu/cpu.cfs_quota_us ]; then
        q=$(cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us 2>/dev/null || echo -1)
        p=$(cat /sys/fs/cgroup/cpu/cpu.cfs_period_us 2>/dev/null || echo 100000)
        if [ "$q" -gt 0 ] 2>/dev/null && [ "$p" -gt 0 ]; then
            q=$((q / p))
            if [ "$q" -lt 1 ]; then q=1; fi
            if [ "$q" -lt "$n" ]; then n=$q; fi
        fi
    fi
    printf '%s' "$n"
}

[ -n "$THREADS" ] || THREADS=$(detect_threads)

log "listening on http://0.0.0.0:${PORT}"
log "auth: ${AUTH}"

set -- --threads "$THREADS"
/opt/jev/jev serve --host 0.0.0.0 --port "$PORT" --model-dir "$MODEL_DIR" "$@" &
pid=$!

trap 'kill -TERM "$pid" 2>/dev/null || true' TERM INT

i=0
healthy=0
while [ "$i" -lt 120 ]; do
    if curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
        healthy=1
        break
    fi
    kill -0 "$pid" 2>/dev/null || break
    i=$((i + 1))
    sleep 1
done

if [ "$healthy" -eq 1 ]; then
    log "healthy"
else
    log "not healthy after ${i}s"
fi

set +e
wait "$pid"
exit $?
