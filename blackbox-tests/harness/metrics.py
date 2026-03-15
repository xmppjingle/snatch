"""Performance metrics collection and reporting."""
import statistics
import time
from dataclasses import dataclass, field
from tabulate import tabulate


@dataclass
class PerfResult:
    """Collected performance metrics for a single test run."""
    test_name: str
    sut: str  # "rust" or "erlang"
    transport: str  # "xmpp", "xmpp_comp", "rabbitmq", "sqs", "kafka"
    messages_sent: int = 0
    messages_received: int = 0
    latencies_ms: list = field(default_factory=list)
    start_time: float = 0.0
    end_time: float = 0.0
    errors: int = 0

    def start(self):
        self.start_time = time.monotonic()

    def stop(self):
        self.end_time = time.monotonic()

    def record_latency(self, latency_ms: float):
        self.latencies_ms.append(latency_ms)

    @property
    def duration_s(self) -> float:
        return self.end_time - self.start_time

    @property
    def throughput(self) -> float:
        """Messages per second."""
        if self.duration_s <= 0:
            return 0.0
        return self.messages_received / self.duration_s

    @property
    def loss_pct(self) -> float:
        if self.messages_sent == 0:
            return 0.0
        return (1 - self.messages_received / self.messages_sent) * 100

    @property
    def p50_ms(self) -> float:
        return self._percentile(50)

    @property
    def p95_ms(self) -> float:
        return self._percentile(95)

    @property
    def p99_ms(self) -> float:
        return self._percentile(99)

    @property
    def avg_ms(self) -> float:
        if not self.latencies_ms:
            return 0.0
        return statistics.mean(self.latencies_ms)

    @property
    def min_ms(self) -> float:
        if not self.latencies_ms:
            return 0.0
        return min(self.latencies_ms)

    @property
    def max_ms(self) -> float:
        if not self.latencies_ms:
            return 0.0
        return max(self.latencies_ms)

    @property
    def stddev_ms(self) -> float:
        if len(self.latencies_ms) < 2:
            return 0.0
        return statistics.stdev(self.latencies_ms)

    def _percentile(self, pct: int) -> float:
        if not self.latencies_ms:
            return 0.0
        sorted_lat = sorted(self.latencies_ms)
        idx = int(len(sorted_lat) * pct / 100)
        idx = min(idx, len(sorted_lat) - 1)
        return sorted_lat[idx]

    def summary_row(self) -> list:
        return [
            self.test_name,
            self.sut,
            self.transport,
            self.messages_sent,
            self.messages_received,
            f"{self.loss_pct:.1f}%",
            f"{self.duration_s:.2f}s",
            f"{self.throughput:.0f}",
            f"{self.avg_ms:.2f}",
            f"{self.p50_ms:.2f}",
            f"{self.p95_ms:.2f}",
            f"{self.p99_ms:.2f}",
            f"{self.min_ms:.2f}",
            f"{self.max_ms:.2f}",
            self.errors,
        ]

    @staticmethod
    def summary_headers() -> list:
        return [
            "Test", "SUT", "Transport", "Sent", "Recv", "Loss",
            "Duration", "Msg/s", "Avg(ms)", "P50(ms)", "P95(ms)",
            "P99(ms)", "Min(ms)", "Max(ms)", "Errors",
        ]


def print_results(results: list[PerfResult]):
    """Pretty-print a table of performance results."""
    rows = [r.summary_row() for r in results]
    print("\n" + tabulate(rows, headers=PerfResult.summary_headers(), tablefmt="github"))
    print()


def assert_no_regression(baseline: PerfResult, current: PerfResult, tolerance_pct: float = 20.0):
    """Assert that current performance is within tolerance of baseline."""
    if baseline.throughput > 0:
        degradation = (baseline.throughput - current.throughput) / baseline.throughput * 100
        assert degradation < tolerance_pct, (
            f"Throughput regression: {current.throughput:.0f} msg/s vs "
            f"baseline {baseline.throughput:.0f} msg/s ({degradation:.1f}% degradation)"
        )
    if baseline.p99_ms > 0:
        increase = (current.p99_ms - baseline.p99_ms) / baseline.p99_ms * 100
        assert increase < tolerance_pct * 2, (
            f"P99 latency regression: {current.p99_ms:.2f}ms vs "
            f"baseline {baseline.p99_ms:.2f}ms ({increase:.1f}% increase)"
        )
