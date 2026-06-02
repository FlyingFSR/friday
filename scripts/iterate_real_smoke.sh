#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORT_DIR="$APP_DIR/.build/real-smoke"
mkdir -p "$REPORT_DIR"

python3 - "$APP_DIR" "$REPORT_DIR" <<'PY'
import json
import math
import os
import statistics
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


def percentile(values, pct):
  if not values:
    return None
  sorted_values = sorted(values)
  index = max(0, math.ceil((pct / 100.0) * len(sorted_values)) - 1)
  return sorted_values[index]


def parse_bool(value, default=False):
  if value is None:
    return default
  normalized = str(value).strip().lower()
  if normalized in {"1", "true", "yes", "on"}:
    return True
  if normalized in {"0", "false", "no", "off"}:
    return False
  return default


def parse_csv(raw):
  return [token.strip() for token in str(raw).split(",") if token.strip()]


def safe_float(value, default=0.0):
  try:
    return float(value)
  except (TypeError, ValueError):
    return default


def run_command(cmd, cwd, env, log_path):
  started = time.monotonic()
  process = subprocess.run(
    cmd,
    cwd=cwd,
    env=env,
    capture_output=True,
    text=True,
  )
  elapsed_ms = int((time.monotonic() - started) * 1000)
  log_path.parent.mkdir(parents=True, exist_ok=True)
  with open(log_path, "w", encoding="utf-8") as handle:
    handle.write(process.stdout)
    if process.stderr:
      handle.write("\n[stderr]\n")
      handle.write(process.stderr)
  return process.returncode, elapsed_ms


def load_metrics(metrics_path):
  metrics = []
  if not metrics_path.exists():
    return metrics
  with open(metrics_path, "r", encoding="utf-8") as handle:
    for line in handle:
      line = line.strip()
      if not line:
        continue
      try:
        metrics.append(json.loads(line))
      except json.JSONDecodeError:
        continue
  return metrics


def aggregate_distribution(metrics):
  output = {}
  for metric in metrics:
    distribution = metric.get("diagnosticsReasonDistribution", {})
    if not isinstance(distribution, dict):
      continue
    for key, value in distribution.items():
      try:
        output[key] = output.get(key, 0) + int(value)
      except (TypeError, ValueError):
        continue
  return output


def aggregate_profile_distribution(metrics):
  distribution = {}
  for metric in metrics:
    profile_id = str(metric.get("acousticProfileID", "")).strip()
    if not profile_id:
      continue
    distribution[profile_id] = distribution.get(profile_id, 0) + 1
  return distribution


def as_score(pass_rate, term_hit_rate, drop_case_count, p95_ms, median_ms):
  p95_component = -(p95_ms if p95_ms is not None else 10**9)
  median_component = -(median_ms if median_ms is not None else 10**9)
  return (pass_rate, term_hit_rate, -drop_case_count, p95_component, median_component)


