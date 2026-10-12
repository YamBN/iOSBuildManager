#!/usr/bin/env python3
"""Local JSON CLI for iOS Build Manager. Python 3, standard library only."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import uuid

TERMINAL = {"succeeded", "failed", "cancelled", "interrupted", "rejected", "completed"}


def identifier(value):
    return str(uuid.UUID(value)).upper()


def read_state(root):
    path = root / "Queue/state.json"
    if not path.exists():
        return {"version": 1, "paused": False, "jobs": []}
    state = json.loads(path.read_text())
    if state.get("version") != 1:
        raise ValueError("Unsupported queue state version")
    return state


def publish(root, request):
    queue = root / "Queue"
    inbox = queue / "inbox"
    inbox.mkdir(parents=True, exist_ok=True, mode=0o700)
    # Serialize clients, never rewrite an existing request ID. The app is the
    # only state writer; atomic publication lets it read complete commands only.
    with (queue / "clients.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        existing = next((j["request"] for j in read_state(root)["jobs"]
                         if j["request"]["id"] == request["id"]), None)
        destination = inbox / (request["id"] + ".json")
        if existing is None and destination.exists():
            existing = json.loads(destination.read_text())
        if existing is not None:
            if existing != request:
                raise ValueError("Request ID already used with different arguments")
            return
        fd, name = tempfile.mkstemp(prefix=".request-", dir=inbox)
        try:
            with os.fdopen(fd, "w") as stream:
                json.dump(request, stream)
                stream.flush()
                os.fsync(stream.fileno())
            os.link(name, destination)  # exclusive, atomic publication
        finally:
            os.unlink(name)


def launch_app(app):
    args = ["/usr/bin/open", "-g"]
    args += ["-a", app] if app else ["-b", "com.yambn.iOSBuildManager"]
    result = subprocess.run(args, capture_output=True, text=True)
    return None if result.returncode == 0 else "Request saved, but the app could not be opened. Launch the updated app manually."


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--support-dir", type=Path,
                        default=Path.home() / "Library/Application Support/iOSBuildManager")
    parser.add_argument("--app", help="Updated .app path to launch (otherwise use bundle identifier)")
    parser.add_argument("--no-launch", action="store_true", help="Save only; app must already be running")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("projects", help="List configured projects")
    sub.add_parser("queue", help="Read all durable jobs and paused state")
    enqueue = sub.add_parser("enqueue", help="Submit one build; returns immediately")
    source = enqueue.add_mutually_exclusive_group(required=True)
    source.add_argument("--project-id", type=identifier)
    source.add_argument("--project", help="Absolute Xcode project/workspace or Swift package path")
    enqueue.add_argument("--scheme")
    enqueue.add_argument("--configuration", choices=["Debug", "Release"])
    enqueue.add_argument("--output", help="Output root; artifacts are isolated under project ID / job ID")
    enqueue.add_argument("--request-id", type=identifier, help="Reuse on transport retry to prevent duplicate builds")
    enqueue.add_argument("--clean", action="store_true")
    enqueue.add_argument("--install-on-device", action="store_true", help="Also try installing on the first connected device")
    for name in ("status", "wait", "cancel"):
        command = sub.add_parser(name)
        command.add_argument("id", type=identifier)
        if name == "wait":
            command.add_argument("--timeout", type=float, default=1800)
    resume = sub.add_parser("resume", help="Resume after a worker crash, once orphan builds have stopped")
    resume.add_argument("--confirm-no-active-builds", required=True, action="store_true")
    args = parser.parse_args(argv)
    root = args.support_dir.expanduser().resolve()
    if args.command == "projects":
        path = root / "projects.json"
        print(json.dumps(json.loads(path.read_text()) if path.exists() else []))
        return 0
    if args.command == "queue":
        print(json.dumps(read_state(root)))
        return 0
    if args.command in ("status", "wait"):
        deadline = time.monotonic() + (args.timeout if args.command == "wait" else 0)
        while True:
            state = read_state(root)
            job = next((j for j in state["jobs"] if j["request"]["id"] == args.id), None)
            if job is None:
                pending = root / "Queue/inbox" / (args.id + ".json")
                job = {"id": args.id, "state": "submitted" if pending.exists() else "not_found"}
            if args.command == "status" or job["state"] in TERMINAL or job["state"] == "not_found":
                print(json.dumps(job))
                return 0 if job["state"] not in {"failed", "cancelled", "interrupted", "rejected", "not_found"} else 1
            if time.monotonic() >= deadline:
                print(json.dumps({"error": "timeout", "job": job, "paused": state["paused"]}))
                return 2
            time.sleep(0.5)
    request = {"version": 1, "id": str(uuid.uuid4()).upper(), "action": args.command}
    if args.command == "enqueue":
        request["id"] = args.request_id or request["id"]
        for field, value in (("projectId", args.project_id), ("projectPath", args.project),
                             ("scheme", args.scheme), ("configuration", args.configuration),
                             ("outputDirectory", args.output)):
            if value is not None:
                if field in ("projectPath", "outputDirectory"):
                    value = str(Path(value).expanduser().resolve())
                request[field] = value
        if args.clean:
            request["clean"] = True
        if args.install_on_device:
            request["installOnDevice"] = True
    if args.command == "cancel":
        request["targetId"] = args.id
    publish(root, request)
    reply = {"id": request["id"], "state": "submitted"}
    if not args.no_launch:
        warning = launch_app(args.app)
        if warning:
            reply["warning"] = warning
    print(json.dumps(reply))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError) as error:
        print(json.dumps({"error": str(error)}), file=sys.stderr)
        sys.exit(1)
