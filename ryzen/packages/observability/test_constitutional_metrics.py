import pytest
from ryzen.packages.observability.constitutional_metrics import ConstitutionalMetrics

def test_metric_determinism():
    """Metric determinism: Repeated identical inputs produce identical outputs."""
    parsed = {"intent": "schedule_booking", "payload": {"loc": "Brussels"}, "metadata": {"c1": True}}
    expected = {"intent": "schedule_booking", "payload": {"loc": "Brussels"}}
    constraints = {"c1"}

    score1 = ConstitutionalMetrics.calculate_intent_alignment(parsed, expected, constraints)
    score2 = ConstitutionalMetrics.calculate_intent_alignment(parsed, expected, constraints)

    assert score1 == score2
    assert isinstance(score1, float)

def test_replay_integrity():
    """Replay integrity: Execution reconstruction is exact."""
    trace_a = [{"step": 1, "out": "ok"}, {"step": 2, "out": "done"}]
    trace_b = [{"step": 1, "out": "ok"}, {"step": 2, "out": "done"}]
    trace_c = [{"step": 1, "out": "ok"}, {"step": 2, "out": "fail"}]

    assert ConstitutionalMetrics.calculate_replay_integrity(trace_a, trace_b) == 1.0
    assert ConstitutionalMetrics.calculate_replay_integrity(trace_a, trace_c) == 0.5
    assert ConstitutionalMetrics.calculate_replay_integrity(trace_a, []) == 0.0

def test_threshold_stability():
    """Threshold stability: Metric gates evaluate reproducibly."""
    context = {"critical_id": 123, "dep_id": 456}
    required = {
        "critical": ["critical_id"],
        "dependency": ["dep_id"],
        "creator": ["creator_id"]
    }

    score = ConstitutionalMetrics.calculate_context_sufficiency(context, required)
    # weights: critical(0.5) * 1.0 + dependency(0.2) * 1.0 + creator(0.2) * 0.0 = 0.7
    assert score == 0.7

def test_entropy_detection_correctness():
    """Entropy detection correctness: Duplicate routing patterns are detected deterministically."""
    paths = [
        ["intent", "gov", "exec"],
        ["intent", "gov", "exec"], # Duplicate
        ["intent", "gov", "verify", "exec"]
    ]

    entropy = ConstitutionalMetrics.calculate_architectural_entropy(paths)
    # unique = 2, total = 3. ratio = 2/3 = 0.67. entropy = 1 - 0.67 = 0.33
    assert entropy == 0.33

    # All same
    paths_all_same = [["a"], ["a"], ["a"]]
    assert ConstitutionalMetrics.calculate_architectural_entropy(paths_all_same) == 0.67 # unique=1, total=3, ratio=0.33, entropy=0.67

    # All unique
    paths_all_unique = [["a"], ["b"], ["c"]]
    assert ConstitutionalMetrics.calculate_architectural_entropy(paths_all_unique) == 0.0
