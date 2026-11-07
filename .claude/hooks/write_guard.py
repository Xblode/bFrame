# Verrou PreToolUse : limite les écritures de l'orchestrateur à .bframe/memory/notes/ et .bframe/memory/tasks/.
# Autorisé : aucune sortie, code 0. Refusé : JSON "permissionDecision": "deny" sur la sortie standard, code 0.
# La sortie 2 n'est pas utilisée : elle n'a pas bloqué lors de l'essai réel dans l'application de bureau, ce JSON si.
# Le hook se déclenche aussi pour les workers : un appel qui porte un agent_id passe sans contrôle.
import json
import os
import sys

MSG = ("Écriture refusée : l'orchestrateur écrit seulement dans .bframe/memory/notes/ "
       "et .bframe/memory/tasks/. Délègue cette modification à un worker. Chemin : {}")


def deny(text):
    out = {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                  "permissionDecision": "deny",
                                  "permissionDecisionReason": text}}
    sys.stdout.buffer.write(json.dumps(out).encode("utf-8"))
    sys.stdout.buffer.flush()
    sys.exit(0)


def norm(p):
    return os.path.normcase(os.path.normpath(os.path.abspath(p)))


def main():
    data = json.loads(sys.stdin.buffer.read().decode("utf-8"))
    if data.get("agent_id"):
        sys.exit(0)
    cwd = data.get("cwd") or ""
    root = os.environ.get("CLAUDE_PROJECT_DIR") or cwd
    if not root:
        deny("Contrôle d'écriture : racine du projet introuvable (CLAUDE_PROJECT_DIR et cwd absents).")
    path = data["tool_input"]["file_path"]
    if not isinstance(path, str) or not path:
        deny("Contrôle d'écriture : file_path absent ou invalide.")
    if not os.path.isabs(path):
        path = os.path.join(cwd or root, path)
    target = norm(path)
    base = norm(root)
    notes = norm(os.path.join(base, ".bframe", "memory", "notes"))
    if target.startswith(notes + os.sep):
        sys.exit(0)
    tasks = norm(os.path.join(base, ".bframe", "memory", "tasks"))
    if target.startswith(tasks + os.sep):
        sys.exit(0)
    deny(MSG.format(path))


try:
    main()
except SystemExit:
    raise
except BaseException as exc:
    deny("Contrôle d'écriture : erreur interne (%s: %s). Écriture refusée par précaution."
         % (type(exc).__name__, exc))
