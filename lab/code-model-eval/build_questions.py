#!/usr/bin/env python3
"""Build the fixed first-round question set from pinned upstream data."""

from __future__ import annotations

import argparse
import hashlib
import json
import random
from pathlib import Path


SEED = 20260802


def stable_id(prefix: str, *parts: object) -> str:
    payload = json.dumps(parts, ensure_ascii=False, sort_keys=True).encode()
    return f"{prefix}-{hashlib.sha256(payload).hexdigest()[:12]}"


def read_json(path: Path):
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def read_jsonl(path: Path):
    with path.open(encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def choose_sweqa(oracle_path: Path, noisy_path: Path) -> list[dict]:
    oracle = read_json(oracle_path)
    noisy = read_json(noisy_path)
    key = lambda row: (row["repo"], row["category"], row["question"], tuple(row["entities"]))
    noisy_by_key = {key(row): row for row in noisy}
    candidates = [row for row in oracle if key(row) in noisy_by_key]
    candidates = [row for row in candidates if len(row["code"]) <= 24000 and len(noisy_by_key[key(row)]["code"]) <= 48000]

    rng = random.Random(SEED)
    rng.shuffle(candidates)
    selected: list[dict] = []
    repo_counts: dict[str, int] = {}
    category_counts: dict[str, int] = {}
    answer_counts: dict[str, int] = {}
    for row in candidates:
        repo = row["repo"]
        category = row["category"]
        answer = row["correct_answer"]
        if repo_counts.get(repo, 0) >= 3:
            continue
        if category_counts.get(category, 0) >= 15:
            continue
        if answer_counts.get(answer, 0) >= 8:
            continue
        selected.append(row)
        repo_counts[repo] = repo_counts.get(repo, 0) + 1
        category_counts[category] = category_counts.get(category, 0) + 1
        answer_counts[answer] = answer_counts.get(answer, 0) + 1
        if len(selected) == 30:
            break
    if len(selected) != 30 or sorted(category_counts.values()) != [15, 15]:
        raise RuntimeError(f"could not construct balanced SWE-QA sample: {category_counts}")

    result = []
    for row in selected:
        pair_id = stable_id("sweqa", *key(row))
        for setting, source in (("oracle", row), ("noisy_oracle", noisy_by_key[key(row)])):
            result.append({
                "id": f"{pair_id}-{setting}",
                "pair_id": pair_id,
                "benchmark": "swe_qa",
                "subset": setting,
                "category": row["category"],
                "repo": row["repo"],
                "prompt_kind": "mcq_with_code",
                "code": source["code"],
                "question": row["question"],
                "choices": row["options"],
                "answer": row["correct_answer"],
            })
    return result


def choose_codemmlu(paths: list[Path]) -> list[dict]:
    result = []
    for offset, path in enumerate(paths):
        payload = read_json(path)
        subset = path.stem.removeprefix("codemmlu-")
        rows = [item["row"] for item in payload["rows"] if len(item["row"]["choices"]) == 4]
        rng = random.Random(SEED + offset + 1)
        rng.shuffle(rows)
        answer_counts: dict[str, int] = {}
        selected = []
        for row in rows:
            answer = row["answer"]
            if answer_counts.get(answer, 0) >= 3:
                continue
            selected.append(row)
            answer_counts[answer] = answer_counts.get(answer, 0) + 1
            if len(selected) == 10:
                break
        if len(selected) != 10:
            raise RuntimeError(f"not enough CodeMMLU rows in {subset}")
        for row in selected:
            result.append({
                "id": f"codemmlu-{subset}-{row['task_id']}",
                "benchmark": "code_mmlu",
                "subset": subset,
                "category": subset,
                "prompt_kind": "mcq",
                "question": row["question"],
                "choices": {chr(65 + i): choice for i, choice in enumerate(row["choices"])},
                "answer": row["answer"],
            })
    return result


def choose_cruxeval(path: Path) -> list[dict]:
    rows = read_jsonl(path)
    rng = random.Random(SEED + 10)
    rng.shuffle(rows)
    selected = rows[:30]
    result = []
    for row in selected:
        common = {
            "benchmark": "cruxeval",
            "category": "execution_reasoning",
            "code": row["code"],
            "source_id": row["id"],
        }
        result.append({
            **common,
            "id": f"cruxeval-output-{row['id']}",
            "subset": "output_prediction",
            "prompt_kind": "crux_output",
            "input": row["input"],
            "answer": row["output"],
        })
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--swe-oracle", type=Path, required=True)
    parser.add_argument("--swe-noisy", type=Path, required=True)
    parser.add_argument("--codemmlu", type=Path, action="append", required=True)
    parser.add_argument("--cruxeval", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    questions = choose_sweqa(args.swe_oracle, args.swe_noisy)
    questions += choose_codemmlu(args.codemmlu)
    questions += choose_cruxeval(args.cruxeval)
    if len(questions) != 120 or len({item["id"] for item in questions}) != 120:
        raise RuntimeError("expected exactly 120 unique requests")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as handle:
        for item in questions:
            handle.write(json.dumps(item, ensure_ascii=False, separators=(",", ":")) + "\n")


if __name__ == "__main__":
    main()
