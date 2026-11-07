---
metadata_version: 1
title: "Convention des métadonnées"
type: convention
description: "Règles des métadonnées de documents : front matter, propriétés, statuts, versions, README de dossier."
version: "0.3.0"
status: draft
created: "2026-11-06"
updated: "2026-11-07"
scope:
  level: universal
  targets:
    - all-projects
---

# Convention des métadonnées

## 1. Principes

Ne déclarer que les propriétés utiles. Ne pas dupliquer une information déjà disponible dans une source fiable.

## 2. Front matter Markdown

- Premier élément du fichier, entre deux lignes `---`, YAML valide, un seul bloc.
- Propriétés en `snake_case`.
- Dates entre guillemets, format `"YYYY-MM-DD"`.
- Propriétés non pertinentes omises.

## 3. Propriétés

Obligatoire : toujours. Recommandé : quand son utilité est avérée. Conditionnel : seulement si la condition s'applique. Facultatif : au besoin.

| Propriété | Classe | Rôle |
| --- | --- | --- |
| `metadata_version` | obligatoire | version du schéma (entier) |
| `title` | obligatoire | titre explicite |
| `type` | obligatoire | nature (§4) |
| `description` | obligatoire | responsabilité du document, une phrase |
| `status` | obligatoire | état (§5) |
| `created` | obligatoire | date de création |
| `updated` | obligatoire | dernière modification significative |
| `version` | recommandé | version du document (§6) |
| `updated_from` | recommandé | sources de la dernière mise à jour (§6) |
| `scope` | conditionnel | conventions, règles, instructions (§7) |
| `extends` | conditionnel | conventions dont le document hérite (§7) |
| `depends_on` | facultatif | dépendances documentaires (§7) |
| `summary`, `tags` | facultatif | synthèse, mots-clés |

## 4. Valeurs de `type`

`convention`, `standard`, `guide`, `specification`, `decision`, `plan`, `report`, `reference`, `template`, `index`, `data`, `skill` (procédure destinée à un agent), `agent` (agent spécialisé). Une convention spécialisée peut ajouter des types documentés.

## 5. Valeurs de `status`

- `draft` : en rédaction, pas une règle validée.
- `review` : proposition en cours de vérification.
- `approved` : utilisable dans son périmètre.
- `deprecated` : chercher une alternative.
- `archived` : usage historique seulement.

Ne jamais supprimer automatiquement un document `deprecated` ou `archived`.

## 6. Version et dates

- `version` : SemVer `MAJOR.MINOR.PATCH`, celle du document, jamais celle du logiciel décrit.
- `created` ne change jamais.
- `updated` change à chaque modification significative, pas pour une consultation.
- `updated_from` : sources réellement utilisées (chemin, URL), remplacées à chaque mise à jour. Omise sans source.

## 7. Périmètre et relations

- `scope` : `level` (`universal`, `domain`, `project`) et `targets` (au moins une valeur). Ne pas revendiquer plus que le périmètre réel.
- `extends` : héritage normatif. `depends_on` : dépendance documentaire réellement utile.
- Chemins relatifs à la racine du projet, vers des fichiers qui existent.

## 8. Autres formats

- Code : commentaires natifs du langage, pas de front matter.
- Configuration et JSON : pas de métadonnées artificielles, ne pas casser le schéma d'un outil.
- Fichiers binaires : fichier associé seulement si nécessaire.
- Format imposé par un outil (agents, règles) : garder les champs de l'outil ; ajouter les propriétés du socle quand l'outil les ignore.

## 9. README de dossier carrefour

Un dossier carrefour est la racine du projet, ou un dossier qui regroupe plusieurs fonctionnalités ou qui en porte une entière. L'orchestrateur propose un README quand un dossier le devient.

- Lecture : avant de travailler dans un dossier, lire le README le plus proche (dossier courant, sinon parent). Son en-tête suffit souvent ; le lire en entier si c'est nécessaire ou en cas de doute.
- En-tête réduit : `metadata_version`, `title`, `type: index`, `description`, `summary` (obligatoire ici : ce qu'il faut savoir sans lire le reste), `version`, `status`, `created`, `updated`.
- Corps, dans l'ordre : (1) à quoi sert le dossier et où aller selon l'intention, (2) état actuel : ce qui marche, ce qui manque, (3) passe ici : les fonctionnalités, en clair, sans lien vers les notes, (4) évolution : quelques lignes datées, (5) ce qu'il ne faut pas y faire. Section vide omise.
- Longueur : environ 60 lignes au plus. Au-delà, résumer, et le détail repart dans les notes.
- Pas de liste de fichiers : elle se périme.
- Un README se lit seul, sans dépendre de la mémoire : il ne cite pas les notes. L'exception d'un README qui est un index reste valable (dernier point).
- Ne jamais remplacer un README existant ; proposer une adaptation à part.
- Pas de README pour un dossier qui n'est pas un carrefour.
- À jour : à la fin d'un plan, un worker met à jour les README des dossiers touchés (`PROCESS.md` §2).
- Exception : un README qui catalogue des documents est un index, sa liste est son contenu.

## 10. Règles pour les agents

- Lecture progressive : métadonnées, puis sections utiles, le document entier seulement si nécessaire.
- Préserver les propriétés valides ; modifier seulement les propriétés concernées.
- Modification du contenu : vérifier `description`, `summary`, `status`, `version`, `updated`.
- Ne jamais inventer une valeur ni une source ; signaler ce qui manque.

## 11. Héritage

Trois niveaux : universel, domaine, projet. Une règle locale ne contredit pas une règle parente en silence.
