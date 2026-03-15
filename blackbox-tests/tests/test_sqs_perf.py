"""AWS SQS performance tests (via LocalStack).

The echo bot polls the 'bb-request' queue and sends echoed messages
to the 'bb-response' queue.
"""
import os
import sys
import time
import uuid

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

import boto3
import pytest

import config as cfg
from harness.metrics import PerfResult


def get_sqs_client():
    return boto3.client(
        "sqs",
        endpoint_url=cfg.AWS_ENDPOINT,
        region_name=cfg.AWS_REGION,
        aws_access_key_id="test",
        aws_secret_access_key="test",
    )


def get_queue_url(client, name):
    resp = client.create_queue(QueueName=name)
    return resp["QueueUrl"]


def purge_queue(client, url):
    try:
        client.purge_queue(QueueUrl=url)
        time.sleep(1)
    except Exception:
        pass


def test_sqs_throughput(perf, sut, ensure_sqs_queues):
    """Measure SQS echo throughput."""
    result = perf("sqs_throughput", "sqs")
    n = min(cfg.SQS_PERF_MESSAGES, 100)  # SQS is inherently slower

    client = get_sqs_client()
    req_url = get_queue_url(client, cfg.SQS_REQUEST_QUEUE)
    resp_url = get_queue_url(client, cfg.SQS_RESPONSE_QUEUE)

    purge_queue(client, resp_url)

    send_times = {}

    result.start()
    # Send messages
    for i in range(n):
        msg_id = f"bb-{uuid.uuid4().hex[:12]}"
        send_times[msg_id] = time.monotonic()
        client.send_message(QueueUrl=req_url, MessageBody=msg_id)
        result.messages_sent += 1

    # Poll for responses
    deadline = time.monotonic() + cfg.SQS_TIMEOUT
    while result.messages_received < n and time.monotonic() < deadline:
        resp = client.receive_message(
            QueueUrl=resp_url,
            MaxNumberOfMessages=10,
            WaitTimeSeconds=5,
        )
        for msg in resp.get("Messages", []):
            body = msg["Body"]
            recv_time = time.monotonic()
            if body in send_times:
                latency = (recv_time - send_times[body]) * 1000
                result.record_latency(latency)
                result.messages_received += 1
            client.delete_message(
                QueueUrl=resp_url,
                ReceiptHandle=msg["ReceiptHandle"],
            )

    result.stop()

    result.errors = n - result.messages_received
    assert result.loss_pct < 20.0, f"SQS loss {result.loss_pct:.1f}%"
    print(f"\n  [{sut}] SQS: {result.throughput:.0f} msg/s avg={result.avg_ms:.2f}ms")


def test_sqs_latency(perf, sut, ensure_sqs_queues):
    """Measure SQS per-message latency."""
    result = perf("sqs_latency", "sqs")
    n = min(cfg.SQS_PERF_MESSAGES, 20)  # SQS has ~100ms+ latency per msg

    client = get_sqs_client()
    req_url = get_queue_url(client, cfg.SQS_REQUEST_QUEUE)
    resp_url = get_queue_url(client, cfg.SQS_RESPONSE_QUEUE)

    purge_queue(client, resp_url)

    result.start()
    for i in range(n):
        msg_id = f"bb-slat-{i}"
        send_time = time.monotonic()
        client.send_message(QueueUrl=req_url, MessageBody=msg_id)
        result.messages_sent += 1

        # Poll for response
        deadline = time.monotonic() + 30.0
        while time.monotonic() < deadline:
            resp = client.receive_message(
                QueueUrl=resp_url,
                MaxNumberOfMessages=1,
                WaitTimeSeconds=5,
            )
            msgs = resp.get("Messages", [])
            if msgs:
                body = msgs[0]["Body"]
                client.delete_message(
                    QueueUrl=resp_url,
                    ReceiptHandle=msgs[0]["ReceiptHandle"],
                )
                if body == msg_id:
                    latency = (time.monotonic() - send_time) * 1000
                    result.record_latency(latency)
                    result.messages_received += 1
                    break

    result.stop()

    result.errors = n - result.messages_received
    assert result.loss_pct < 30.0  # SQS can be flaky
    print(f"\n  [{sut}] SQS latency: avg={result.avg_ms:.2f}ms")
