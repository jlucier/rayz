#!/usr/bin/env python3
"""Build and benchmark scene 0, or compare saved Hyperfine JSON results.

Benchmark configuration: ReleaseFast, 1440x810, 10 samples/pixel, seed 123,
one worker on CPU 0, one warmup, and five timed runs. Timings include startup
and PPM serialization. Set ZIG to select the compiler (default: zig).
"""

import argparse
import hashlib
import json
import math
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path


def benchmark(output):
    repo = Path(__file__).resolve().parent
    zig = os.environ.get("ZIG", "zig")

    for program in (zig, "hyperfine", "taskset"):
        if shutil.which(program) is None:
            raise ValueError(f"Required executable not found: {program}")

    version = subprocess.check_output([zig, "version"], text=True).strip()
    print(f"Zig: {version}\nResults: {output}", flush=True)
    subprocess.run([zig, "build", "-Doptimize=ReleaseFast"], cwd=repo, check=True)

    render = [
        "taskset",
        "-c",
        "0",
        str(repo / "zig-out/bin/rayz"),
        "1440",
        "--scene=0",
        "--noparallel",
        "--samples=10",
        "--seed=123",
    ]

    # Hash a render outside the timed runs without retaining the image in memory.
    digest = hashlib.sha256()
    with subprocess.Popen(
        render, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
    ) as process:
        for chunk in iter(lambda: process.stdout.read(65536), b""):
            digest.update(chunk)

        if process.wait() != 0:
            raise subprocess.CalledProcessError(process.returncode, render)

    print(f"PPM SHA-256: {digest.hexdigest()}", flush=True)
    subprocess.run(
        [
            "hyperfine",
            "--shell=bash",
            "--output=null",
            "--style=color",
            "--warmup",
            "1",
            "--runs",
            "5",
            "--export-json",
            str(output),
            "--command-name",
            "scene0-1440-seed123-serial",
            shlex.join(render),
        ],
        check=True,
    )


def load_results(path):
    with path.open() as file:
        data = json.load(file)

    results = data.get("results") if isinstance(data, dict) else None
    if not isinstance(results, list) or not results:
        raise ValueError(f"{path}: expected a nonempty Hyperfine results array")

    names = set()
    for result in results:
        if not isinstance(result, dict) or not isinstance(result.get("command"), str):
            raise ValueError(f"{path}: each result must have a command name")

        name = result["command"]
        if name in names:
            raise ValueError(f"{path}: duplicate command name: {name}")
        names.add(name)

        for field in ("mean", "stddev"):
            value = result.get(field)
            if (
                type(value) not in (int, float)
                or not math.isfinite(value)
                or value < 0
                or (field == "mean" and value == 0)
            ):
                raise ValueError(f"{path}: {name}: invalid {field}")

        if not isinstance(result.get("times"), list) or not result["times"]:
            raise ValueError(f"{path}: {name}: expected timing samples")

    return results


def compare(baseline_path, candidate_path):
    baseline = load_results(baseline_path)
    candidate = load_results(candidate_path)

    if len(baseline) == len(candidate) == 1:
        pairs = [(baseline[0], candidate[0])]
    else:
        candidates = {result["command"]: result for result in candidate}
        if {result["command"] for result in baseline} != set(candidates):
            raise ValueError("Multi-result files must contain matching command names")

        pairs = [(result, candidates[result["command"]]) for result in baseline]

    print(f"Baseline: {baseline_path}\nCandidate: {candidate_path}")
    for before, after in pairs:
        print(f"\n{before['command']} -> {after['command']}")
        for label, result in (("Baseline", before), ("Candidate", after)):
            print(
                f"  {label}: {result['mean']:.6f} s mean, "
                f"{result['stddev']:.6f} s SD ({len(result['times'])} runs)"
            )

        change = (after["mean"] / before["mean"] - 1) * 100
        speedup = before["mean"] / after["mean"]
        print(f"  Time change: {change:+.2f}%; speedup: {speedup:.3f}x")

    print(
        "\nNegative time change means faster. No statistical significance test is performed."
    )
    print("Check image hashes, compiler versions, and machine conditions separately.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="mode", required=True)
    run_parser = commands.add_parser(
        "run", help="Build ReleaseFast and benchmark scene 0"
    )
    run_parser.add_argument(
        "output", nargs="?", type=Path, default=Path("/tmp/rayz-benchmark.json")
    )
    compare_parser = commands.add_parser(
        "compare", help="Compare saved Hyperfine JSON files"
    )
    compare_parser.add_argument("baseline", type=Path)
    compare_parser.add_argument("candidate", type=Path)

    # Preserve the default invocation: ./benchmark.py [results.json].
    arguments = sys.argv[1:]
    if not arguments or arguments[0] not in ("run", "compare", "-h", "--help"):
        arguments.insert(0, "run")
    args = parser.parse_args(arguments)

    try:
        if args.mode == "compare":
            compare(args.baseline, args.candidate)
        else:
            benchmark(args.output)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"error: {error}\n")


if __name__ == "__main__":
    main()
