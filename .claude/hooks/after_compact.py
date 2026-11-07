# Redonne à l'orchestrateur le sujet en cours et le chemin des notes après un résumé de la conversation (SessionStart, matcher compact). Ne bloque jamais.
import json
import os
import sys

PREFIXE = "**Sujet en cours :**"


def lire_sujet(racine):
    try:
        with open(os.path.join(racine, ".bframe", "memory", "tasks", "README.md"), encoding="utf-8") as f:
            for ligne in f:
                if ligne.startswith(PREFIXE):
                    return ligne[len(PREFIXE):].strip()
    except Exception:
        pass
    return ""


def main():
    racine = os.environ.get("CLAUDE_PROJECT_DIR")
    if not racine:
        data = json.loads(sys.stdin.buffer.read().decode("utf-8"))
        racine = data.get("cwd")
    if not racine:
        return
    sujet = lire_sujet(racine).rstrip(".").strip()
    texte = "La conversation vient d'être résumée. "
    if sujet:
        texte += "Sujet en cours : " + sujet + ". "
    texte += (
        "Reprends avec .bframe/memory/tasks/README.md et .bframe/memory/notes/README.md, "
        "selon .bframe/conventions/PROCESS.md."
    )
    sortie = {
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": texte,
        }
    }
    sys.stdout.buffer.write(json.dumps(sortie, ensure_ascii=False).encode("utf-8"))
    sys.stdout.buffer.flush()


try:
    main()
except Exception:
    pass
sys.exit(0)