def summarize_metrics(metrics, required_models):
  case_count = len(metrics)
  passed_cases = sum(1 for metric in metrics if metric.get("pass") is True)
  pass_rate = (passed_cases / case_count) if case_count else 0.0

  model_distribution = {}
  case_model_distribution = {}
  for metric in metrics:
    model = str(metric.get("model", "")).strip().lower()
    case_id = str(metric.get("caseID", "")).strip().lower()
    if model:
      model_distribution[model] = model_distribution.get(model, 0) + 1
    if case_id and model:
      case_model_distribution.setdefault(case_id, {})
      case_model_distribution[case_id][model] = case_model_distribution[case_id].get(model, 0) + 1

  models_covered = all(model_distribution.get(model, 0) > 0 for model in required_models)

  term_hits = sum(int(metric.get("terminologyHits", 0)) for metric in metrics)
  term_total = sum(int(metric.get("terminologyTotal", 0)) for metric in metrics)
  term_hit_rate = (term_hits / term_total) if term_total else 0.0
  term_fuzzy_rates = []
  for metric in metrics:
    if "termFuzzyHitRate" in metric:
      term_fuzzy_rates.append(safe_float(metric.get("termFuzzyHitRate"), default=0.0))
    elif int(metric.get("terminologyTotal", 0)) > 0:
      term_fuzzy_rates.append(int(metric.get("terminologyHits", 0)) / int(metric.get("terminologyTotal", 0)))
  avg_term_fuzzy_hit_rate = (sum(term_fuzzy_rates) / len(term_fuzzy_rates)) if term_fuzzy_rates else 0.0

  latencies = [int(metric.get("durationMs", 0)) for metric in metrics if int(metric.get("durationMs", 0)) > 0]
  median_latency_ms = int(statistics.median(latencies)) if latencies else None
  p95_latency_ms = int(percentile(latencies, 95)) if latencies else None

  drop_case_count = sum(1 for metric in metrics if metric.get("dropSuspected") is True)
  switch_scores = [safe_float(metric.get("languageSwitchIntegrityScore"), default=1.0) for metric in metrics]
  segment_scores = [safe_float(metric.get("segmentIntegrityScore"), default=1.0) for metric in metrics]
  avg_switch_integrity_score = (sum(switch_scores) / len(switch_scores)) if switch_scores else 1.0
  avg_segment_integrity_score = (sum(segment_scores) / len(segment_scores)) if segment_scores else 1.0
  switch_integrity_fail_count = sum(1 for score in switch_scores if score < 0.90)
  segment_integrity_fail_count = sum(1 for score in segment_scores if score < 0.85)
  required_phrase_ok = all(
    bool(metric.get(
      "requiredPhraseOK",
      int(metric.get("requiredPhraseHits", 0)) >= int(metric.get("requiredPhraseTotal", 0))
    ))
    for metric in metrics
  ) if metrics else False

  diagnostics_distribution = aggregate_distribution(metrics)
  acoustic_profile_distribution = aggregate_profile_distribution(metrics)

  failure_class_distribution = {
    "boundary_drop": 0,
    "language_lock": 0,
    "term_drift": 0,
    "latency_spike": 0,
  }
  for metric in metrics:
    metric_diagnostics = metric.get("diagnosticsReasonDistribution", {})
    if isinstance(metric_diagnostics, dict):
      failure_class_distribution["boundary_drop"] += int(metric_diagnostics.get("boundary_drop", 0) or 0)
      failure_class_distribution["language_lock"] += int(metric_diagnostics.get("language_lock", 0) or 0)
      failure_class_distribution["term_drift"] += int(metric_diagnostics.get("term_drift", 0) or 0)

  return {
    "case_count": case_count,
    "passed_cases": passed_cases,
    "pass_rate": pass_rate,
    "model_distribution": model_distribution,
    "case_model_distribution": case_model_distribution,
    "models_covered": models_covered,
    "terminology_hits": term_hits,
    "terminology_total": term_total,
    "terminology_hit_rate": term_hit_rate,
    "avg_term_fuzzy_hit_rate": avg_term_fuzzy_hit_rate,
    "median_latency_ms": median_latency_ms,
    "p95_latency_ms": p95_latency_ms,
    "drop_case_count": drop_case_count,
    "avg_segment_integrity_score": avg_segment_integrity_score,
    "avg_switch_integrity_score": avg_switch_integrity_score,
    "switch_integrity_fail_count": switch_integrity_fail_count,
    "segment_integrity_fail_count": segment_integrity_fail_count,
    "required_phrase_ok": required_phrase_ok,
    "diagnostics_reason_distribution": diagnostics_distribution,
    "acoustic_profile_distribution": acoustic_profile_distribution,
    "failure_class_distribution": failure_class_distribution,
  }


app_dir = Path(sys.argv[1])
report_dir = Path(sys.argv[2])
report_dir.mkdir(parents=True, exist_ok=True)

supported_case_order = [
  "mixed_zh_en_zh",
  "mixed_en_zh_en",
  "mixed_zh_then_en_tail",
  "mixed_en_then_zh_tail",
  "mixed_random_distribution",
]

supported_acoustic_profiles = [
  "clean_ref",
  "office_snr15_reverb_light",
  "cafe_snr10_reverb_medium",
  "phone_bandlimit_clip_light",
  "keyboard_nearfield_snr12",
]

boundary_shift_rotation = [-300, 0, 300]

smoke_mode = os.environ.get("FRIDAY_SMOKE_MODE", "progressive").strip().lower()
if smoke_mode != "progressive":
  raise SystemExit(f"Unsupported FRIDAY_SMOKE_MODE={smoke_mode}")

