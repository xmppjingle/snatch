# Blackbox Performance Tests

Language-agnostic performance test suite that runs identically against both
**Snatch** (Erlang) and **rnatch** (Rust). Tests verify 100% behavioral
compatibility and measure performance across all transports.

## Architecture

```
                    ┌──────────────────┐
                    │  Python Harness  │  (pytest + slixmpp/pika/boto3/confluent-kafka)
                    │  sends messages  │
                    │  measures perf   │
                    └────────┬─────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
         ┌────▼────┐   ┌─────▼─────┐  ┌────▼────┐
         │ ejabberd │   │ RabbitMQ  │  │  Kafka  │  ... (Docker services)
         └────┬─────┘   └─────┬─────┘  └────┬────┘
              │              │              │
              └──────────────┼──────────────┘
                             │
                    ┌────────▼─────────┐
                    │    Echo Bot      │  (Rust OR Erlang — same behavior)
                    │  swaps from/to   │
                    │  echoes messages  │
                    └──────────────────┘
```

The **echo bot** is the System Under Test (SUT). It connects as an XMPP
component and echoes every stanza with `from`/`to` swapped. For RabbitMQ,
Kafka, and SQS it reads from a request queue and writes to a response queue.

The Python harness sends messages through each transport and measures:
- **Round-trip latency** (per-message, percentiles)
- **Throughput** (messages/second under burst)
- **Message loss** (% of sent messages not received back)

## Quick Start

```bash
# Run against rnatch (Rust)
./run.sh rust

# Run against snatch (Erlang)
./run.sh erlang

# Run both and compare side-by-side
./run.sh both

# Run only XMPP tests
./run.sh rust -k xmpp

# Run with more messages
BB_PERF_MESSAGES=5000 ./run.sh rust
```

If `rebar3` is not installed locally, `./run.sh erlang` and `./run.sh both`
automatically use a Docker builder (`bots/erlang/Dockerfile`) to compile
`snatch_echo`.

## Manual Setup

```bash
# 1. Start services
docker compose up -d
sleep 15
docker exec bb-ejabberd ejabberdctl register bbuser localhost bbpass

# 2. Build and start the bot
cd bots/rust && cargo build --release
./target/release/rnatch-echo-bot --all

# 3. Run tests (in another terminal)
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
BB_SUT=rust python3 -m pytest tests/ -v

# 4. Cleanup
docker compose down -v
```

## Test Matrix

| Test | Transport | What it measures |
|------|-----------|------------------|
| `test_xmpp_message_latency` | XMPP | Per-message round-trip latency |
| `test_xmpp_throughput_burst` | XMPP | Max burst throughput (msg/s) |
| `test_xmpp_iq_roundtrip` | XMPP | IQ request/response latency |
| `test_rabbitmq_throughput` | RabbitMQ | Echo throughput via AMQP |
| `test_rabbitmq_latency_seq` | RabbitMQ | Sequential per-message latency |
| `test_kafka_throughput` | Kafka | Echo throughput via Kafka |
| `test_kafka_latency` | Kafka | Per-message latency via Kafka |
| `test_sqs_throughput` | SQS | Echo throughput via SQS |
| `test_sqs_latency` | SQS | Per-message latency via SQS |

## Configuration

All parameters are configurable via `BB_` prefixed environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `BB_SUT` | `rust` | System under test: `rust` or `erlang` |
| `BB_PERF_MESSAGES` | `1000` | Messages per test |
| `BB_PERF_WARMUP` | `10` | Warmup messages (excluded from metrics) |
| `BB_PERF_TIMEOUT` | `60` | Test timeout in seconds |
| `BB_XMPP_HOST` | `localhost` | XMPP server host |
| `BB_XMPP_C2S_PORT` | `5222` | XMPP client port |
| `BB_XMPP_COMP_PORT` | `5275` | XMPP component port |
| `BB_RABBITMQ_HOST` | `localhost` | RabbitMQ host |
| `BB_KAFKA_BOOTSTRAP` | `localhost:9092` | Kafka bootstrap servers |
| `BB_AWS_ENDPOINT` | `http://localhost:4566` | LocalStack endpoint |

## Output

### Console Output

```
| Test                    | SUT  | Transport | Sent | Recv | Loss | Duration | Msg/s | Avg(ms) | P50(ms) | P95(ms) | P99(ms) |
|-------------------------|------|-----------|------|------|------|----------|-------|---------|---------|---------|---------|
| xmpp_message_latency    | rust | xmpp      | 1000 | 1000 | 0.0% | 2.34s    | 427   | 1.23    | 1.10    | 2.45    | 4.12    |
| xmpp_throughput_burst   | rust | xmpp      | 1000 | 1000 | 0.0% | 0.89s    | 1124  | 0.88    | 0.76    | 1.89    | 3.21    |
| rabbitmq_throughput     | rust | rabbitmq  | 1000 | 1000 | 0.0% | 1.56s    | 641   | 1.55    | 1.32    | 3.10    | 5.67    |
```

### Comparison Mode (`./run.sh both`)

```
| Test                 | Transport | Rust msg/s | Erlang msg/s | Speedup | Rust P99 | Erlang P99 |
|----------------------|-----------|------------|--------------|---------|----------|------------|
| xmpp_message_latency | xmpp      | 427        | 312          | 1.37x   | 4.12     | 6.78       |
| rabbitmq_throughput  | rabbitmq  | 641        | 489          | 1.31x   | 5.67     | 8.23       |
```

### JSON Report

Results are also written to `results.json` for CI integration:

```json
[
  {
    "test": "xmpp_message_latency",
    "sut": "rust",
    "transport": "xmpp",
    "messages_sent": 1000,
    "messages_received": 1000,
    "throughput_msg_s": 427.3,
    "avg_ms": 1.234,
    "p50_ms": 1.102,
    "p95_ms": 2.451,
    "p99_ms": 4.123,
    "errors": 0
  }
]
```

## Adding to Snatch

To run the same tests against the Erlang Snatch library:

```bash
# Copy the blackbox-tests directory to the snatch project
cp -r blackbox-tests /path/to/snatch/

# Or symlink it
ln -s /path/to/rnatch/blackbox-tests /path/to/snatch/blackbox-tests

# Run
cd /path/to/snatch/blackbox-tests
./run.sh erlang
```
