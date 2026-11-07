---
metadata_version: 1
title: "Convention de nommage"
type: convention
description: "Règles de nommage des fichiers et dossiers : concept, casse, variantes, portabilité, exceptions."
version: "0.1.1"
status: draft
created: "2026-11-06"
updated: "2026-11-07"
scope:
  level: universal
  targets:
    - all-projects
---

# Convention de nommage

## 1. Principes

- Nommer selon le concept et la responsabilité ; nom court.
- Le chemin donne le contexte : `components/card.tsx`, pas `components/component-card.tsx`.
- Pas de qualificatifs creux (`main`, `primary`, `global`, `default`, `base`, `manager`, `handler`, `component`, `module`, `file`) sauf distinction réelle.
- Nom stable : pas de `new-`, `-v2`, `-final`.

## 2. Casse

- `kebab-case` par défaut.
- `UPPER_SNAKE_CASE` pour les documents de référence (`VISION.md`).
- Noms imposés conservés : `README.md`, `CLAUDE.md`, `SKILL.md`, `package.json`...
- Conventions du langage respectées : Python `snake_case`, Java `PascalCase`.
- Extensions en minuscules.
- React : fichier en `kebab-case` (`card.tsx`), composant en `PascalCase` (`Card`).
- Hooks préfixés `use-` (`use-cart.ts`).
- Tests selon le framework (`card.test.tsx`).

## 3. Fichiers

- Une responsabilité identifiable.
- Nom composé seulement s'il distingue (`payment-gateway.ts`).
- Pas de préfixe redondant avec le dossier ou l'extension.
- Abréviations reconnues seulement (`api`, `ui`, `db`).

## 4. Dossiers

- `kebab-case`. Noms génériques permis (`docs`, `src`, `assets`) si leur périmètre est clair.
- Pluriel pour une collection (`components/`), singulier pour un domaine (`auth/`).
- Un niveau de plus seulement s'il se justifie.

## 5. Variantes

Regrouper les variantes d'un même concept dans un seul fichier (`card.tsx` avec une prop `variant`). Séparer quand la responsabilité devient indépendante, a une logique métier propre, est réutilisée seule, ou répond à une contrainte technique. Éviter les deux extrêmes : un fichier par variante, ou un fichier fourre-tout.

## 6. Noms à risque

`index`, `config`, `utils`, `types`, `common`, `shared`, `helpers` : permis si leur périmètre reste identifiable. `index` seulement pour un point d'entrée attendu par un outil ou l'export public d'un module.

Collision, ordre de résolution : (1) contexte du dossier, (2) séparer les domaines, (3) qualificatif utile, (4) nomenclature imposée par l'outil.

## 7. Médias

Nom selon le contenu (`logo.svg`, `hero.webp`) ; variante seulement si réelle (`logo-dark.svg`).

## 8. Générés et temporaires

Fichiers générés aux emplacements prévus (`dist/`, `build/`), temporaires dans `tmp/` ou `cache/`. Pas de `-old`, `-copy`, `-backup`.

## 9. Portabilité

- ASCII, sans espace ni accent.
- Caractères interdits : `< > : " / \ | ? *`.
- Pas d'espace ni de point final.
- Éviter les noms réservés Windows (`CON`, `PRN`, `AUX`, `NUL`, `COM1`, `LPT1`).
- Jamais deux noms qui diffèrent seulement par la casse.

## 10. Exceptions

Permises face à une contrainte réelle (framework, outil, API externe, convention établie cohérente), limitées à leur périmètre. Une exception durable est documentée : règle concernée, périmètre, justification, comportement attendu.

Priorité : (1) contrainte de l'outil, (2) exception du projet, (3) convention spécialisée, (4) convention générale.

## 11. Règles pour les agents

- Avant de créer : chercher si un fichier existant convient.
- Pas de nouveau fichier pour une simple variante.
- Pas de renommage massif.
- Après renommage, corriger imports et références.
- Respecter une convention existante cohérente ; ne pas normaliser les fichiers existants.
- Pas de convention concurrente.
- Décision d'architecture : signaler les options.
