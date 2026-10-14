#!/usr/bin/env python3
"""Build and record the current capture behavior without changing application sources."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import statistics
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
BUILD = Path(tempfile.gettempdir()) / "scrollsnap-baseline-build"


def run(command, log, cwd=REPO, allow_failure=False):
    if command[0] == "xcodebuild":
        inventory = subprocess.run(["pgrep", "-lx", "xcodebuild"], capture_output=True, text=True)
        if inventory.returncode != 1:
            raise RuntimeError("Cannot start another Xcode build: " + (inventory.stdout + inventory.stderr).strip())
    print("Running:", " ".join(map(str, command)), flush=True)
    env = os.environ.copy()
    env["CLANG_MODULE_CACHE_PATH"] = str(BUILD / "module-cache")
    with log.open("w") as stream:
        result = subprocess.run(list(map(str, command)), cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT)
    if result.returncode and not allow_failure:
        raise RuntimeError(f"Command exited {result.returncode}; see {log}")
    return result.returncode


def content_matches(observation):
    return (abs(observation["actualHeight"] - observation["expectedHeight"]) <= 1
            and observation["actualRows"] == observation["expectedRows"])


def replay_report(output):
    observations = json.loads((output / "replay/observations.json").read_text())
    lines = ["# Capture replay baseline", "", "Measured matcher/stitcher behavior only; no live screen capture or UI input.",
             "Timing excludes fixture generation and image export. CPU is process CPU time, not UI responsiveness.",
             "A failed expectation is recorded honestly; recording a baseline does not imply the tests passed.", "",
             "Expected content checks height and row order; image checks additionally require pixel fidelity and the expected warning state.", "",
             "| Scenario | Scale | Expected content | Image checks | Median processing ms | Median CPU ms |",
             "| --- | --- | --- | --- | --- | --- |"]
    for key in sorted({(o["scenario"], o["scale"]) for o in observations}):
        items = [o for o in observations if (o["scenario"], o["scale"]) == key]
        passed = sum(o["accurate"] for o in items)
        lines.append(f"| {key[0]} | {key[1]}x | {sum(content_matches(o) for o in items)}/{len(items)} | {passed}/{len(items)} | "
                     f"{statistics.median(o['processingMilliseconds'] for o in items):.1f} | "
                     f"{statistics.median(o['cpuMilliseconds'] for o in items):.1f} |")
    lines += ["", "See replay/observations.json and the expected/actual PNGs for individual measurements.",
              "Reverse scenarios expect the furthest captured extent to be preserved.",
              "Pinned-header validation ignores rows completely obscured in the initial viewport.",
              "Conversation captures check pixel fidelity in each 64-row band; conversation-gap expects the initial viewport and an incomplete warning.",
              "Memory and actual-app responsiveness are not measured by this replay runner."]
    (output / "report.md").write_text("\n".join(lines) + "\n")


def compare(output, baseline):
    before_meta = json.loads((baseline / "metadata.json").read_text())
    after_meta = json.loads((output / "metadata.json").read_text())
    for key in ["macos", "architecture", "configuration"]:
        if before_meta.get(key) != after_meta.get(key):
            raise RuntimeError(f"Cannot compare like-for-like: {key} differs")
    for source in ["FixtureDocument.swift", "ConversationFixture.swift", "Replay.swift"]:
        if before_meta["baseline_sources"][source] != after_meta["baseline_sources"][source]:
            raise RuntimeError(f"Cannot compare like-for-like: {source} differs")
    before = json.loads((baseline / "replay/observations.json").read_text())
    after = json.loads((output / "replay/observations.json").read_text())
    if {(o["scenario"], o["scale"]) for o in before} != {(o["scenario"], o["scale"]) for o in after}:
        raise RuntimeError("Cannot compare like-for-like: scenarios differ")
    lines = ["# Before / after replay comparison", "", f"Baseline: {baseline}", f"Current: {output}", "",
             "| Scenario | Scale | Content before | Content after | Image checks before | Image checks after | Processing time change |",
             "| --- | --- | --- | --- | --- | --- | --- |"]
    for key in sorted({(o["scenario"], o["scale"]) for o in before}):
        a = [o for o in before if (o["scenario"], o["scale"]) == key]
        b = [o for o in after if (o["scenario"], o["scale"]) == key]
        if len(a) != len(b): raise RuntimeError(f"Workload differs: {key}")
        delta = statistics.median(o["processingMilliseconds"] for o in b) - statistics.median(o["processingMilliseconds"] for o in a)
        lines.append(f"| {key[0]} | {key[1]}x | {sum(content_matches(o) for o in a)}/{len(a)} | "
                     f"{sum(content_matches(o) for o in b)}/{len(b)} | {sum(o['accurate'] for o in a)}/{len(a)} | "
                     f"{sum(o['accurate'] for o in b)}/{len(b)} | {delta:+.1f} ms |")
    (output / "comparison.md").write_text("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=["replay", "ui-build", "ui"], default="replay")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--app-bundle", type=Path, help="Use an already-built ScrollSnap app bundle")
    parser.add_argument("--app-configuration", choices=["Debug", "Release"], default="Debug", help="Configuration of the supplied app")
    parser.add_argument("--app-source-root", type=Path, help="Source checkout used to build a supplied app")
    parser.add_argument("--compare", type=Path, help="Compare replay results with an existing baseline directory")
    parser.add_argument("--only-test", help="Run one UI test method, for example testNormalCapturesWithoutRestarting")
    args = parser.parse_args()
    output = args.output or Path(tempfile.mkdtemp(prefix="scrollsnap-baseline-"))
    output = output.resolve()
    if (output / "replay/observations.json").exists() or (output / "ui.xcresult").exists():
        raise RuntimeError("Results already exist in this directory; choose another output to preserve the baseline")
    output.mkdir(parents=True, exist_ok=True)
    BUILD.mkdir(parents=True, exist_ok=True)
    source_root = (args.app_source_root or REPO).resolve()
    sources = sorted((source_root / "ScrollSnap").rglob("*.swift"))
    metadata = {"date": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip(),
                "macos": platform.mac_ver()[0], "architecture": platform.machine(), "mode": args.mode,
                "configuration": "Release" if args.mode == "replay" else "Debug",
                "app_configuration": args.app_configuration if args.mode != "replay" else "Release",
                "app_source_root": str(source_root),
                "ui_test_filter": args.only_test,
                "application_sources": {str(p.relative_to(source_root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}}
    metadata["baseline_sources"] = {str(p.relative_to(HERE)): hashlib.sha256(p.read_bytes()).hexdigest()
                                    for p in sorted(HERE.rglob("*")) if p.is_file() and p.suffix in [".swift", ".py", ".pbxproj", ".xcscheme"]}
    (output / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Artifacts: {output}", flush=True)
    if args.mode == "replay":
        run(["swiftc", "-swift-version", "5", "-O", "-module-cache-path", BUILD / "module-cache",
             REPO / "ScrollSnap/Managers/StitchingManager.swift",
             HERE / "FixtureDocument.swift", HERE / "ConversationFixture.swift", HERE / "Replay.swift", "-o", BUILD / "replay"], output / "compile.log")
        run([BUILD / "replay", output / "replay"], output / "replay.log")
        replay_report(output)
        if args.compare: compare(output, args.compare.resolve())
        print(f"Report: {output / 'report.md'}")
        return
    app = args.app_bundle
    if app is None:
        run(["xcodebuild", "-project", REPO / "ScrollSnap.xcodeproj", "-scheme", "ScrollSnap",
             "-configuration", "Debug", "-destination", "platform=macOS", "-derivedDataPath", BUILD / "App",
             "CODE_SIGN_IDENTITY=-", "DEVELOPMENT_TEAM=", "build"], output / "app-build.log")
        app = BUILD / "App/Build/Products/Debug/ScrollSnap Dev.app"
    if not app.is_dir():
        raise RuntimeError(f"Missing development app: {app}")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    metadata["tested_app"] = {"path": str(app.resolve()), "bundle_id": info["CFBundleIdentifier"],
                              "version": info.get("CFBundleShortVersionString"),
                              "binary_sha256": hashlib.sha256(executable.read_bytes()).hexdigest()}
    (output / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    action = "build-for-testing" if args.mode == "ui-build" else "test"
    command = ["xcodebuild", "-project", HERE / "CaptureBaseline.xcodeproj", "-scheme", "CaptureBaseline",
               "-configuration", "Debug", "-destination", "platform=macOS", "-derivedDataPath", BUILD / "UI",
               f"SCROLLSNAP_APP_PATH={app.resolve()}", "CODE_SIGN_IDENTITY=-", "DEVELOPMENT_TEAM="]
    if action == "test":
        command += ["-resultBundlePath", output / "ui.xcresult"]
        if args.only_test: command += [f"-only-testing:CaptureUITests/CaptureUITests/{args.only_test}"]
    exit_code = run(command + [action], output / "ui.log", allow_failure=action == "test")
    if action == "test":
        summary = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", output / "ui.xcresult"],
                                 capture_output=True, text=True)
        (output / "ui-summary.json").write_text(summary.stdout)
        if summary.returncode:
            raise RuntimeError("UI run completed, but its summary could not be collected; inspect ui.xcresult")
        result = json.loads(summary.stdout)
        if not result.get("totalTestCount"):
            raise RuntimeError("No UI tests ran; check the --only-test method name and ui-summary.json")
        if exit_code or result.get("failedTests", 0):
            raise RuntimeError(f"UI run failed (exit {exit_code}); inspect ui-summary.json and ui.xcresult")
        if result.get("skippedTests", 0):
            raise RuntimeError("UI tests were skipped (possibly an OS permission blocker); inspect ui.xcresult. This is not a complete UI baseline.")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