max_full_cycles = int(os.environ.get("MAX_FULL_CYCLES", os.environ.get("MAX_ROUNDS", "10")))
consecutive_target = int(os.environ.get("CONSECUTIVE_TARGET", "2"))
plateau_cycles = int(os.environ.get("PLATEAU_CYCLES", os.environ.get("PLATEAU_ROUNDS", "4")))
cooldown_seconds = int(float(os.environ.get("COOLDOWN_SECONDS", "90")))
fast_fail_per_micro_round = parse_bool(os.environ.get("FAST_FAIL_PER_MICRO_ROUND", "1"), default=True)
required_models = [m.lower() for m in parse_csv(os.environ.get("FRIDAY_REAL_SMOKE_MODELS", "medium,large-v3"))]
if not required_models:
  required_models = ["medium", "large-v3"]
acoustic_mode = os.environ.get("FRIDAY_REAL_SMOKE_ACOUSTIC_MODE", "clean").strip().lower()
if acoustic_mode not in {"clean", "realistic"}:
  acoustic_mode = "clean"
forced_acoustic_profile = os.environ.get("FRIDAY_REAL_SMOKE_ACOUSTIC_PROFILE", "").strip().lower()
gate_mode = os.environ.get("FRIDAY_REAL_SMOKE_GATE_MODE", "soft").strip().lower()
if gate_mode not in {"soft", "hard"}:
  gate_mode = "soft"
soft_gate_cycles = int(os.environ.get("SOFT_GATE_CYCLES", "2"))
rollback_mode = parse_bool(os.environ.get("FRIDAY_REAL_SMOKE_ROLLBACK", "0"), default=False)

if rollback_mode:
  acoustic_mode = "clean"
  forced_acoustic_profile = "clean_ref"
  gate_mode = "hard"
  soft_gate_cycles = 0

hard_term_fuzzy_threshold = 0.75
hard_switch_integrity_threshold = 0.90
hard_segment_integrity_threshold = 0.85
hard_median_budget_multiplier = 1.35
hard_p95_budget_multiplier = 1.55
legacy_median_budget_multiplier = 1.30
legacy_p95_budget_multiplier = 1.45

custom_case_order = parse_csv(os.environ.get("MICRO_CASE_ORDER", ",".join(supported_case_order)))
micro_case_order = [case_id for case_id in custom_case_order if case_id in supported_case_order]
if not micro_case_order:
  micro_case_order = supported_case_order

report_path = report_dir / "report.json"
checkpoint_path = report_dir / "checkpoint.json"

micro_rounds = []
cycles = []
best_cycle_score = None
best_cycle = None
consecutive_cycle_passes = 0
no_improvement_cycles = 0
stop_reason = "max_cycles"
baseline_median_ms = None
baseline_p95_ms = None


def write_checkpoint(payload):
  with open(checkpoint_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)


total_micro_round_index = 0

