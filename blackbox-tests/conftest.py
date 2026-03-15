"""Shared pytest fixtures for blackbox performance tests."""
import json
import os
import subprocess
import time

import pytest
import config as cfg
from harness.metrics import PerfResult, print_results

# Collect all results for final summary
_all_results: list[PerfResult] = []


def pytest_collection_modifyitems(config, items):
    """Skip unsupported transport tests for selected SUT."""
    sut = os.environ.get("BB_SUT", cfg.SUT)
    if sut != "erlang":
        return

    skip_unsupported = pytest.mark.skip(
        reason="Erlang blackbox bot currently supports XMPP transport only"
    )
    for item in items:
        nodeid = item.nodeid
        if "test_kafka_perf.py" in nodeid or "test_rabbitmq_perf.py" in nodeid or "test_sqs_perf.py" in nodeid:
            item.add_marker(skip_unsupported)


def pytest_sessionfinish(session, exitstatus):
    """Print summary table at end of test run."""
    if _all_results:
        print_results(_all_results)
        # Also write JSON for CI comparison
        report = []
        for r in _all_results:
            report.append({
                "test": r.test_name,
                "sut": r.sut,
                "transport": r.transport,
                "messages_sent": r.messages_sent,
                "messages_received": r.messages_received,
                "throughput_msg_s": round(r.throughput, 1),
                "avg_ms": round(r.avg_ms, 3),
                "p50_ms": round(r.p50_ms, 3),
                "p95_ms": round(r.p95_ms, 3),
                "p99_ms": round(r.p99_ms, 3),
                "errors": r.errors,
            })
        report_path = os.path.join(os.path.dirname(__file__), "results.json")
        with open(report_path, "w") as f:
            json.dump(report, f, indent=2)
        print(f"\nResults written to {report_path}")


@pytest.fixture
def sut():
    """Return which SUT is being tested."""
    return cfg.SUT


@pytest.fixture
def perf(sut):
    """Create a PerfResult and register it for the final summary."""
    def _factory(test_name: str, transport: str) -> PerfResult:
        result = PerfResult(test_name=test_name, sut=sut, transport=transport)
        _all_results.append(result)
        return result
    return _factory


@pytest.fixture(scope="session")
def ensure_xmpp_users():
    """Register XMPP test users via ejabberdctl (idempotent)."""
    users = [
        (cfg.XMPP_USER, cfg.XMPP_PASS),
        ("bbuser2", "bbpass2"),
    ]
    for user, passwd in users:
        subprocess.run(
            ["docker", "exec", "bb-ejabberd", "ejabberdctl",
             "register", user, cfg.XMPP_DOMAIN, passwd],
            capture_output=True,
        )
    time.sleep(1)


@pytest.fixture(scope="session")
def ensure_sqs_queues():
    """Create SQS queues in LocalStack (idempotent)."""
    import boto3
    client = boto3.client(
        "sqs",
        endpoint_url=cfg.AWS_ENDPOINT,
        region_name=cfg.AWS_REGION,
        aws_access_key_id="test",
        aws_secret_access_key="test",
    )
    for q in [cfg.SQS_REQUEST_QUEUE, cfg.SQS_RESPONSE_QUEUE]:
        try:
            client.create_queue(QueueName=q)
        except Exception:
            pass


@pytest.fixture(scope="session")
def ensure_sns_topic():
    """Create SNS topic in LocalStack (idempotent)."""
    import boto3
    client = boto3.client(
        "sns",
        endpoint_url=cfg.AWS_ENDPOINT,
        region_name=cfg.AWS_REGION,
        aws_access_key_id="test",
        aws_secret_access_key="test",
    )
    try:
        client.create_topic(Name=cfg.SNS_TOPIC_NAME)
    except Exception:
        pass


@pytest.fixture(scope="session", autouse=True)
def ensure_kafka_topics():
    """Create Kafka request/response topics before tests run (idempotent)."""
    from confluent_kafka.admin import AdminClient, NewTopic

    admin = AdminClient({"bootstrap.servers": cfg.KAFKA_BOOTSTRAP})
    desired = [cfg.KAFKA_REQUEST_TOPIC, cfg.KAFKA_RESPONSE_TOPIC]
    deadline = time.time() + 45
    last_error = None

    while time.time() < deadline:
        try:
            metadata = admin.list_topics(timeout=10)
            existing = set(metadata.topics.keys())
            missing = [topic for topic in desired if topic not in existing]

            if not missing:
                return

            futures = admin.create_topics(
                [NewTopic(topic, num_partitions=1, replication_factor=1) for topic in missing],
                request_timeout=10,
            )
            for _topic, future in futures.items():
                try:
                    future.result(10)
                except Exception as exc:
                    # Topic may already exist by the time creation executes.
                    last_error = exc
        except Exception as exc:
            last_error = exc

        time.sleep(2)

    raise RuntimeError(
        f"Could not ensure Kafka topics {desired} on {cfg.KAFKA_BOOTSTRAP}. "
        f"Last error: {last_error}"
    )
