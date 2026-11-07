# Garde PreToolUse sur Bash : demande confirmation à l'humain avant git commit, git push, git clean et une suppression récursive.
# Commande visée ou erreur interne : JSON "permissionDecision": "ask" sur la sortie standard, code 0. Autre commande : aucune sortie, code 0.
# Détection par motifs sur le texte de la commande : contournable, faux positifs possibles. Ce n'est pas une barrière de sécurité.
# La sortie 2 n'est pas utilisée (voir write_guard.py).
import json
import re
import sys

OPT = r"(?:\s+-{1,2}[\w-]+(?:\s+[^\s-]\S*)?)*"  # options de git placées avant la sous-commande
ARGS = r"[^;&|\n]*?"  # le reste de la même commande simple
PATTERNS = [
    ("git commit", r"\bgit" + OPT + r"\s+commit\b"),
    ("git push", r"\bgit" + OPT + r"\s+push\b"),
    ("git clean", r"\bgit" + OPT + r"\s+clean\b"),
    ("rm récursif", r"\brm\s+(?:" + ARGS + r"\s)?(?:-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)(?=\s|$)"),
    ("Remove-Item -Recurse", r"\bRemove-Item\b" + ARGS + r"\s-r(?:ec\w*)?(?=\s|$|:)"),
    ("rmdir /s", r"\b(?:rmdir|rd)\s+(?:" + ARGS + r"\s)?/s(?=\s|$)"),
    ("del /s", r"\b(?:del|erase)\s+(?:" + ARGS + r"\s)?/s(?=\s|$)"),
]


def ask(text):
    out = {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                  "permissionDecision": "ask",
                                  "permissionDecisionReason": text}}
    sys.stdout.buffer.write(json.dumps(out).encode("utf-8"))
    sys.stdout.buffer.flush()
    sys.exit(0)


def main():
    data = json.loads(sys.stdin.buffer.read().decode("utf-8"))
    command = data["tool_input"]["command"]
    if not isinstance(command, str):
        ask("Contrôle des commandes : command n'est pas un texte. Confirmation demandée par précaution.")
    for name, pattern in PATTERNS:
        if re.search(pattern, command, re.IGNORECASE):
            ask("Commande irréversible détectée (%s). Confirme avant de l'exécuter : %s" % (name, command))
    sys.exit(0)


try:
    main()
except SystemExit:
    raise
except BaseException as exc:
    ask("Contrôle des commandes : erreur interne (%s: %s). Confirmation demandée par précaution."
        % (type(exc).__name__, exc))
