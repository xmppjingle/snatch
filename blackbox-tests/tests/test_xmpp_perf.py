"""XMPP performance tests using raw TCP sockets.

These tests connect as an XMPP client to ejabberd, authenticate,
then send messages to the echo component (echo.localhost) and measure
round-trip latency and throughput.

Compatible with both Snatch (Erlang) and rnatch (Rust) as the SUT.
"""
import os
import re
import socket
import sys
import time
import uuid

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

import pytest

import config as cfg
from harness.metrics import PerfResult

import base64


def xmpp_connect_and_auth(host, port, user, password, domain, resource):
    """Connect to XMPP server, authenticate with SASL PLAIN, bind resource.
    Returns the connected socket."""
    sock = socket.create_connection((host, port), timeout=10)
    sock.settimeout(5)

    # Stream header
    sock.sendall(
        f"<?xml version='1.0'?>"
        f"<stream:stream to='{domain}' "
        f"xmlns='jabber:client' "
        f"xmlns:stream='http://etherx.jabber.org/streams' "
        f"version='1.0'>".encode()
    )
    _recv_until(sock, b"</stream:features>")  # stream header + features

    # SASL PLAIN auth
    auth_str = f"\x00{user}\x00{password}"
    auth_b64 = base64.b64encode(auth_str.encode()).decode()
    sock.sendall(
        f"<auth xmlns='urn:ietf:params:xml:ns:xmpp-sasl' "
        f"mechanism='PLAIN'>{auth_b64}</auth>".encode()
    )
    resp = _recv_until(sock, b"</success>", timeout=5)
    assert b"<success" in resp, f"Auth failed: {resp}"

    # Re-open stream after successful auth
    sock.sendall(
        f"<?xml version='1.0'?>"
        f"<stream:stream to='{domain}' "
        f"xmlns='jabber:client' "
        f"xmlns:stream='http://etherx.jabber.org/streams' "
        f"version='1.0'>".encode()
    )
    _recv_until(sock, b"</stream:features>")  # new stream features

    # Bind resource
    sock.sendall(
        f"<iq type='set' id='bind1'>"
        f"<bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'>"
        f"<resource>{resource}</resource>"
        f"</bind></iq>".encode()
    )
    resp = _recv_until(sock, b"</iq>", timeout=5)
    assert b"jid" in resp, f"Bind failed: {resp}"

    # Send presence
    sock.sendall(b"<presence/>")

    sock.settimeout(0.01)  # Non-blocking for polling
    return sock


def _recv(sock, size=8192):
    """Receive data with timeout."""
    try:
        return sock.recv(size)
    except socket.timeout:
        return b""


def _recv_until(sock, marker, timeout=5):
    """Receive data until marker is found or timeout."""
    data = b""
    deadline = time.monotonic() + timeout
    old_timeout = sock.gettimeout()
    sock.settimeout(0.5)
    while time.monotonic() < deadline:
        try:
            chunk = sock.recv(8192)
            if chunk:
                data += chunk
                if marker in data:
                    break
        except (socket.timeout, BlockingIOError):
            continue
    sock.settimeout(old_timeout)
    return data


def _recv_all(sock, timeout=5.0):
    """Receive all available data within timeout."""
    data = b""
    deadline = time.monotonic() + timeout
    sock.settimeout(0.05)
    while time.monotonic() < deadline:
        try:
            chunk = sock.recv(8192)
            if chunk:
                data += chunk
            else:
                break
        except (socket.timeout, BlockingIOError):
            if data:
                break
            continue
    return data


def _extract_bodies(data):
    """Extract message bodies from raw XML."""
    return re.findall(r"<body>(bb-[^<]+)</body>", data.decode("utf-8", errors="replace"))


def test_xmpp_message_latency(perf, sut, ensure_xmpp_users):
    """Measure per-message round-trip latency via XMPP."""
    result = perf("xmpp_message_latency", "xmpp")
    n = cfg.XMPP_PERF_MESSAGES

    sock = xmpp_connect_and_auth(
        cfg.XMPP_HOST, cfg.XMPP_C2S_PORT,
        cfg.XMPP_USER, cfg.XMPP_PASS,
        cfg.XMPP_DOMAIN, "bench"
    )

    try:
        # Warmup
        for i in range(cfg.PERF_WARMUP):
            sock.sendall(
                f"<message to='{cfg.XMPP_COMP_DOMAIN}' type='chat'>"
                f"<body>warmup-{i}</body></message>".encode()
            )
        time.sleep(1)
        _recv_all(sock, timeout=1)  # drain warmup responses

        # Benchmark: send one-by-one, measuring RTT
        send_times = {}
        result.start()

        for i in range(n):
            msg_id = f"bb-{uuid.uuid4().hex[:12]}"
            send_times[msg_id] = time.monotonic()
            sock.sendall(
                f"<message to='{cfg.XMPP_COMP_DOMAIN}' type='chat' "
                f"from='{cfg.XMPP_USER}@{cfg.XMPP_DOMAIN}/bench'>"
                f"<body>{msg_id}</body></message>".encode()
            )
            result.messages_sent += 1

        # Collect responses
        deadline = time.monotonic() + cfg.XMPP_TIMEOUT
        last_progress = time.monotonic()
        received = set()
        sock.settimeout(0.1)

        while len(received) < n and time.monotonic() < deadline:
            try:
                chunk = sock.recv(65536)
                if chunk:
                    recv_time = time.monotonic()
                    bodies = _extract_bodies(chunk)
                    for body in bodies:
                        if body in send_times and body not in received:
                            received.add(body)
                            latency = (recv_time - send_times[body]) * 1000
                            result.record_latency(latency)
                            result.messages_received += 1
                            last_progress = time.monotonic()
            except (socket.timeout, BlockingIOError):
                if time.monotonic() - last_progress > cfg.STALL_TIMEOUT:
                    break
                continue

        result.stop()
        result.errors = n - result.messages_received

    finally:
        sock.sendall(b"</stream:stream>")
        sock.close()

    assert result.messages_received > 0, "no messages received"
    print(f"\n  [{sut}] XMPP latency: avg={result.avg_ms:.2f}ms p50={result.p50_ms:.2f}ms "
          f"p95={result.p95_ms:.2f}ms p99={result.p99_ms:.2f}ms "
          f"throughput={result.throughput:.0f} msg/s")