for cycle_index in range(1, max_full_cycles + 1):
  cycle_id = f"cycle-{cycle_index:02d}"
  cycle_dir = report_dir / cycle_id
  cycle_dir.mkdir(parents=True, exist_ok=True)
  effective_gate_mode = "hard" if (gate_mode == "hard" or cycle_index > soft_gate_cycles) else "soft"

  if forced_acoustic_profile:
    cycle_acoustic_profile = (
      forced_acoustic_profile
      if forced_acoustic_profile in supported_acoustic_profiles
      else "clean_ref"
    )
  elif acoustic_mode == "clean":
    cycle_acoustic_profile = "clean_ref"
  else:
    cycle_acoustic_profile = supported_acoustic_profiles[(cycle_index - 1) % len(supported_acoustic_profiles)]

  cycle_metrics = []
  cycle_hard_failure = False
  cycle_hard_failure_reason = ""

  for case_position, case_id in enumerate(micro_case_order, start=1):
    total_micro_round_index += 1
    round_id = f"round-{total_micro_round_index:03d}"
    micro_dir = cycle_dir / f"{round_id}-{case_id}"
    micro_dir.mkdir(parents=True, exist_ok=True)

    max_attempts = 1 if fast_fail_per_micro_round else 2
    micro_attempt_records = []
    selected_metrics = []
    micro_pass = False
    boundary_shift_ms = boundary_shift_rotation[(total_micro_round_index - 1) % len(boundary_shift_rotation)]
    if acoustic_mode == "clean":
      boundary_shift_ms = 0

    for attempt in range(1, max_attempts + 1):
      metrics_path = micro_dir / f"metrics-attempt-{attempt}.ndjson"
      if metrics_path.exists():
        metrics_path.unlink()

      env_real = os.environ.copy()
      env_real["FRIDAY_REAL_TRANSCRIBE_SMOKE"] = "1"
      env_real["FRIDAY_REAL_SMOKE_METRICS_PATH"] = str(metrics_path)
      env_real["FRIDAY_REAL_SMOKE_MODELS"] = ",".join(required_models)
      env_real["FRIDAY_REAL_SMOKE_CASE"] = case_id
      env_real["FRIDAY_REAL_SMOKE_CYCLE_ID"] = cycle_id
      env_real["FRIDAY_REAL_SMOKE_ROUND_ID"] = round_id
      env_real["FULL_CYCLE_INDEX"] = str(cycle_index)
      env_real["MICRO_ROUND_INDEX"] = str(total_micro_round_index)
      env_real["FRIDAY_REAL_SMOKE_ACOUSTIC_MODE"] = acoustic_mode
      env_real["FRIDAY_REAL_SMOKE_ACOUSTIC_PROFILE"] = cycle_acoustic_profile
      env_real["FRIDAY_REAL_SMOKE_BOUNDARY_SHIFT_MS"] = str(boundary_shift_ms)
      env_real["FRIDAY_REAL_SMOKE_EFFECTIVE_GATE_MODE"] = effective_gate_mode

      real_exit, real_elapsed_ms = run_command(
        ["swift", "test", "--filter", "RealTranscriptionRegressionTests"],
        cwd=str(app_dir),
        env=env_real,
        log_path=micro_dir / f"real-attempt-{attempt}.log",
      )

      metrics = load_metrics(metrics_path)
      selected_metrics = metrics
      summary = summarize_metrics(metrics, required_models)
      micro_pass_common = (
        real_exit == 0 and
        summary["case_count"] > 0 and
        summary["models_covered"]
      )
      micro_quality_hard = (
        summary["drop_case_count"] == 0 and
        summary["required_phrase_ok"] and
        summary["avg_term_fuzzy_hit_rate"] >= hard_term_fuzzy_threshold and
        summary["switch_integrity_fail_count"] == 0 and
        summary["segment_integrity_fail_count"] == 0
      )
      if rollback_mode:
        micro_quality_hard = (
          summary["drop_case_count"] == 0 and
          summary["required_phrase_ok"] and
          summary["terminology_hit_rate"] >= (2.0 / 3.0)
        )
      micro_pass = micro_pass_common and (
        True if effective_gate_mode == "soft" else micro_quality_hard
      )

      micro_attempt_records.append({
        "attempt": attempt,
        "real_test_exit_code": real_exit,
        "real_test_elapsed_ms": real_elapsed_ms,
        "metrics_path": str(metrics_path),
        "acoustic_mode": acoustic_mode,
        "acoustic_profile_id": cycle_acoustic_profile,
        "boundary_shift_ms": boundary_shift_ms,
        "gate_mode": effective_gate_mode,
        "summary": summary,
        "pass": micro_pass,
      })

      if micro_pass:
        break

      if real_exit != 0 and attempt >= max_attempts:
        infrastructure_failure = (
          summary["case_count"] == 0 or
          not summary["models_covered"]
        )
        if infrastructure_failure:
          cycle_hard_failure = True
          cycle_hard_failure_reason = (
            f"real_test_failed cycle={cycle_id} round={round_id} case={case_id} exit={real_exit}"
          )

    cycle_metrics.extend(selected_metrics)

    micro_round_record = {
      "micro_round_index": total_micro_round_index,
      "cycle_index": cycle_index,
      "cycle_id": cycle_id,
      "round_id": round_id,
      "case_id": case_id,
      "attempts": micro_attempt_records,
      "attempt_count": len(micro_attempt_records),
      "pass": micro_pass,
      "selected_metrics_count": len(selected_metrics),
      "acoustic_mode": acoustic_mode,
      "acoustic_profile_id": cycle_acoustic_profile,
      "boundary_shift_ms": boundary_shift_ms,
      "gate_mode": effective_gate_mode,
      "cooldown_seconds": cooldown_seconds,
      "hard_failure": cycle_hard_failure,
      "hard_failure_reason": cycle_hard_failure_reason,
    }

    micro_rounds.append(micro_round_record)

    write_checkpoint({
      "mode": smoke_mode,
      "phase": "micro_round_completed",
      "last_cycle": cycle_index,
      "last_round": total_micro_round_index,
      "stop_reason": None,
      "micro_rounds": micro_rounds,
      "cycles": cycles,
      "consecutive_cycle_passes": consecutive_cycle_passes,
      "no_improvement_cycles": no_improvement_cycles,
    })

    if cycle_hard_failure:
      break

    if cooldown_seconds > 0:
      time.sleep(cooldown_seconds)

  if cycle_hard_failure:
    stop_reason = "hard_failure"
    cycles.append({
      "cycle": cycle_index,
      "cycle_id": cycle_id,
      "unit_test_exit_code": None,
      "unit_test_elapsed_ms": None,
      "case_coverage": False,
      "model_coverage": False,
      "correctness": False,
      "required_phrase_ok": False,
      "terminology_hit_rate": 0.0,
      "median_latency_ms": None,
      "p95_latency_ms": None,
      "budget_ok": False,
      "cycle_pass": False,
      "hard_failure": True,
      "hard_failure_reason": cycle_hard_failure_reason,
    })
    break

  env_unit = os.environ.copy()
  env_unit.pop("FRIDAY_REAL_TRANSCRIBE_SMOKE", None)
  env_unit.pop("FRIDAY_REAL_SMOKE_METRICS_PATH", None)
  env_unit.pop("FRIDAY_REAL_SMOKE_MODELS", None)
  env_unit.pop("FRIDAY_REAL_SMOKE_CASE", None)
  env_unit.pop("FRIDAY_REAL_SMOKE_CYCLE_ID", None)
  env_unit.pop("FRIDAY_REAL_SMOKE_ROUND_ID", None)
  env_unit.pop("FRIDAY_REAL_SMOKE_ACOUSTIC_MODE", None)
  env_unit.pop("FRIDAY_REAL_SMOKE_ACOUSTIC_PROFILE", None)
  env_unit.pop("FRIDAY_REAL_SMOKE_BOUNDARY_SHIFT_MS", None)
  env_unit.pop("FRIDAY_REAL_SMOKE_EFFECTIVE_GATE_MODE", None)

  unit_exit, unit_elapsed_ms = run_command(
    ["swift", "test"],
    cwd=str(app_dir),
    env=env_unit,
    log_path=cycle_dir / "unit.log",
  )

  cycle_summary = summarize_metrics(cycle_metrics, required_models)
  cycle_case_ids = {
    str(metric.get("caseID", "")).strip().lower()
    for metric in cycle_metrics
    if str(metric.get("caseID", "")).strip()
  }
  case_coverage = all(case_id in cycle_case_ids for case_id in micro_case_order)

  case_model_coverage = cycle_summary["case_model_distribution"]
  model_coverage = True
  for case_id in micro_case_order:
    models_for_case = case_model_coverage.get(case_id, {})
    for model in required_models:
      if models_for_case.get(model, 0) <= 0:
        model_coverage = False
        break
    if not model_coverage:
      break

  if baseline_median_ms is None and cycle_summary["median_latency_ms"] is not None:
    baseline_median_ms = cycle_summary["median_latency_ms"]
  if baseline_p95_ms is None and cycle_summary["p95_latency_ms"] is not None:
    baseline_p95_ms = cycle_summary["p95_latency_ms"]

  median_budget_multiplier = (
    legacy_median_budget_multiplier if rollback_mode else hard_median_budget_multiplier
  )
  p95_budget_multiplier = (
    legacy_p95_budget_multiplier if rollback_mode else hard_p95_budget_multiplier
  )
  budget_ok = True
  if (
    baseline_median_ms is not None and
    baseline_p95_ms is not None and
    cycle_summary["median_latency_ms"] is not None and
    cycle_summary["p95_latency_ms"] is not None
  ):
    budget_ok = (
      cycle_summary["median_latency_ms"] <= baseline_median_ms * median_budget_multiplier and
      cycle_summary["p95_latency_ms"] <= baseline_p95_ms * p95_budget_multiplier
    )
  if not budget_ok:
    cycle_summary["failure_class_distribution"]["latency_spike"] = (
      cycle_summary["failure_class_distribution"].get("latency_spike", 0) + 1
    )

  cycle_pass_base = (
    unit_exit == 0 and
    cycle_summary["case_count"] > 0 and
    case_coverage and
    model_coverage
  )
  cycle_pass_hard = (
    cycle_summary["drop_case_count"] == 0 and
    cycle_summary["required_phrase_ok"] and
    cycle_summary["avg_term_fuzzy_hit_rate"] >= hard_term_fuzzy_threshold and
    cycle_summary["avg_switch_integrity_score"] >= hard_switch_integrity_threshold and
    cycle_summary["avg_segment_integrity_score"] >= hard_segment_integrity_threshold and
    budget_ok
  )
  if rollback_mode:
    cycle_pass_hard = (
      cycle_summary["drop_case_count"] == 0 and
      cycle_summary["required_phrase_ok"] and
      cycle_summary["terminology_hit_rate"] >= (2.0 / 3.0) and
      budget_ok
    )
  cycle_pass = cycle_pass_base and (
    True if effective_gate_mode == "soft" else cycle_pass_hard
  )

  if effective_gate_mode == "hard":
    if cycle_pass:
      consecutive_cycle_passes += 1
    else:
      consecutive_cycle_passes = 0

  score = as_score(
    cycle_summary["pass_rate"],
    cycle_summary["avg_term_fuzzy_hit_rate"] if not rollback_mode else cycle_summary["terminology_hit_rate"],
    cycle_summary["drop_case_count"],
    cycle_summary["p95_latency_ms"],
    cycle_summary["median_latency_ms"],
  )
  improved = best_cycle_score is None or score > best_cycle_score
  if effective_gate_mode == "hard":
    if improved:
      best_cycle_score = score
      best_cycle = cycle_index
      no_improvement_cycles = 0
    else:
      no_improvement_cycles += 1

  cycle_record = {
    "cycle": cycle_index,
    "cycle_id": cycle_id,
    "gate_mode": effective_gate_mode,
    "acoustic_mode": acoustic_mode,
    "acoustic_profile_id": cycle_acoustic_profile,
    "unit_test_exit_code": unit_exit,
    "unit_test_elapsed_ms": unit_elapsed_ms,
    "case_count": cycle_summary["case_count"],
    "passed_cases": cycle_summary["passed_cases"],
    "pass_rate": cycle_summary["pass_rate"],
    "case_coverage": case_coverage,
    "model_coverage": model_coverage,
    "required_models": required_models,
    "required_cases": micro_case_order,
    "model_distribution": cycle_summary["model_distribution"],
    "terminology_hits": cycle_summary["terminology_hits"],
    "terminology_total": cycle_summary["terminology_total"],
    "terminology_hit_rate": cycle_summary["terminology_hit_rate"],
    "avg_term_fuzzy_hit_rate": cycle_summary["avg_term_fuzzy_hit_rate"],
    "drop_case_count": cycle_summary["drop_case_count"],
    "avg_segment_integrity_score": cycle_summary["avg_segment_integrity_score"],
    "avg_switch_integrity_score": cycle_summary["avg_switch_integrity_score"],
    "switch_integrity_fail_count": cycle_summary["switch_integrity_fail_count"],
    "segment_integrity_fail_count": cycle_summary["segment_integrity_fail_count"],
    "required_phrase_ok": cycle_summary["required_phrase_ok"],
    "median_latency_ms": cycle_summary["median_latency_ms"],
    "p95_latency_ms": cycle_summary["p95_latency_ms"],
    "budget_ok": budget_ok,
    "acoustic_profile_distribution": cycle_summary["acoustic_profile_distribution"],
    "diagnostics_reason_distribution": cycle_summary["diagnostics_reason_distribution"],
    "failure_class_distribution": cycle_summary["failure_class_distribution"],
    "cycle_pass": cycle_pass,
    "counted_for_consecutive": effective_gate_mode == "hard",
    "hard_failure": False,
    "hard_failure_reason": "",
    "improved": improved,
    "no_improvement_cycles": no_improvement_cycles,
    "consecutive_cycle_passes": consecutive_cycle_passes,
  }

  cycles.append(cycle_record)

  write_checkpoint({
    "mode": smoke_mode,
    "phase": "cycle_completed",
    "last_cycle": cycle_index,
    "last_round": total_micro_round_index,
    "stop_reason": None,
    "micro_rounds": micro_rounds,
    "cycles": cycles,
    "consecutive_cycle_passes": consecutive_cycle_passes,
    "no_improvement_cycles": no_improvement_cycles,
  })

  if consecutive_cycle_passes >= consecutive_target:
    stop_reason = "target_reached"
    break

  if no_improvement_cycles >= plateau_cycles:
    stop_reason = "plateau"
    break

