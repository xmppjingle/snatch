"""Blackbox test configuration.

All values can be overridden via environment variables prefixed with BB_.
Example: BB_XMPP_HOST=192.168.1.10 overrides XMPP_HOST.
"""
import os

def _env(key, default):
    return os.environ.get(f"BB_{key}", default)

# --- XMPP ---
XMPP_HOST = _env("XMPP_HOST", "localhost")
XMPP_C2S_PORT = int(_env("XMPP_C2S_PORT", "45222"))
XMPP_COMP_PORT = int(_env("XMPP_COMP_PORT", "45275"))
XMPP_DOMAIN = _env("XMPP_DOMAIN", "localhost")
XMPP_COMP_DOMAIN = _env("XMPP_COMP_DOMAIN", "echo.localhost")
XMPP_COMP_PASSWORD = _env("XMPP_COMP_PASSWORD", "secret")

# Test user credentials (pre-registered)
XMPP_USER = _env("XMPP_USER", "bbuser")
XMPP_PASS = _env("XMPP_PASS", "bbpass")

# --- RabbitMQ ---
RABBITMQ_HOST = _env("RABBITMQ_HOST", "localhost")
RABBITMQ_PORT = int(_env("RABBITMQ_PORT", "45672"))
RABBITMQ_USER = _env("RABBITMQ_USER", "guest")
RABBITMQ_PASS = _env("RABBITMQ_PASS", "guest")
RABBITMQ_VHOST = _env("RABBITMQ_VHOST", "/")

# --- AWS / LocalStack ---
AWS_ENDPOINT = _env("AWS_ENDPOINT", "http://localhost:44566")
AWS_REGION = _env("AWS_REGION", "us-east-1")
SQS_REQUEST_QUEUE = _env("SQS_REQUEST_QUEUE", "bb-request")
SQS_RESPONSE_QUEUE = _env("SQS_RESPONSE_QUEUE", "bb-response")
SNS_TOPIC_NAME = _env("SNS_TOPIC_NAME", "bb-topic")

# --- Kafka ---
KAFKA_BOOTSTRAP = _env("KAFKA_BOOTSTRAP", "127.0.0.1:49092")
KAFKA_REQUEST_TOPIC = _env("KAFKA_REQUEST_TOPIC", "bb-request")
KAFKA_RESPONSE_TOPIC = _env("KAFKA_RESPONSE_TOPIC", "bb-response")
KAFKA_GROUP_ID = _env("KAFKA_GROUP_ID", "bb-test")

# --- Performance ---
PERF_WARMUP = int(_env("PERF_WARMUP", "10"))        # warmup messages
PERF_MESSAGES = int(_env("PERF_MESSAGES", "10000"))  # generic default messages per test
PERF_CONCURRENT = int(_env("PERF_CONCURRENT", "10")) # concurrent senders
PERF_TIMEOUT = int(_env("PERF_TIMEOUT", "60"))       # generic default timeout (seconds)

# Transport-specific tuning (defaults aim for sub-1-minute tests).
KAFKA_PERF_MESSAGES = int(_env("KAFKA_PERF_MESSAGES", "5000"))
RABBITMQ_PERF_MESSAGES = int(_env("RABBITMQ_PERF_MESSAGES", "10000"))
XMPP_PERF_MESSAGES = int(_env("XMPP_PERF_MESSAGES", "1000"))
SQS_PERF_MESSAGES = int(_env("SQS_PERF_MESSAGES", "100"))

KAFKA_TIMEOUT = int(_env("KAFKA_TIMEOUT", "50"))
RABBITMQ_TIMEOUT = int(_env("RABBITMQ_TIMEOUT", "50"))
XMPP_TIMEOUT = int(_env("XMPP_TIMEOUT", "20"))
SQS_TIMEOUT = int(_env("SQS_TIMEOUT", "50"))

# Abort waiting loops early if no new responses arrive for this long.
STALL_TIMEOUT = int(_env("STALL_TIMEOUT", "6"))

# --- SUT (System Under Test) ---
SUT = _env("SUT", "rust")  # "rust" or "erlang"
