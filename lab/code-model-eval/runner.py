#!/usr/bin/env python3
"""Run a fixed evaluation set through a persistent OpenCode server."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import shutil
import signal
import socket
import statistics
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


FINAL_RE = re.compile(r"FINAL_ANSWER\s*:\s*(.+?)\s*$", re.IGNORECASE | re.MULTILINE)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def safe_label(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", value).strip("-.")
    if not cleaned:
        raise ValueError("label must contain a letter or number")
    return cleaned


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def wait_for_port(port: int, process: subprocess.Popen, timeout: float = 90.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"opencode serve exited with status {process.returncode}")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                return
        except OSError:
            time.sleep(0.25)
    raise TimeoutError("timed out waiting for opencode serve")


def format_choices(choices: dict[str, str]) -> str:
    return "\n".join(f"{letter}. {text}" for letter, text in sorted(choices.items()))


def make_prompt(item: dict) -> str:
    common = (
        "This is an isolated benchmark question. Do not use tools, files, shell commands, "
        "web search, other agents, or external knowledge retrieval. Solve only from the text below. "
        "Give a concise explanation, then finish with exactly one line in the form FINAL_ANSWER: <answer>.\n\n"
    )
    kind = item["prompt_kind"]
    if kind in {"mcq", "mcq_with_code"}:
        code = f"Code/context:\n```\n{item['code']}\n```\n\n" if "code" in item else ""
        return common + code + f"Question:\n{item['question']}\n\nOptions:\n{format_choices(item['choices'])}\n\nThe final answer must be one letter: A, B, C, or D."
    if kind == "crux_output":
        return common + f"Python function:\n```python\n{item['code']}\n```\n\nInput arguments:\n```python\n{item['input']}\n```\n\nPredict the exact Python repr of the return value."
    raise ValueError(f"unknown prompt kind: {kind}")


def collect_text(value) -> list[str]:
    found: list[str] = []
    if isinstance(value, dict):
        if value.get("type") == "text" and isinstance(value.get("text"), str):
            found.append(value["text"])
        for child in value.values():
            found.extend(collect_text(child))
    elif isinstance(value, list):
        for child in value:
            found.extend(collect_text(child))
    return found


def count_tool_nodes(value) -> int:
    count = 0
    if isinstance(value, dict):
        if "tool" in str(value.get("type", "")).lower():
            count += 1
        for child in value.values():
            count += count_tool_nodes(child)
    elif isinstance(value, list):
        for child in value:
            count += count_tool_nodes(child)
    return count


def parse_events(stdout: str) -> tuple[str, int, int]:
    texts: list[str] = []
    tool_events = 0
    parse_errors = 0
    for line in stdout.splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            parse_errors += 1
            continue
        tool_events += count_tool_nodes(event)
        texts.extend(collect_text(event))
    deduped = []
    for text in texts:
        if not deduped or deduped[-1] != text:
            deduped.append(text)
    return "\n".join(deduped).strip(), tool_events, parse_errors


def extract_answer(text: str, kind: str) -> str | None:
    matches = FINAL_RE.findall(text)
    if not matches:
        return None
    answer = matches[-1].strip().strip("`").strip()
    if kind in {"mcq", "mcq_with_code"}:
        match = re.match(r"([A-D])(?:\b|[.)])", answer, re.IGNORECASE)
        return match.group(1).upper() if match else None
    return answer


def normalized_exact(value: str | None) -> str | None:
    if value is None:
        return None
    return re.sub(r"\s+", "", value.strip())


def load_questions(path: Path) -> list[dict]:
    with path.open(encoding="utf-8") as handle:
        rows = [json.loads(line) for line in handle if line.strip()]
    if len(rows) != 120 or len({row["id"] for row in rows}) != len(rows):
        raise RuntimeError("question file must contain 120 unique requests")
    return rows


def write_summary(result_dir: Path, questions: list[dict]) -> None:
    records = {}
    responses = result_dir / "responses.jsonl"
    if responses.exists():
        with responses.open(encoding="utf-8") as handle:
            for line in handle:
                row = json.loads(line)
                records[row["id"]] = row
    with (result_dir / "answers.csv").open("w", encoding="utf-8", newline="") as handle:
        fields = ["id", "benchmark", "subset", "status", "prediction", "answer", "correct", "wall_seconds", "tool_events"]
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for question in questions:
            row = records.get(question["id"], {})
            writer.writerow({key: row.get(key, question.get(key, "")) for key in fields})

    groups: dict[str, list[dict]] = {"overall": list(records.values())}
    for row in records.values():
        groups.setdefault(f"benchmark:{row['benchmark']}", []).append(row)
        groups.setdefault(f"subset:{row['benchmark']}/{row['subset']}", []).append(row)
    summary = {}
    for name, rows in sorted(groups.items()):
        valid = [row for row in rows if row.get("status") == "ok"]
        latencies = [float(row["wall_seconds"]) for row in rows]
        summary[name] = {
            "attempted": len(rows),
            "valid": len(valid),
            "correct": sum(bool(row.get("correct")) for row in rows),
            "accuracy_all_attempts": round(sum(bool(row.get("correct")) for row in rows) / len(rows), 6) if rows else None,
            "accuracy_valid_only": round(sum(bool(row.get("correct")) for row in valid) / len(valid), 6) if valid else None,
            "median_wall_seconds": round(statistics.median(latencies), 3) if latencies else None,
            "statuses": {status: sum(row.get("status") == status for row in rows) for status in sorted({row.get("status") for row in rows})},
        }
    pairs: dict[str, dict[str, dict]] = {}
    question_by_id = {row["id"]: row for row in questions}
    for response in records.values():
        question = question_by_id.get(response["id"], {})
        if question.get("pair_id"):
            pairs.setdefault(question["pair_id"], {})[response["subset"]] = response
    complete_pairs = [pair for pair in pairs.values() if "oracle" in pair and "noisy_oracle" in pair]
    summary["swe_qa_pair_analysis"] = {
        "complete_pairs": len(complete_pairs),
        "oracle_correct": sum(bool(pair["oracle"].get("correct")) for pair in complete_pairs),
        "noisy_oracle_correct": sum(bool(pair["noisy_oracle"].get("correct")) for pair in complete_pairs),
        "oracle_correct_noisy_wrong": sum(bool(pair["oracle"].get("correct")) and not bool(pair["noisy_oracle"].get("correct")) for pair in complete_pairs),
        "oracle_wrong_noisy_correct": sum(not bool(pair["oracle"].get("correct")) and bool(pair["noisy_oracle"].get("correct")) for pair in complete_pairs),
    }
    (result_dir / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--questions", type=Path)
    parser.add_argument("--results-root", type=Path)
    parser.add_argument("--resume", type=Path, help="resume an existing result directory")
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--retries", type=int, default=1)
    parser.add_argument("--limit", type=int, help="development smoke-test only")
    parser.add_argument("--use-serve", action="store_true", help="experimental: use opencode serve + run --attach")
    parser.add_argument("--attach-url", help="with --use-serve, connect to an existing server")
    args = parser.parse_args()

    base = Path(__file__).resolve().parent
    questions_path = (args.questions or base / "data" / "questions.jsonl").resolve()
    results_root = (args.results_root or base / "results").resolve()
    label = safe_label(args.label)
    questions = load_questions(questions_path)
    if args.limit:
        questions = questions[: args.limit]
    if shutil.which("opencode") is None:
        raise RuntimeError("opencode is not in PATH")

    run_key = f"{datetime.now().strftime('%Y%m%d-%H%M%S')}-{label}"
    result_dir = args.resume.resolve() if args.resume else results_root / run_key
    raw_dir = result_dir / "raw"
    workspace = result_dir / "workspace"
    raw_dir.mkdir(parents=True, exist_ok=True)
    workspace.mkdir(exist_ok=True)
    version = subprocess.run(["opencode", "--version"], text=True, capture_output=True, check=True).stdout.strip()
    try:
        models = subprocess.run(["opencode", "models"], text=True, capture_output=True, timeout=60)
        model_listing = models.stdout + models.stderr
    except subprocess.TimeoutExpired:
        model_listing = "opencode models timed out after 60 seconds\n"
    (result_dir / "opencode-version.txt").write_text(version + "\n", encoding="utf-8")
    (result_dir / "model-list.txt").write_text(model_listing, encoding="utf-8")

    manifest = {
        "schema_version": 1,
        "label": label,
        "requested_model": args.model,
        "opencode_version": version,
        "questions_sha256": sha256(questions_path),
        "request_count": len(questions),
        "started_at": utc_now(),
        "warmup_count": 1,
        "cold_start_excluded": True,
        "each_question_new_session": True,
        "completed": False,
        "development_limit": args.limit,
        "transport": "serve_attach" if args.use_serve else "direct_run",
    }
    manifest_path = result_dir / "manifest.json"
    if args.resume:
        if not manifest_path.exists():
            raise RuntimeError("--resume directory has no manifest.json")
        previous = json.loads(manifest_path.read_text(encoding="utf-8"))
        if previous.get("questions_sha256") != manifest["questions_sha256"]:
            raise RuntimeError("cannot resume: question file hash changed")
        if previous.get("requested_model") != args.model or previous.get("label") != label:
            raise RuntimeError("cannot resume: label or model differs from manifest")
        manifest = previous
        manifest["resumed_at"] = utc_now()
        manifest["completed"] = False
        manifest["request_count"] = len(questions)
        manifest["transport"] = "serve_attach" if args.use_serve else "direct_run"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    server = None
    server_log = None
    attach_url = None
    if args.use_serve and args.attach_url:
        attach_url = args.attach_url
    elif args.use_serve:
        port = free_port()
        attach_url = f"http://127.0.0.1:{port}"
        server_log = (result_dir / "server.log").open("w", encoding="utf-8")
        server = subprocess.Popen(
            ["opencode", "serve", "--hostname", "127.0.0.1", "--port", str(port)],
            cwd=workspace,
            stdout=server_log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
            text=True,
        )
        wait_for_port(port, server)

    base_command = ["opencode", "run"]
    if attach_url:
        base_command += ["--attach", attach_url, "--dir", str(workspace)]
    base_command += ["--model", args.model, "--format", "json"]
    try:
        warmup_start = time.monotonic()
        warmup = subprocess.run(base_command + ["This is a non-scored warmup. Do not use tools. Reply with exactly: WARMUP_OK"], cwd=workspace, text=True, capture_output=True, timeout=args.timeout)
        (raw_dir / "warmup.stdout.jsonl").write_text(warmup.stdout, encoding="utf-8")
        (raw_dir / "warmup.stderr.txt").write_text(warmup.stderr, encoding="utf-8")
        manifest["warmup_seconds"] = round(time.monotonic() - warmup_start, 3)
        manifest["warmup_exit_code"] = warmup.returncode
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if warmup.returncode != 0:
            raise RuntimeError("warmup failed; inspect raw/warmup.stderr.txt")

        responses_path = result_dir / "responses.jsonl"
        completed: set[str] = set()
        if responses_path.exists():
            with responses_path.open(encoding="utf-8") as handle:
                completed = {json.loads(line)["id"] for line in handle if line.strip()}
        for index, item in enumerate(questions, 1):
            if item["id"] in completed:
                continue
            print(f"[{index}/{len(questions)}] {item['id']}", flush=True)
            prompt = make_prompt(item)
            last = None
            started = time.monotonic()
            for attempt in range(args.retries + 1):
                try:
                    last = subprocess.run(base_command + [prompt], cwd=workspace, text=True, capture_output=True, timeout=args.timeout)
                except subprocess.TimeoutExpired as exc:
                    last = exc
                if isinstance(last, subprocess.CompletedProcess) and last.returncode == 0:
                    break
            elapsed = round(time.monotonic() - started, 3)
            if isinstance(last, subprocess.TimeoutExpired):
                stdout = last.stdout or ""
                stderr = last.stderr or ""
                status = "timeout"
                exit_code = None
            else:
                stdout = last.stdout
                stderr = last.stderr
                status = "ok" if last.returncode == 0 else "error"
                exit_code = last.returncode
            (raw_dir / f"{item['id']}.stdout.jsonl").write_text(stdout, encoding="utf-8")
            (raw_dir / f"{item['id']}.stderr.txt").write_text(stderr, encoding="utf-8")
            text, tool_events, parse_errors = parse_events(stdout)
            prediction = extract_answer(text, item["prompt_kind"])
            if status == "ok" and prediction is None:
                status = "format_error"
            if tool_events:
                status = "tool_contaminated"
            correct = normalized_exact(prediction) == normalized_exact(item["answer"])
            record = {
                "id": item["id"],
                "benchmark": item["benchmark"],
                "subset": item["subset"],
                "category": item["category"],
                "status": status,
                "prediction": prediction,
                "answer": item["answer"],
                "correct": correct,
                "wall_seconds": elapsed,
                "exit_code": exit_code,
                "tool_events": tool_events,
                "json_parse_errors": parse_errors,
                "response_text": text,
            }
            with responses_path.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")
            write_summary(result_dir, questions)
    finally:
        if server is not None:
            try:
                os.killpg(server.pid, signal.SIGTERM)
                server.wait(timeout=10)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                pass
        if server_log is not None:
            server_log.close()

    manifest["finished_at"] = utc_now()
    manifest["completed"] = True
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_summary(result_dir, questions)
    print(f"results: {result_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