if stop_reason not in {"target_reached", "plateau", "hard_failure"}:
  stop_reason = "max_cycles"

final_acoustic_profile_distribution = {}
switch_integrity_fail_count = 0
segment_integrity_fail_count = 0
for cycle in cycles:
  profile_distribution = cycle.get("acoustic_profile_distribution", {})
  if isinstance(profile_distribution, dict):
    for key, value in profile_distribution.items():
      try:
        final_acoustic_profile_distribution[key] = (
          final_acoustic_profile_distribution.get(key, 0) + int(value)
        )
      except (TypeError, ValueError):
        continue
  switch_integrity_fail_count += int(cycle.get("switch_integrity_fail_count", 0) or 0)
  segment_integrity_fail_count += int(cycle.get("segment_integrity_fail_count", 0) or 0)

report = {
  "generated_at": datetime.now(timezone.utc).isoformat(),
  "config": {
    "mode": smoke_mode,
    "max_full_cycles": max_full_cycles,
    "consecutive_target": consecutive_target,
    "plateau_cycles": plateau_cycles,
    "cooldown_seconds": cooldown_seconds,
    "fast_fail_per_micro_round": fast_fail_per_micro_round,
    "required_models": required_models,
    "micro_case_order": micro_case_order,
    "acoustic_mode": acoustic_mode,
    "forced_acoustic_profile": forced_acoustic_profile or None,
    "supported_acoustic_profiles": supported_acoustic_profiles,
    "boundary_shift_rotation": boundary_shift_rotation,
    "gate_mode": gate_mode,
    "soft_gate_cycles": soft_gate_cycles,
    "rollback_mode": rollback_mode,
    "budget_multipliers": {
      "median_hard": hard_median_budget_multiplier,
      "p95_hard": hard_p95_budget_multiplier,
      "median_legacy": legacy_median_budget_multiplier,
      "p95_legacy": legacy_p95_budget_multiplier,
    },
    "terminology_hit_threshold": 2.0 / 3.0,
    "term_fuzzy_hit_threshold_hard": hard_term_fuzzy_threshold,
    "switch_integrity_threshold_hard": hard_switch_integrity_threshold,
    "segment_integrity_threshold_hard": hard_segment_integrity_threshold,
  },
  "baseline": {
    "median_latency_ms": baseline_median_ms,
    "p95_latency_ms": baseline_p95_ms,
  },
  "stop_reason": stop_reason,
  "acoustic_profile_distribution": final_acoustic_profile_distribution,
  "switch_integrity_fail_count": switch_integrity_fail_count,
  "segment_integrity_fail_count": segment_integrity_fail_count,
  "micro_rounds": micro_rounds,
  "cycles": cycles,
  "final": {
    "success": consecutive_cycle_passes >= consecutive_target,
    "executed_full_cycles": len(cycles),
    "executed_micro_rounds": len(micro_rounds),
    "best_cycle": best_cycle,
    "consecutive_cycle_passes": consecutive_cycle_passes,
  },
}

with open(report_path, "w", encoding="utf-8") as handle:
  json.dump(report, handle, ensure_ascii=False, indent=2)

write_checkpoint({
  "mode": smoke_mode,
  "phase": "finished",
  "last_cycle": len(cycles),
  "last_round": len(micro_rounds),
  "stop_reason": stop_reason,
  "micro_rounds": micro_rounds,
  "cycles": cycles,
  "consecutive_cycle_passes": consecutive_cycle_passes,
  "no_improvement_cycles": no_improvement_cycles,
})

print(
  "Real smoke progressive run completed: "
  f"cycles={len(cycles)} micro_rounds={len(micro_rounds)} stop_reason={stop_reason}"
)
if best_cycle is not None:
  print(f"Best cycle: {best_cycle}")
print(f"Report written to: {report_path}")
print(f"Checkpoint written to: {checkpoint_path}")
PY
