# Hook UserPromptSubmit : avertit l'humain quand les notes n'ont pas bougé depuis THRESHOLD de ses messages. Ne bloque jamais.
import json
import os
import sys
from pathlib import Path

THRESHOLD = 3


def latest_mtime(root):
    latest = 0
    paths = []
    for d in (root / ".bframe" / "memory" / "notes", root / ".bframe" / "memory" / "tasks"):
        if d.is_dir():
            paths.extend(p for p in d.rglob("*") if p.is_file())
    for p in paths:
        try:
            if p.is_file():
                latest = max(latest, p.stat().st_mtime_ns)
        except OSError:
            pass
    return latest


def main():
    data = json.loads(sys.stdin.buffer.read().decode("utf-8"))
    prompt = data.get("prompt") or ""
    if prompt.lstrip().startswith("<"):
        return
    root = Path(os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or ".")
    session = data.get("session_id")
    signature = latest_mtime(root)

    state_file = root / ".claude" / "state" / "notes_reminder.json"
    state = None
    try:
        state = json.loads(state_file.read_text(encoding="utf-8"))
    except Exception:
        state = None

    warn = False
    if not isinstance(state, dict) or state.get("session_id") != session:
        count = 0
    elif state.get("signature") != signature:
        count = 0
    else:
        count = int(state.get("count", 0)) + 1
        if count >= THRESHOLD:
            count = 0
            warn = True

    state_file.parent.mkdir(parents=True, exist_ok=True)
    state_file.write_text(
        json.dumps({"session_id": session, "signature": signature, "count": count}),
        encoding="utf-8",
    )

    if warn:
        out = {
            "systemMessage": f"Attention : les notes n'ont pas bougé depuis {THRESHOLD} messages.",
            "hookSpecificOutput": {
                "hookEventName": "UserPromptSubmit",
                "additionalContext": (
                    f"Les notes et les tâches n'ont pas bougé depuis {THRESHOLD} messages de l'humain. "
                    "Vérifie s'il y a quelque chose à noter, selon .bframe/conventions/TAXONOMY.md."
                ),
            },
        }
        sys.stdout.buffer.write(json.dumps(out, ensure_ascii=False).encode("utf-8"))
        sys.stdout.buffer.flush()


if __name__ == "__main__":
    try:
        main()
    except BaseException:
        pass
    sys.exit(0)
