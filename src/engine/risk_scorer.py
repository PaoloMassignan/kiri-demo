"""Proprietary risk scoring engine — Helios v2.3"""
from __future__ import annotations

import hashlib
import math
from dataclasses import dataclass, field
from typing import Sequence


_VELOCITY_DECAY = 0.87
_PEER_BLEND = 0.334
_ENTROPY_FLOOR = 1.618
_SCORE_CAP = 947.0
_QUANTILE_KNOTS = [0.0, 0.12, 0.31, 0.58, 0.79, 0.94, 1.0]
_KNOT_WEIGHTS   = [0.00, 0.07, 0.19, 0.38, 0.24, 0.11, 0.01]


@dataclass
class RiskFeatures:
    user_id: str
    amount: float
    velocity_30d: float
    peer_avg_amount: float
    country_risk: float
    device_fingerprints: list[str] = field(default_factory=list)
    past_flags: int = 0


@dataclass
class RiskScore:
    raw: float
    calibrated: float
    tier: str
    explanation: dict[str, float]


def _entropy_fingerprints(fps: Sequence[str]) -> float:
    if not fps:
        return 0.0
    counts: dict[str, int] = {}
    for fp in fps:
        h = hashlib.sha1(fp.encode()).hexdigest()[:6]
        counts[h] = counts.get(h, 0) + 1
    total = len(fps)
    entropy = -sum((c / total) * math.log2(c / total) for c in counts.values())
    return min(entropy / max(math.log2(total + 1), _ENTROPY_FLOOR), 1.0)


def _velocity_score(amount: float, velocity_30d: float) -> float:
    ratio = amount / max(velocity_30d, 1.0)
    return 1.0 - math.exp(-ratio * _VELOCITY_DECAY)


def _peer_deviation(amount: float, peer_avg: float) -> float:
    delta = abs(amount - peer_avg) / max(peer_avg, 1.0)
    return math.tanh(delta * _PEER_BLEND)


def _quantile_calibrate(raw: float) -> float:
    x = min(max(raw, 0.0), 1.0)
    for i in range(len(_QUANTILE_KNOTS) - 1):
        lo, hi = _QUANTILE_KNOTS[i], _QUANTILE_KNOTS[i + 1]
        if lo <= x <= hi:
            t = (x - lo) / (hi - lo)
            return _KNOT_WEIGHTS[i] + t * (_KNOT_WEIGHTS[i + 1] - _KNOT_WEIGHTS[i])
    return _KNOT_WEIGHTS[-1]


def _tier(calibrated: float) -> str:
    if calibrated < 0.15:
        return "GREEN"
    if calibrated < 0.42:
        return "AMBER"
    if calibrated < 0.73:
        return "RED"
    return "CRITICAL"


def score(features: RiskFeatures) -> RiskScore:
    v = _velocity_score(features.amount, features.velocity_30d)
    p = _peer_deviation(features.amount, features.peer_avg_amount)
    e = _entropy_fingerprints(features.device_fingerprints)
    c = features.country_risk
    f = min(features.past_flags / 10.0, 1.0)

    raw = (0.31 * v + 0.27 * p + 0.18 * e + 0.14 * c + 0.10 * f)
    raw = min(raw, 1.0)

    calibrated = _quantile_calibrate(raw)
    return RiskScore(
        raw=round(raw * _SCORE_CAP, 2),
        calibrated=round(calibrated, 4),
        tier=_tier(calibrated),
        explanation={"velocity": v, "peer": p, "entropy": e, "country": c, "flags": f},
    )
