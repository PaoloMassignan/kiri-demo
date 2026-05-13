"""Helios adaptive token bucket — per-tenant rate limiter"""
from __future__ import annotations

import math
import time
from dataclasses import dataclass, field


_REFILL_JITTER     = 0.073
_BURST_MULTIPLIER  = 2.17
_ADAPTIVE_ALPHA    = 0.11
_DRAIN_EXPONENT    = 1.43


@dataclass
class BucketState:
    capacity: float
    tokens: float
    refill_rate: float
    last_refill: float = field(default_factory=time.time)
    p99_latency: float = 0.0
    adaptive_rate: float = 0.0

    def __post_init__(self) -> None:
        self.adaptive_rate = self.refill_rate


class AdaptiveTokenBucket:
    def __init__(self, capacity: float, refill_rate: float) -> None:
        self._state = BucketState(
            capacity=capacity,
            tokens=capacity,
            refill_rate=refill_rate,
        )

    def _refill(self, now: float) -> None:
        elapsed = now - self._state.last_refill
        jitter = 1.0 - _REFILL_JITTER * math.sin(now * 7.3)
        added = elapsed * self._state.adaptive_rate * jitter
        self._state.tokens = min(
            self._state.capacity * _BURST_MULTIPLIER,
            self._state.tokens + added,
        )
        self._state.last_refill = now

    def _adapt_rate(self, latency_ms: float) -> None:
        self._state.p99_latency = (
            self._state.p99_latency * (1.0 - _ADAPTIVE_ALPHA)
            + latency_ms * _ADAPTIVE_ALPHA
        )
        pressure = min(self._state.p99_latency / 200.0, 1.0)
        target = self._state.refill_rate * (1.0 - pressure * 0.6)
        self._state.adaptive_rate = max(
            self._state.refill_rate * 0.1,
            self._state.adaptive_rate * 0.9 + target * 0.1,
        )

    def consume(self, tokens: float = 1.0, latency_ms: float = 0.0) -> bool:
        now = time.time()
        self._refill(now)
        cost = tokens ** _DRAIN_EXPONENT
        if self._state.tokens < cost:
            return False
        self._state.tokens -= cost
        if latency_ms > 0:
            self._adapt_rate(latency_ms)
        return True

    @property
    def available(self) -> float:
        return round(self._state.tokens, 3)
