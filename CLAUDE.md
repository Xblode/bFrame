---
metadata_version: 1
title: "Instructions du projet"
type: guide
description: "Explique l'usage de bFrame et décrit le projet qui l'utilise."
version: "0.1.2"
status: draft
created: "2026-11-06"
updated: "2026-11-07"
---

# bFrame

Framework pour lancer et piloter un projet, vide ou existant. Chaque conversation démarre en orchestrateur, qui délègue le travail aux workers.

@.bframe/ROUTER.md

## Fonctionnalités

- Agents : `.claude/agents/`.
- Conventions, lues à la demande : `.bframe/conventions/`.
- Structure d'un projet : `.bframe/memory/reference/STRUCTURE.md`.
- Notes et tâches : `.bframe/memory/notes/`, `.bframe/memory/tasks/`.
- Process standard : `.bframe/conventions/PROCESS.md`.
- Skills : `.claude/skills/`, lus à la demande.

## Règles

- Une proposition n'est pas une décision tant que l'humain ne l'a pas validée.
- Demander confirmation avant une action difficile à réparer.
- Pas de commit ni de push sans demande explicite.

---

# Projet

<!-- Décrire ici le projet : but, technologies, commandes, règles propres. Ce commentaire n'est pas chargé par Claude Code. -->
