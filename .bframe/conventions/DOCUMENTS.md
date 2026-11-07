---
metadata_version: 1
title: "Convention des documents standards"
type: convention
description: "Catalogue des documents standards d'un projet bFrame : trois documents de base obligatoires, catalogue facultatif, règles de proposition et d'évolution."
version: "0.1.2"
status: draft
created: "2026-11-07"
updated: "2026-11-07"
scope:
  level: universal
  targets:
    - all-projects
---

# Convention des documents standards

## 1. Les trois documents de base

Obligatoires dans chaque projet, dans `.bframe/memory/reference/`. La liste de ces trois documents ne change jamais. Leur contenu évolue avec le projet ; leur plan interne n'est pas figé.

| Document | Question | Ne contient pas |
| --- | --- | --- |
| `VISION.md` | Pourquoi ce projet existe-t-il ? | Décisions, périmètre, organisation des fichiers |
| `CADRAGE.md` | Qu'est-ce qui est décidé, et quel est le périmètre ? | Les raisons d'être du projet, l'arborescence |
| `STRUCTURE.md` | Comment le projet est-il rangé ? | Les objectifs, les décisions de périmètre |

Chaque information a un seul propriétaire : les objectifs relèvent de la vision, le contexte et le périmètre du cadrage. Un document renvoie vers l'autre au lieu de répéter.

## 2. Le catalogue facultatif

Un document par responsabilité, créé seulement si le besoin existe.

| Responsabilité | Rôle |
| --- | --- |
| Données | Ce que le projet manipule et comment c'est organisé |
| Parcours | Comment les utilisateurs accomplissent leurs tâches |
| Design | Identité visuelle et règles d'interface |
| Services | Les composants ou services et leurs rôles |
| Plan | Étapes, ordre et échéances du travail |
| Exploitation | Faire tourner et surveiller le projet |
| Sécurité | Risques, protections, accès |
| Tests | Ce qui est vérifié et comment |
| Déploiement | Comment le projet est livré et mis en ligne |
| Intégrations | Les liens avec des systèmes externes |

## 3. Quand proposer un document

- bFrame propose un document facultatif quand un besoin réel apparaît, explique pourquoi, et attend l'accord de l'humain. Sans accord, rien n'est créé.
- Le choix des documents selon le type de projet est prévu avec les modules, après le socle. Il n'est pas décrit ici.

## 4. Faire évoluer le catalogue

Ajouter, fusionner ou retirer un document du catalogue facultatif demande l'accord de l'humain. Les trois documents de base sont exclus de cette possibilité.

## 5. Ce qui n'est pas ici

- La création automatique des documents à l'onboarding : à cadrer plus tard.
- Les notes et les tâches : `TAXONOMY.md`.
- Les README de dossier et les métadonnées : `METADATA.md`.
