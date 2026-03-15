"""Kafka performance tests.

The echo bot consumes from the 'bb-request' topic and produces echoes
to the 'bb-response' topic with the same key and value.
"""
import os
import sys
import time
import uuid

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

import pytest
from confluent_kafka import Consumer, Producer

import config as cfg
from harness.metrics import PerfResult


def make_producer():
    return Producer({
        "bootstrap.servers": cfg.KAFKA_BOOTSTRAP,
        "linger.ms": 5,
        "batch.num.messages": 100,
    })


def make_consumer(group_suffix=""):
    unique_group = f"{cfg.KAFKA_GROUP_ID}-test-{group_suffix}-{uuid.uuid4().hex[:8]}"
    return Consumer({
        "bootstrap.servers": cfg.KAFKA_BOOTSTRAP,
        "group.id": unique_group,
        # Read from earliest for each fresh group to avoid assignment timing races.
        "auto.offset.reset": "earliest",
        "enable.auto.commit": False,
    })


def test_kafka_throughput(perf, sut):
    """Measure Kafka echo throughput."""
    result = perf("kafka_throughput", "kafka")
    n = cfg.KAFKA_PERF_MESSAGES

    producer = make_producer()
    consumer = make_consumer("throughput")
    consumer.subscribe([cfg.KAFKA_RESPONSE_TOPIC])

    # Drain old messages
    consumer.poll(timeout=2.0)

    send_times = {}

    result.start()
    # Produce all messages
    for i in range(n):
        msg_id = f"bb-{uuid.uuid4().hex[:12]}"
        send_times[msg_id] = time.monotonic()
        producer.produce(
            cfg.KAFKA_REQUEST_TOPIC,
            key=msg_id.encode(),
            value=msg_id.encode(),
        )
        result.messages_sent += 1

    producer.flush(timeout=10)

    # Consume responses
    deadline = time.monotonic() + cfg.KAFKA_TIMEOUT
    last_progress = time.monotonic()
    while result.messages_received < n and time.monotonic() < deadline:
        msg = consumer.poll(timeout=1.0)
        if msg is None or msg.error():
            if time.monotonic() - last_progress > cfg.STALL_TIMEOUT:
                break
            continue
        msg_id = msg.value().decode()
        recv_time = time.monotonic()
        if msg_id in send_times:
            latency = (recv_time - send_times[msg_id]) * 1000
            result.record_latency(latency)
            result.messages_received += 1
            last_progress = time.monotonic()

    result.stop()
    consumer.close()

    assert result.loss_pct < 10.0, f"Kafka loss {result.loss_pct:.1f}%"
    print(f"\n  [{sut}] Kafka: {result.throughput:.0f} msg/s avg={result.avg_ms:.2f}ms "
          f"p99={result.p99_ms:.2f}ms")


def test_kafka_latency(perf, sut):
    """Measure Kafka per-message latency."""
    result = perf("kafka_latency", "kafka")
    n = min(cfg.PERF_MESSAGES, 200)

    producer = make_producer()
    consumer = make_consumer("latency")
    consumer.subscribe([cfg.KAFKA_RESPONSE_TOPIC])
    consumer.poll(timeout=2.0)  # drain

    result.start()
    for i in range(n):
        msg_id = f"bb-lat-{i}"
        send_time = time.monotonic()

        producer.produce(
            cfg.KAFKA_REQUEST_TOPIC,
            key=msg_id.encode(),
            value=msg_id.encode(),
        )
        producer.flush(timeout=5)
        result.messages_sent += 1

        # Poll for response
        deadline = time.monotonic() + 10.0
        while time.monotonic() < deadline:
            msg = consumer.poll(timeout=0.1)
            if msg and not msg.error():
                recv_id = msg.value().decode()
                if recv_id == msg_id:
                    latency = (time.monotonic() - send_time) * 1000
                    result.record_latency(latency)
                    result.messages_received += 1
                    break

    result.stop()
    consumer.close()

    result.errors = n - result.messages_received
    assert result.loss_pct < 10.0
    print(f"\n  [{sut}] Kafka latency: avg={result.avg_ms:.2f}ms p99={result.p99_ms:.2f}ms")
