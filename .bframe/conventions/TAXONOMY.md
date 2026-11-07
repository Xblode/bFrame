---
metadata_version: 1
title: "Convention de taxonomie"
type: convention
description: "Règles du cycle de vie des idées : statuts, format et tenue des notes, recherche, validation et plans."
version: "0.6.0"
status: draft
created: "2026-11-07"
updated: "2026-11-07"
scope:
  level: universal
  targets:
    - all-projects
---

# Convention de taxonomie

## 1. Cycle de vie

Une idée passe par trois étapes.

| Étape | Contenu | Emplacement |
| --- | --- | --- |
| NOTES | En discussion | `.bframe/memory/notes/` |
| TASKS | Validé, à faire | `.bframe/memory/tasks/` |
| README | Fait | README du carrefour le plus proche |

## 2. Statuts d'une note

| Statut | Sens | Suite |
| --- | --- | --- |
| `idée` | Dite, pas encore tranchée | Statut de départ |
| `validée` | Acceptée explicitement par l'humain | Sa tâche part dans `.bframe/memory/tasks/` |
| `faite` | Réalisée, décrite dans le README du carrefour le plus proche | Reste en note |
| `plus tard` | Bonne, mais hors périmètre du moment | Reste en note |
| `écartée` | Abandonnée | Reste en note, avec la raison |

Une note passe en `validée` seulement sur l'accord clair de l'humain : l'orchestrateur la marque alors lui-même, sans repasser par une question, et le lui signale. Il ne le fait jamais de son seul jugement.

## 3. Fichiers

- Un seul fichier de notes par fonctionnalité : `.bframe/memory/notes/<fonctionnalite>.md`, en `kebab-case`.
- `.bframe/memory/notes/README.md` est l'index : une ligne par fichier, avec ses mots-clés.
- En-tête d'une note : `metadata_version`, `title`, `type: note`, `description`, `tags` (mots-clés et synonymes, sur une seule ligne), `status: draft`, `created`, `updated`. Le type `note` est propre à cette convention.
- Un README de dossier ne cite pas les notes : il se lit seul (`METADATA.md` §9).

## 4. Entrée d'une note

```markdown
## [idée] Titre précis, 2026-11-07

Ce qu'il faut pour réexpliquer l'idée sans la conversation : le contenu, le contexte, la raison.

« Mots de l'humain, seulement s'ils portent une nuance. »
```

- Le statut et le titre tiennent sur la ligne de titre : une recherche sur `^## ` donne la liste des entrées sans lire le reste.
- Un titre précis, avec des noms concrets.
- Une entrée, une idée. Un message qui contient plusieurs idées donne plusieurs entrées.
- Aussi court que possible, assez complet pour se comprendre seul.

## 5. Noter à chaque message

L'orchestrateur note lui-même, avant de répondre.

- À noter : une idée, une décision, une demande, une contrainte, une question ouverte, une préférence.
- À ne pas noter : un simple accord, un remerciement, une répétition.
- Une précision complète l'entrée existante au lieu d'en créer une nouvelle.
- Une seule écriture par fichier et par message : regrouper les entrées.
- Pour seulement ajouter une entrée, ne pas relire toute la note : lire sa fin suffit.

## 6. Retrouver

Dans cet ordre, en s'arrêtant dès que la réponse est là :

1. L'index.
2. Une recherche par mot-clé dans `.bframe/memory/notes/`.
3. Les titres d'une note (`^## `).
4. Les seules entrées utiles.
5. La note entière, seulement si c'est nécessaire ou en cas de doute.

L'orchestrateur peut proposer d'aller voir les notes liées au sujet de la conversation.

## 7. Valider

- Le contenu des notes se valide par petits lots avec `AskUserQuestion`, quatre éléments au plus par question. Ne jamais demander à l'humain de lire les notes.
- Une réponse vaut pour ce qui vient d'être présenté.
- Une entrée validée passe en `validée`, et sa tâche s'ajoute dans `.bframe/memory/tasks/`, dans sa tâche maître et sa fonctionnalité.

## 8. Plans

L'orchestrateur propose un plan quand une note dépasse environ 200 lignes, ou quand plusieurs idées validées forment une fonctionnalité.

- La proposition se fait avec `AskUserQuestion` et deux réponses : « Lancer le plan pour ... » et « Ne pas lancer ».
- L'orchestrateur ne lance jamais un plan seul.
- Le seuil de 200 lignes est un repère de départ, à ajuster à l'usage.

## 9. Tâches

Seul ce qui est validé entre dans les tâches, et on ne lance que cela.

- `.bframe/memory/tasks/README.md` est l'index : le sujet en cours et l'état de chaque tâche maître, environ 50 lignes au plus, en-tête compris. C'est le seul fichier de tâches lu à la reprise.
- Un fichier par tâche maître : `.bframe/memory/tasks/<tache-maitre>.md`, en `kebab-case`. Lire seulement la section utile : les titres `^### ` donnent les fonctionnalités.
- Rangement : tâche maître (le fichier), fonctionnalité (`###`), tâche, sous-tâche, sous-sous-tâche.
- Format d'une ligne : `- [ ] S-12 Texte de la tâche`. `[x]` pour une tâche faite.
- Identifiant : la lettre de la tâche maître et un numéro, hiérarchique (`S-12`, `S-12.1`, `S-12.1.1`). Il ne change jamais et ne se réutilise jamais, même après l'archivage.
- L'orchestrateur coche une tâche sans réécrire son texte. Changer un texte demande l'accord de l'humain.
- À la fin d'un plan, les tâches faites partent dans `.bframe/memory/tasks/archive.md`, et l'index se met à jour. Une tâche reste en place tant qu'une de ses sous-tâches est ouverte.
- L'archive n'est jamais lue à la reprise : on y cherche par identifiant ou par mot-clé.
