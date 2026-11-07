---
metadata_version: 1
title: "Convention du process standard"
type: convention
description: "Chemin de travail appliqué à chaque sujet, sur tous les projets, avec le renvoi vers la règle de chaque étape."
version: "0.3.3"
status: draft
created: "2026-11-07"
updated: "2026-11-07"
scope:
  level: universal
  targets:
    - all-projects
---

# Process standard

Le chemin que bFrame suit à chaque sujet, sur tous les projets. Ce document donne l'ordre et renvoie aux règles sans les recopier. Préparer ou reprendre un projet passe par l'onboarding, sur demande de l'humain : `.claude/skills/onboarding/SKILL.md`.

## 1. Les 8 étapes

| Étape | Ce qui se passe | Qui | Règle |
| --- | --- | --- | --- |
| 1. Reprendre | Dire où on en est et ce qui attend, à partir de l'index des tâches et de l'index des notes | Orchestrateur | `.claude/agents/orchestrator.md` |
| 2. Brainstormer | Creuser des sujets nommés, retrouver les notes liées, rappeler le sujet en cours | Orchestrateur et humain | `.claude/agents/orchestrator.md`, `TAXONOMY.md` §6 |
| 3. Noter | À chaque message : idées, décisions, résultats de recherche | Orchestrateur | `TAXONOMY.md` §4 et §5 |
| 4. Valider | Le contenu ressort par petits lots de questions à choix ; ce qui est validé part dans `.bframe/memory/tasks/` | Humain | `TAXONOMY.md` §7 |
| 5. Planifier | Un plan avec deux boutons, jamais lancé seul | L'orchestrateur propose, l'humain lance | `TAXONOMY.md` §8, `ROUTER.md` §3 |
| 6. Déléguer et contrôler | Des workers en arrière-plan avec un brief précis, et chaque résultat contrôlé avant la suite | Workers et orchestrateur | `ROUTER.md` §2, §4, §5 et §6 |
| 7. Mettre à jour | Dire ce qui est fait (§2) | Orchestrateur et worker | Ce document, §2 |
| 8. Proposer la suite | Proposer sur quoi continuer, puis `/compact` si la conversation s'allonge | Orchestrateur | `.claude/agents/orchestrator.md` |

## 2. Mettre à jour

À la fin d'un plan, dans cet ordre :

1. La dernière tâche du plan revient à un worker : il suit `.claude/skills/readme/SKILL.md` pour les README des dossiers touchés, et met à jour `.bframe/memory/reference/STRUCTURE.md` si l'arborescence a changé.
2. L'orchestrateur contrôle son travail, coche les tâches, archive celles qui sont faites et met l'index à jour (`TAXONOMY.md` §9), puis passe les notes concernées au statut `faite`.

Un plan n'est terminé qu'après cette étape.
