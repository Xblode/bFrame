---
metadata_version: 1
title: "Dossier bFrame"
type: index
description: "Présente le dossier .bframe, qui regroupe le routeur, les conventions et la mémoire du projet."
summary: "Le routeur dit qui délègue à qui, les conventions fixent les règles communes, la mémoire garde les documents propres au projet. Seule la mémoire est spécifique au projet."
version: "0.2.3"
status: draft
created: "2026-11-07"
updated: "2026-11-07"
---

# Dossier bFrame

Commun à tous les projets, sauf `memory/`, qui est propre au projet et jamais copiée ailleurs.

## Où aller

| Pour | Aller à |
| --- | --- |
| Comprendre la délégation | `ROUTER.md` |
| Lire une règle commune | `conventions/README.md` |
| Retrouver une décision, une idée, l'arborescence | `memory/README.md` |

## État actuel

- Marche : routeur, quatre conventions, mémoire avec notes, cadrage et structure.
- Manque : préparer, reprendre et entretenir un projet ne sont pas encore cadrés ; le cadrage n'est pas clos.

`memory/` garde le cadrage, la vision et la structure du projet (`reference/`), les idées en discussion (`notes/`) et ce qui est validé et à faire (`tasks/`).

`template/` contient les modèles de la mémoire vierge, copiés à l'installation.

## Fonctionnalités qui passent ici

- Le process standard.
- Le cycle de vie des idées.
- Faire respecter les règles.
- Le périmètre du socle.

## Évolution

- 2026-11-06 : routeur et premières conventions (métadonnées, nommage).
- 2026-11-07 : process standard, taxonomie, mémoire du projet (cadrage, structure, notes).

## À ne pas faire

- Y placer un document propre au projet hors de `memory/`.
- Y mettre ce que Claude Code seul utilise : cela va dans `.claude/`.
