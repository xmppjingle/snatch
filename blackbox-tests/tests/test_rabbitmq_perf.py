"""RabbitMQ/AMQP performance tests.

The echo bot subscribes to the 'bb_request' queue on the 'bb_direct' exchange.
When it receives a message, it publishes the same body to 'bb_response' exchange
with the original routing key.

The test publishes messages to bb_direct and consumes from bb_response,
measuring round-trip latency.
"""
import os
import sys
import threading
import time
import uuid

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

import pika
import pytest

import config as cfg
from harness.metrics import PerfResult

EXCHANGE_REQUEST = "bb_direct"
EXCHANGE_RESPONSE = "bb_response"
ROUTING_KEY = "bench"


def setup_exchanges_and_queues(channel):
    """Declare exchanges and queues for the test."""
    channel.exchange_declare(exchange=EXCHANGE_REQUEST, exchange_type="direct", durable=False)
    channel.exchange_declare(exchange=EXCHANGE_RESPONSE, exchange_type="direct", durable=False)
    # Response queue for the test harness
    channel.queue_declare(queue="bb_response_q", exclusive=False, auto_delete=False)
    channel.queue_bind(queue="bb_response_q", exchange=EXCHANGE_RESPONSE, routing_key=ROUTING_KEY)
    # Request queue for the bot
    channel.queue_declare(queue="bb_request_q", exclusive=False, auto_delete=False)
    channel.queue_bind(queue="bb_request_q", exchange=EXCHANGE_REQUEST, routing_key=ROUTING_KEY)


def test_rabbitmq_throughput(perf, sut):
    """Measure RabbitMQ message echo throughput."""
    result = perf("rabbitmq_throughput", "rabbitmq")
    n = cfg.RABBITMQ_PERF_MESSAGES

    creds = pika.PlainCredentials(cfg.RABBITMQ_USER, cfg.RABBITMQ_PASS)
    params = pika.ConnectionParameters(
        host=cfg.RABBITMQ_HOST,
        port=cfg.RABBITMQ_PORT,
        virtual_host=cfg.RABBITMQ_VHOST,
        credentials=creds,
    )

    # Publisher connection
    pub_conn = pika.BlockingConnection(params)
    pub_ch = pub_conn.channel()
    setup_exchanges_and_queues(pub_ch)

    # Consumer connection (in separate thread)
    recv_times = {}
    send_times = {}
    consumer_ready = threading.Event()
    stop_consuming = threading.Event()

    def consumer_thread():
        cons_conn = pika.BlockingConnection(params)
        cons_ch = cons_conn.channel()
        setup_exchanges_and_queues(cons_ch)

        def on_message(ch, method, properties, body):
            msg_id = body.decode()
            if msg_id.startswith("bb-"):
                recv_times[msg_id] = time.monotonic()
            ch.basic_ack(delivery_tag=method.delivery_tag)
            if len(recv_times) >= n or stop_consuming.is_set():
                ch.stop_consuming()

        cons_ch.basic_consume(queue="bb_response_q", on_message_callback=on_message)
        consumer_ready.set()

        # Consume until all received or timeout
        deadline = time.monotonic() + cfg.RABBITMQ_TIMEOUT
        try:
            while time.monotonic() < deadline and not stop_consuming.is_set():
                cons_conn.process_data_events(time_limit=1)
                if len(recv_times) >= n:
                    break
        except Exception:
            pass
        try:
            cons_conn.close()
        except Exception:
            pass

    t = threading.Thread(target=consumer_thread, daemon=True)
    t.start()
    consumer_ready.wait(timeout=5)

    # Publish messages
    result.start()
    for i in range(n):
        msg_id = f"bb-{uuid.uuid4().hex[:12]}"
        send_times[msg_id] = time.monotonic()
        pub_ch.basic_publish(
            exchange=EXCHANGE_REQUEST,
            routing_key=ROUTING_KEY,
            body=msg_id.encode(),
        )
        result.messages_sent += 1

    # Wait for consumer
    t.join(timeout=cfg.RABBITMQ_TIMEOUT)
    stop_consuming.set()
    result.stop()

    pub_conn.close()

    # Calculate
    for msg_id, recv_time in recv_times.items():
        if msg_id in send_times:
            latency = (recv_time - send_times[msg_id]) * 1000
            result.record_latency(latency)
            result.messages_received += 1

    result.errors = n - result.messages_received

    assert result.loss_pct < 10.0, f"RabbitMQ loss {result.loss_pct:.1f}%"
    print(f"\n  [{sut}] RabbitMQ: {result.throughput:.0f} msg/s avg={result.avg_ms:.2f}ms "
          f"p99={result.p99_ms:.2f}ms")


def test_rabbitmq_latency_sequential(perf, sut):
    """Measure RabbitMQ per-message latency with sequential sends."""
    result = perf("rabbitmq_latency_seq", "rabbitmq")
    n = min(cfg.RABBITMQ_PERF_MESSAGES, 200)  # Sequential is slower

    creds = pika.PlainCredentials(cfg.RABBITMQ_USER, cfg.RABBITMQ_PASS)
    params = pika.ConnectionParameters(
        host=cfg.RABBITMQ_HOST,
        port=cfg.RABBITMQ_PORT,
        virtual_host=cfg.RABBITMQ_VHOST,
        credentials=creds,
    )

    conn = pika.BlockingConnection(params)
    ch = conn.channel()
    setup_exchanges_and_queues(ch)

    result.start()
    for i in range(n):
        msg_id = f"bb-seq-{i}"
        send_time = time.monotonic()

        ch.basic_publish(
            exchange=EXCHANGE_REQUEST,
            routing_key=ROUTING_KEY,
            body=msg_id.encode(),
        )
        result.messages_sent += 1

        # Poll for response
        deadline = time.monotonic() + 5.0
        got_response = False
        while time.monotonic() < deadline:
            method, props, body = ch.basic_get(queue="bb_response_q", auto_ack=True)
            if method and body:
                recv_id = body.decode()
                if recv_id == msg_id:
                    latency = (time.monotonic() - send_time) * 1000
                    result.record_latency(latency)
                    result.messages_received += 1
                    got_response = True
                    break
            time.sleep(0.001)

        if not got_response:
            result.errors += 1

    result.stop()
    conn.close()

    assert result.loss_pct < 10.0
    print(f"\n  [{sut}] RabbitMQ seq: avg={result.avg_ms:.2f}ms p99={result.p99_ms:.2f}ms")