def test_xmpp_throughput_burst(perf, sut, ensure_xmpp_users):
    """Measure maximum burst throughput via XMPP."""
    result = perf("xmpp_throughput_burst", "xmpp")
    n = cfg.XMPP_PERF_MESSAGES

    sock = xmpp_connect_and_auth(
        cfg.XMPP_HOST, cfg.XMPP_C2S_PORT,
        cfg.XMPP_USER, cfg.XMPP_PASS,
        cfg.XMPP_DOMAIN, "burst"
    )

    try:
        time.sleep(0.5)

        send_times = {}
        result.start()

        # Send all messages as fast as possible
        for i in range(n):
            msg_id = f"bb-burst-{i}"
            send_times[msg_id] = time.monotonic()
            sock.sendall(
                f"<message to='{cfg.XMPP_COMP_DOMAIN}' type='chat' "
                f"from='{cfg.XMPP_USER}@{cfg.XMPP_DOMAIN}/burst'>"
                f"<body>{msg_id}</body></message>".encode()
            )
            result.messages_sent += 1

        # Collect responses
        deadline = time.monotonic() + cfg.XMPP_TIMEOUT
        last_progress = time.monotonic()
        received = set()
        sock.settimeout(0.1)

        while len(received) < n and time.monotonic() < deadline:
            try:
                chunk = sock.recv(65536)
                if chunk:
                    recv_time = time.monotonic()
                    bodies = _extract_bodies(chunk)
                    for body in bodies:
                        if body in send_times and body not in received:
                            received.add(body)
                            latency = (recv_time - send_times[body]) * 1000
                            result.record_latency(latency)
                            result.messages_received += 1
                            last_progress = time.monotonic()
            except (socket.timeout, BlockingIOError):
                if time.monotonic() - last_progress > cfg.STALL_TIMEOUT:
                    break
                continue

        result.stop()
        result.errors = n - result.messages_received

    finally:
        sock.sendall(b"</stream:stream>")
        sock.close()

    assert result.messages_received > 0, "no messages received"
    print(f"\n  [{sut}] XMPP burst: {result.throughput:.0f} msg/s, "
          f"sent={result.messages_sent} recv={result.messages_received} "
          f"avg={result.avg_ms:.2f}ms p99={result.p99_ms:.2f}ms")


def test_xmpp_iq_roundtrip(perf, sut, ensure_xmpp_users):
    """Measure IQ request/response round-trip latency."""
    result = perf("xmpp_iq_roundtrip", "xmpp")
    n = min(cfg.XMPP_PERF_MESSAGES, 200)

    sock = xmpp_connect_and_auth(
        cfg.XMPP_HOST, cfg.XMPP_C2S_PORT,
        cfg.XMPP_USER, cfg.XMPP_PASS,
        cfg.XMPP_DOMAIN, "iq"
    )

    try:
        time.sleep(0.5)

        send_times = {}
        result.start()

        for i in range(n):
            iq_id = f"bb-iq-{i}"
            send_times[iq_id] = time.monotonic()
            sock.sendall(
                f"<iq type='get' id='{iq_id}' "
                f"to='{cfg.XMPP_COMP_DOMAIN}' "
                f"from='{cfg.XMPP_USER}@{cfg.XMPP_DOMAIN}/iq'>"
                f"<ping xmlns='urn:xmpp:ping'/></iq>".encode()
            )
            result.messages_sent += 1

        # Collect responses
        deadline = time.monotonic() + cfg.XMPP_TIMEOUT
        last_progress = time.monotonic()
        received = set()
        sock.settimeout(0.1)

        while len(received) < n and time.monotonic() < deadline:
            try:
                chunk = sock.recv(65536)
                if chunk:
                    recv_time = time.monotonic()
                    data = chunk.decode("utf-8", errors="replace")
                    # Extract IQ result ids
                    for iq_id in re.findall(r"<iq[^>]*id='(bb-iq-\d+)'", data):
                        if iq_id in send_times and iq_id not in received:
                            received.add(iq_id)
                            latency = (recv_time - send_times[iq_id]) * 1000
                            result.record_latency(latency)
                            result.messages_received += 1
                            last_progress = time.monotonic()
                    # Also check double-quoted ids
                    for iq_id in re.findall(r'<iq[^>]*id="(bb-iq-\d+)"', data):
                        if iq_id in send_times and iq_id not in received:
                            received.add(iq_id)
                            latency = (recv_time - send_times[iq_id]) * 1000
                            result.record_latency(latency)
                            result.messages_received += 1
                            last_progress = time.monotonic()
            except (socket.timeout, BlockingIOError):
                if time.monotonic() - last_progress > cfg.STALL_TIMEOUT:
                    break
                continue

        result.stop()
        result.errors = n - result.messages_received

    finally:
        sock.sendall(b"</stream:stream>")
        sock.close()

    assert result.messages_received > 0, "no messages received"
    print(f"\n  [{sut}] IQ roundtrip: avg={result.avg_ms:.2f}ms "
          f"p99={result.p99_ms:.2f}ms throughput={result.throughput:.0f} msg/s")
