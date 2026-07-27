# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
# type: ignore
"""Smoke-check the LSP adapter over a real stdio session.

`tests/lsp/` drives `Lsp_lib.Server` in process, which leaves `main.ml` —
capability advertisement and request dispatch — uncovered.  That gap is not
theoretical: the daily-note command was once handled in `on_request_unhandled`,
which linol never consults for `ExecuteCommand`, so a correct handler sat
unreachable while every test passed.  Nothing in the suite could see it,
because the bug was in which hook the handler hung off.

This script talks to the built binary the way an editor does and asserts the
effects an editor would observe.  Run it by hand after touching `main.ml`:

    dune build pkg/oystermark/lsp/main.exe
    uv run --script pkg/oystermark/lsp/scripts/smoke.py

Pass a path to check a different binary — the installed one, say:

    uv run --script pkg/oystermark/lsp/scripts/smoke.py $(which oystermark-lsp)
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
from typing import IO

DEFAULT_BINARY = "_build/default/pkg/oystermark/lsp/main.exe"
DAILY_NOTE_COMMAND = "oystermark.dailyNote.open"

NOTE = "note.md"
NOTE_TEXT = "# Hello\n\nsome prose.\n"


# Session
# =======


class Session:
    """One stdio LSP session, with the server's own requests recorded."""

    def __init__(self, binary, root):
        self.proc = subprocess.Popen(
            [binary],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        assert self.proc.stdin is not None and self.proc.stdout is not None
        self.stdin: IO[bytes] = self.proc.stdin
        self.stdout: IO[bytes] = self.proc.stdout
        self.root = root
        self.requests = []  # methods the server sent us, in order
        self.messages = []  # window/showMessage texts, in order
        self.next_id = 1

    def send(self, msg):
        body = json.dumps(msg).encode()
        self.stdin.write(b"Content-Length: %d\r\n\r\n" % len(body) + body)
        self.stdin.flush()

    def read(self):
        length = None
        while True:
            line = self.stdout.readline()
            if not line:
                return None
            line = line.strip()
            if not line:
                break
            if line.lower().startswith(b"content-length:"):
                length = int(line.split(b":")[1])
        if length is None:
            return None
        return json.loads(self.stdout.read(length))

    def request(self, method, params):
        """Send a request and pump until its response, acking anything the
        server asks of us on the way — a server request left unanswered can
        stall the exchange being measured."""
        id_ = self.next_id
        self.next_id += 1
        self.send({"jsonrpc": "2.0", "id": id_, "method": method, "params": params})
        while True:
            msg = self.read()
            if msg is None:
                raise RuntimeError(f"server closed the connection during {method}")
            if "method" in msg and msg.get("id") is not None:
                self.requests.append(msg["method"])
                result = (
                    {"applied": True}
                    if msg["method"] == "workspace/applyEdit"
                    else {"success": True}
                )
                self.send({"jsonrpc": "2.0", "id": msg["id"], "result": result})
            elif msg.get("method") == "window/showMessage":
                self.messages.append(msg["params"]["message"])
            elif msg.get("id") == id_:
                if "error" in msg:
                    raise RuntimeError(f"{method} failed: {msg['error']}")
                return msg.get("result")

    def notify(self, method, params):
        self.send({"jsonrpc": "2.0", "method": method, "params": params})

    def uri(self, rel_path):
        return "file://" + os.path.join(self.root, rel_path)

    def close(self):
        self.proc.kill()


# Checks
# ======

failures = []


def check(label, ok, detail="", hint=""):
    """[detail] is context worth seeing either way; [hint] is guidance that
    only matters once the check has failed."""
    note = detail or (hint if not ok else "")
    print(f"  {'PASS' if ok else 'FAIL'}  {label}{'  — ' + note if note else ''}")
    if not ok:
        failures.append(label)


def run(binary, show_document=True):
    root = tempfile.mkdtemp(prefix="oysterlsp-smoke-")
    with open(os.path.join(root, NOTE), "w") as f:
        f.write(NOTE_TEXT)

    s = Session(binary, root)
    try:
        # A bare vault: no oysterlsp.json, no initializationOptions.  Daily
        # notes must still work off their defaults.
        window = {"showDocument": {"support": True}} if show_document else {}
        caps = s.request(
            "initialize",
            {
                "processId": None,
                "rootUri": "file://" + root,
                "capabilities": {"window": window},
            },
        )["capabilities"]

        print("\ncapabilities")
        check("codeActionProvider", caps.get("codeActionProvider") is not None)
        check("codeLensProvider", caps.get("codeLensProvider") is not None)
        commands = (caps.get("executeCommandProvider") or {}).get("commands", [])
        check(
            "executeCommandProvider lists the daily-note command",
            DAILY_NOTE_COMMAND in commands,
            f"got {commands}",
        )

        s.notify("initialized", {})
        s.notify(
            "textDocument/didOpen",
            {
                "textDocument": {
                    "uri": s.uri(NOTE),
                    "languageId": "markdown",
                    "version": 1,
                    "text": NOTE_TEXT,
                }
            },
        )

        # Code actions: the daily-note menu, plus the command block offer.
        print("\ntextDocument/codeAction")
        actions = s.request(
            "textDocument/codeAction",
            {
                "textDocument": {"uri": s.uri(NOTE)},
                "range": {
                    "start": {"line": 2, "character": 0},
                    "end": {"line": 2, "character": 0},
                },
                "context": {"diagnostics": []},
            },
        )
        titles = [a["title"] for a in actions]
        check("daily-note actions offered", any("daily note" in t for t in titles))
        check(
            "command-block insert offered",
            any("command block" in t for t in titles),
            f"got {titles}",
        )

        # The seam that had no coverage: a command must reach the handler and
        # produce its two protocol effects.
        print("\nworkspace/executeCommand")
        daily = next((a for a in actions if a.get("command")), None)
        if daily is None:
            check("a code action carries a command", False)
        else:
            before, said = len(s.requests), len(s.messages)
            result = s.request(
                "workspace/executeCommand",
                {
                    "command": daily["command"]["command"],
                    "arguments": daily["command"]["arguments"],
                },
            )
            sent, messages = s.requests[before:], s.messages[said:]
            check(
                "reaches the handler (result is not null)",
                result is not None,
                hint="null means the request was dispatched to a hook that is "
                "not overridden — check which linol method handles it",
            )
            check("sends workspace/applyEdit", "workspace/applyEdit" in sent)
            if show_document:
                check("sends window/showDocument", "window/showDocument" in sent)
                check("stays quiet when the client can focus", not messages)
            else:
                # Where focusing is impossible the command must still say so:
                # silence is indistinguishable from failure.
                check(
                    "does not send window/showDocument",
                    "window/showDocument" not in sent,
                )
                check(
                    "reports the path instead",
                    any(root in m for m in messages),
                    f"said {messages}",
                )

        # Code lenses carry the same commands; a client that renders them is
        # the whole point of the command block.
        print("\ntextDocument/codeLens")
        panel = "```oysterlsp\ndaily/today\n```\n"
        s.notify(
            "textDocument/didChange",
            {
                "textDocument": {"uri": s.uri(NOTE), "version": 2},
                "contentChanges": [{"text": NOTE_TEXT + "\n" + panel}],
            },
        )
        lenses = s.request(
            "textDocument/codeLens", {"textDocument": {"uri": s.uri(NOTE)}}
        )
        check(
            "a command-block line gets a lens with a command",
            any(lens.get("command", {}).get("command") for lens in lenses),
            f"got {len(lenses)} lens(es)",
        )
    finally:
        s.close()
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    binary = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_BINARY
    if not os.path.exists(binary):
        sys.exit(
            f"no such binary: {binary}\n(build it with: dune build {DEFAULT_BINARY})"
        )
    print(f"smoke-checking {binary}")
    print("\n### client that supports window/showDocument")
    run(binary)
    # The other half of the world, and the one several editors are in: the
    # command cannot focus, and must say so rather than finish in silence.
    print("\n### client that does not support window/showDocument")
    run(binary, show_document=False)
    print(
        f"\n{len(failures)} failure(s)"
        + (": " + ", ".join(failures) if failures else "")
    )
    sys.exit(1 if failures else 0)
