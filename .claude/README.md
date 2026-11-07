---
metadata_version: 1
title: "Adaptateur Claude Code"
type: index
description: "Explique ce que Claude Code utilise dans ce dossier pour appliquer le routeur."
summary: "Agents, hooks, règles et skill par lesquels Claude Code applique le routeur ; garanties partielles listées plus bas, aucune convention ici."
version: "0.13.1"
status: draft
created: "2026-11-06"
updated: "2026-11-07"
---

# Adaptateur Claude Code

Ce dossier contient ce que Claude Code utilise pour appliquer `.bframe/ROUTER.md`.

## Fonctionnalités

| Agent | Modèle | Outils |
| --- | --- | --- |
| `orchestrator` | `opus` | `Read`, `Grep`, `Glob`, `Edit` et `Write` limités par un hook, `Agent` limité aux workers, `SendMessage`, `TaskStop`, `AskUserQuestion`, `mcp__ccd_turn__update_plan` |
| `worker-sonnet` | `sonnet` | `Read`, `Grep`, `Glob`, `Edit`, `Write`, `Bash`, outils externes du projet (`mcp__*`) seulement si le brief l'autorise |
| `worker-haiku` | `haiku` | `Read`, `Grep`, `Glob`, `Edit`, `Bash` |
| `worker-web` | `sonnet` | `Read`, `Grep`, `Glob`, `WebSearch`, `WebFetch`, navigateur Playwright isolé |

- `settings.json` démarre l'orchestrateur, à partir de la conversation suivante. `rules/` renvoie vers les conventions selon le fichier touché (`documents.md` : `.bframe/memory/reference/`).
- Les workers démarrent sans `CLAUDE.md` (`omitClaudeMd`) : le brief est leur source principale. Ils tournent en arrière-plan (`background: true`), visibles dans « Background tasks », au menu ⋮ de l'application.
- `hooks/write_guard.py` limite les écritures de l'orchestrateur à `.bframe/memory/notes/` et `.bframe/memory/tasks/`. Il se déclenche aussi pour les workers, et les laisse passer car leur appel porte un `agent_id`.
- `hooks/bash_guard.py` demande confirmation à l'humain avant une commande `Bash` irréversible : `git commit`, `git push`, `git clean`, suppression récursive (`rm -r`, `Remove-Item -Recurse`, `rmdir /s`, `rd /s`, `del /s`). Confirmation, pas refus : commit et push restent permis sur demande explicite.
- `hooks/notes_reminder.py` avertit l'humain quand les notes n'ont pas bougé depuis 3 de ses messages. Il ne bloque jamais, et garde son état dans `state/`. `hooks/after_compact.py` redonne le sujet en cours et le chemin des notes après un résumé.
- `skills/readme/` explique aux workers comment entretenir les README. Il ne se lance pas seul.
- Le process standard et le cycle de vie des idées passent par l'orchestrateur, ses règles et ses hooks.
- `skills/onboarding/` guide l'onboarding d'un projet, vide ou existant. Essayé en simulation seulement, pas encore sur un vrai projet.

## État actuel

- Marche : orchestrateur, workers, hooks, skill d'entretien des README. Dans un projet, `.bframe/memory/` suit Git ; l'installation ajoute un bloc balisé au `.gitignore`.

## Ce qui n'est pas garanti

- `Bash` permet à `worker-sonnet` et `worker-haiku` de contourner leurs interdits : seule la consigne s'y oppose.
- Le paramètre `model` de l'outil Agent peut surcharger le modèle d'un worker : seule la consigne l'interdit.
- Un worker ne peut pas interroger l'orchestrateur : il s'arrête en `blocked`.
- La liste de tâches vient de l'application de bureau : ailleurs, l'orchestrateur la donne dans sa réponse.
- Le verrou d'écriture laisse passer si Python ne peut pas se lancer, et la documentation le dit lié au dialogue de confiance du dossier. Il est essayé en conversation réelle : refus de l'orchestrateur (Edit, Write) et passage d'un worker (Edit). Il repose sur le champ `agent_id`, observé mais pas garanti par la documentation.
- La confirmation de `bash_guard.py` repose sur des motifs dans le texte de la commande : contournable (variable, script, autre outil), faux positif possible sur un texte qui cite une commande. Ce n'est pas une barrière de sécurité. Essai réel du 2026-11-07 : la fenêtre de confirmation s'affiche pour un worker en arrière-plan, en mode Auto. Un worker ne voit pas cette fenêtre : son rapport ne prouve rien sur ce point. Refuser la fenêtre n'a pas été essayé.
- Outils externes : `worker-sonnet` hérite des outils de la conversation, dont les outils externes (`mcp__*`) du projet, car il n'a qu'une liste d'interdits (`disallowedTools`). Seule la consigne (brief qui nomme l'outil et les actions) limite leur usage. Le hook de confirmation ne couvre que `Bash`, aucun garde-fou technique sur ces outils. Accès réel non essayé. `worker-haiku` et l'orchestrateur n'en ont aucun.
- L'avertissement sur les notes peut sonner à tort si l'humain répond seulement par de simples accords. Il repose sur la date des fichiers, et ne dit rien de la qualité des notes.
- Le navigateur de `worker-web` a besoin de Node et se télécharge au premier usage. Sans lui, le worker garde `WebSearch` et `WebFetch`. Rien ne l'empêche techniquement de remplir un formulaire : seule la consigne s'y oppose.

## Exception de nommage

`worker-sonnet` et `worker-haiku` portent le nom de leur modèle, à la demande de l'humain : exception à NAMING §1, limitée à `agents/`. Si le modèle d'un worker change, renommer son fichier.

## Évolution

- 2026-11-06 : création des quatre agents.
- 2026-11-07 : skill d'entretien des README.
- 2026-11-07 : règle `documents.md`, outils externes pour `worker-sonnet`, bloc `.gitignore` posé par l'installation.

## À ne pas faire

Ne pas placer ici de conventions ni de règles de délégation : elles vont dans `.bframe/`.
