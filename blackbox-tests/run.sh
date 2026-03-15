#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Blackbox Performance Test Runner
#
# Runs the same test suite against both Snatch (Erlang) and rnatch (Rust).
# Results are printed side-by-side for comparison.
#
# Usage:
#   ./run.sh rust          # Test rnatch only
#   ./run.sh erlang        # Test snatch only
#   ./run.sh both          # Test both and compare
#   ./run.sh rust --xmpp   # Test only XMPP tests
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

SUT="${1:-both}"
shift || true
EXTRA_ARGS=("$@")

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() { echo -e "${BLUE}[blackbox]${NC} $*"; }
ok()  { echo -e "${GREEN}[  OK  ]${NC} $*"; }
err() { echo -e "${RED}[FAIL]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

# --- Prerequisites ---
check_prereqs() {
    log "Checking prerequisites..."
    command -v docker >/dev/null 2>&1 || { err "docker not found"; exit 1; }
    command -v python3 >/dev/null 2>&1 || { err "python3 not found"; exit 1; }
    ok "Prerequisites met"
}

# --- Docker Services ---
start_services() {
    log "Starting Docker services..."
    # Ensure stale containers/ports from previous interrupted runs are cleared.
    docker compose down -v >/dev/null 2>&1 || true
    docker compose up -d --wait 2>&1 || docker compose up -d

    log "Waiting for services to be healthy..."
    sleep 15

    # Register XMPP users
    docker exec bb-ejabberd ejabberdctl register bbuser localhost bbpass 2>/dev/null || true
    docker exec bb-ejabberd ejabberdctl register bbuser2 localhost bbpass2 2>/dev/null || true

    # Ensure Kafka topics exist from host side (same network path as tests/bot).
    setup_kafka_topics_host || warn "Kafka topic setup via host client failed (continuing)"

    ok "Services ready"
}

setup_kafka_topics_host() {
    python3 - <<'PY'
import time
from confluent_kafka.admin import AdminClient, NewTopic

bootstrap = "127.0.0.1:49092"
topics = ["bb-request", "bb-response"]
deadline = time.time() + 45
last_error = None

while time.time() < deadline:
    try:
        admin = AdminClient({"bootstrap.servers": bootstrap})
        md = admin.list_topics(timeout=10)
        existing = set(md.topics.keys())
        missing = [t for t in topics if t not in existing]
        if not missing:
            print("Kafka topics already present")
            raise SystemExit(0)

        futures = admin.create_topics(
            [NewTopic(t, num_partitions=1, replication_factor=1) for t in missing],
            request_timeout=10,
        )
        for _, fut in futures.items():
            try:
                fut.result(10)
            except Exception as exc:
                last_error = exc

        md2 = admin.list_topics(timeout=10)
        existing2 = set(md2.topics.keys())
        if all(t in existing2 for t in topics):
            print("Kafka topics created")
            raise SystemExit(0)
    except Exception as exc:
        last_error = exc
    time.sleep(2)

print(f"Kafka topic setup timed out: {last_error}")
raise SystemExit(1)
PY
}

stop_services() {
    log "Stopping Docker services..."
    docker compose down -v 2>/dev/null || true
}

# --- Python Environment ---
setup_python() {
    if [ ! -d ".venv" ]; then
        log "Creating Python virtual environment..."
        python3 -m venv .venv
    fi
    source .venv/bin/activate
    pip install -q -r requirements.txt 2>/dev/null
    ok "Python environment ready"
}

# --- Build Echo Bots ---
build_rust_bot() {
    log "Building Rust echo bot..."
    (cd bots/rust && cargo build --release 2>&1) || { err "Rust bot build failed"; return 1; }
    ok "Rust echo bot built"
}

build_erlang_bot() {
    log "Building Erlang echo bot..."
    [ -d "bots/erlang" ] || { warn "bots/erlang dir missing, skipping Erlang build"; return 1; }

    if command -v rebar3 >/dev/null 2>&1; then
        (cd bots/erlang && rebar3 escriptize 2>&1) || { warn "Erlang bot build failed"; return 1; }
        ok "Erlang echo bot built (local rebar3)"
        return 0
    fi

    warn "rebar3 not found, using Docker builder for Erlang echo bot"
    build_erlang_bot_docker
}

build_erlang_bot_docker() {
    command -v docker >/dev/null 2>&1 || { err "docker not found"; return 1; }

    # Prefer executor localbuilder image when available.
    if docker image inspect executor-builder:latest >/dev/null 2>&1; then
        log "Building Erlang echo bot with executor-builder:latest"
        if docker run --rm \
            -v "$SCRIPT_DIR/bots/erlang:/opt/snatch-echo" \
            -w /opt/snatch-echo \
            executor-builder:latest \
            sh -lc "env -u ERL_COMPILER_OPTIONS rebar3 escriptize" 2>&1; then
            chmod +x bots/erlang/_build/default/bin/snatch_echo 2>/dev/null || true
            ok "Erlang echo bot built (executor-builder:latest)"
            return 0
        fi
        warn "executor-builder path failed, falling back to Dockerfile build"
    fi

    local image="${BB_ERLANG_BUILDER_IMAGE:-rnatch/snatch-echo-builder:latest}"
    local container=""

    log "Building snatch echo bot image: ${image}"
    docker build -t "$image" bots/erlang 2>&1 || { err "Docker builder image build failed"; return 1; }

    log "Extracting Erlang build artifacts from Docker image..."
    container="$(docker create "$image")" || { err "Failed to create temporary Docker container"; return 1; }
    rm -rf bots/erlang/_build
    if ! docker cp "$container:/opt/snatch-echo/_build" "bots/erlang/_build"; then
        docker rm "$container" >/dev/null 2>&1 || true
        err "Failed to copy _build artifacts from Docker builder"
        return 1
    fi
    docker rm "$container" >/dev/null 2>&1 || true

    ok "Erlang echo bot built (Docker builder)"
}

# --- Run Echo Bot ---
start_rust_bot() {
    log "Starting Rust echo bot..."
    local rust_mode="${BB_RUST_BOT_MODE:-all}"
    local rust_transport_flag="--all"
    if [ "$rust_mode" = "xmpp_only" ]; then
        rust_transport_flag="--xmpp-comp"
    fi

    bots/rust/target/release/rnatch-echo-bot "$rust_transport_flag" \
        --xmpp-host "${BB_XMPP_HOST:-localhost}" \
        --xmpp-port "${BB_XMPP_COMP_PORT:-45275}" \
        --xmpp-domain "${BB_XMPP_COMP_DOMAIN:-echo.localhost}" \
        --xmpp-password "${BB_XMPP_COMP_PASSWORD:-secret}" \
        --rabbitmq-host "${BB_RABBITMQ_HOST:-localhost}" \
        --rabbitmq-port "${BB_RABBITMQ_PORT:-45672}" \
        --kafka-bootstrap "${BB_KAFKA_BOOTSTRAP:-127.0.0.1:49092}" \
        --sqs-endpoint "${BB_AWS_ENDPOINT:-http://localhost:44566}" &
    BOT_PID=$!
    sleep 3
    if kill -0 $BOT_PID 2>/dev/null; then
        ok "Rust echo bot started (PID $BOT_PID)"
    else
        err "Rust echo bot failed to start"
        return 1
    fi
}

start_erlang_bot() {
    log "Starting Erlang echo bot..."
    BOT_CONTAINER=""
    if command -v escript >/dev/null 2>&1; then
        bots/erlang/_build/default/bin/snatch_echo \
            --xmpp-host "${BB_XMPP_HOST:-localhost}" \
            --xmpp-port "${BB_XMPP_COMP_PORT:-45275}" \
            --xmpp-domain "${BB_XMPP_COMP_DOMAIN:-echo.localhost}" \
            --xmpp-password "${BB_XMPP_COMP_PASSWORD:-secret}" &
    else
        BOT_CONTAINER="bb-erlang-echo"
        docker rm -f "$BOT_CONTAINER" >/dev/null 2>&1 || true
        docker run --rm \
            --name "$BOT_CONTAINER" \
            --network blackbox-tests_default \
            -v "$SCRIPT_DIR/bots/erlang:/opt/snatch-echo" \
            -w /opt/snatch-echo \
            executor-builder:latest \
            sh -lc "erl -pa _build/default/lib/*/ebin -noshell -eval 'snatch_echo:main([\"--xmpp-host\",\"bb-ejabberd\",\"--xmpp-port\",\"5275\",\"--xmpp-domain\",\"${BB_XMPP_COMP_DOMAIN:-echo.localhost}\",\"--xmpp-password\",\"${BB_XMPP_COMP_PASSWORD:-secret}\"]).'" &
    fi
    BOT_PID=$!
    sleep 5
    if kill -0 $BOT_PID 2>/dev/null; then
        ok "Erlang echo bot started (PID $BOT_PID)"
    else
        err "Erlang echo bot failed to start"
        return 1
    fi
}

stop_bot() {
    if [ -n "${BOT_PID:-}" ] && kill -0 "$BOT_PID" 2>/dev/null; then
        log "Stopping echo bot (PID $BOT_PID)..."
        kill "$BOT_PID" 2>/dev/null || true
    fi
    if [ -n "${BOT_CONTAINER:-}" ]; then
        docker rm -f "$BOT_CONTAINER" >/dev/null 2>&1 || true
        BOT_CONTAINER=""
    fi
}

# --- Run Tests ---
run_tests() {
    local sut="$1"
    log "Running blackbox tests against: ${sut}"

    if [ "${#EXTRA_ARGS[@]}" -gt 0 ]; then
        BB_SUT="$sut" python3 -m pytest tests/ \
            -v --tb=short \
            -x \
            "${EXTRA_ARGS[@]}" \
            2>&1
    else
        BB_SUT="$sut" python3 -m pytest tests/ \
            -v --tb=short \
            -x \
            2>&1
    fi

    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        ok "All tests passed for ${sut}"
    else
        err "Some tests failed for ${sut} (exit code: $exit_code)"
    fi
    return $exit_code
}

# --- Compare Results ---
compare_results() {
    if [ -f "results_rust.json" ] && [ -f "results_erlang.json" ]; then
        log "Comparing results..."
        python3 -c "
import json
from tabulate import tabulate

with open('results_rust.json') as f:
    rust = {r['test'] + ':' + r['transport']: r for r in json.load(f)}
with open('results_erlang.json') as f:
    erlang = {r['test'] + ':' + r['transport']: r for r in json.load(f)}

def is_throughput(key: str) -> bool:
    test_name = key.split(':')[0]
    return 'throughput' in test_name

common_throughput_rows = []
rust_only_rows = []

for key in sorted(set(list(rust.keys()) + list(erlang.keys()))):
    r = rust.get(key)
    e = erlang.get(key)
    if not is_throughput(key):
        continue

    test_name, transport = key.split(':')

    if r and e:
        r_tp = r.get('throughput_msg_s', 0)
        e_tp = e.get('throughput_msg_s', 0)
        speedup = f'{r_tp / e_tp:.2f}x' if e_tp > 0 else 'N/A'
        common_throughput_rows.append([
            test_name,
            transport,
            f'{r_tp:.0f}',
            f'{e_tp:.0f}',
            speedup,
            f\"{r.get('p99_ms', 0):.2f}\",
            f\"{e.get('p99_ms', 0):.2f}\",
        ])
    elif r and not e:
        rust_only_rows.append([
            test_name,
            transport,
            f\"{r.get('throughput_msg_s', 0):.0f}\",
            f\"{r.get('p99_ms', 0):.2f}\",
        ])

print()
print('Common throughput tests (both SUTs):')
if common_throughput_rows:
    headers = ['Test', 'Transport', 'Rust msg/s', 'Erlang msg/s', 'Rust/Erlang', 'Rust P99', 'Erlang P99']
    print(tabulate(common_throughput_rows, headers=headers, tablefmt='github'))
else:
    print('  (none)')

if rust_only_rows:
    print()
    print('Rust-only throughput tests (not run by Erlang SUT):')
    headers = ['Test', 'Transport', 'Rust msg/s', 'Rust P99']
    print(tabulate(rust_only_rows, headers=headers, tablefmt='github'))
print()
"
    fi
}

# --- Main ---
main() {
    check_prereqs
    setup_python
    start_services

    trap 'stop_bot; stop_services' EXIT

    case "$SUT" in
        rust)
            build_rust_bot
            start_rust_bot
            run_tests "rust"
            cp results.json results_rust.json 2>/dev/null || true
            ;;
        erlang)
            build_erlang_bot
            start_erlang_bot
            run_tests "erlang"
            cp results.json results_erlang.json 2>/dev/null || true
            ;;
        both)
            # Run Rust
            build_rust_bot
            start_rust_bot
            run_tests "rust" || true
            cp results.json results_rust.json 2>/dev/null || true
            stop_bot

            sleep 2

            # Run Erlang
            if build_erlang_bot; then
                start_erlang_bot
                run_tests "erlang" || true
                cp results.json results_erlang.json 2>/dev/null || true
                stop_bot

                compare_results
            else
                warn "Skipping Erlang tests (build failed)"
            fi
            ;;
        *)
            echo "Usage: $0 {rust|erlang|both} [pytest args...]"
            exit 1
            ;;
    esac
}

main
