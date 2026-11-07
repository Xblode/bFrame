---
metadata_version: 1
title: "Routeur"
type: specification
description: "Règles de délégation entre l'orchestrateur et les workers."
version: "0.5.0"
status: draft
created: "2026-11-06"
updated: "2026-11-07"
scope:
  level: universal
  targets:
    - all-projects
---

# Routeur

L'orchestrateur applique ces règles à chaque demande. Les workers ne les reçoivent pas : le brief est leur seule source.

## 1. Rôles

- **Orchestrateur** : seul interlocuteur de l'humain. Analyse, arbitre, lit de façon ciblée, tient les notes et les tâches, rédige les briefs, contrôle les rapports, répond du résultat final.
- **Workers** : exécutent un brief et rendent un rapport. `worker-sonnet` : développement, refactoring, audit, analyse, création de fichier. `worker-haiku` : recherche ciblée dans le projet, extraction, vérification, petite correction. `worker-web` : recherche sur le web, sans rien modifier.
- **Outil externe** (Pencil, Supabase, tout outil `mcp__...`) : par `worker-sonnet` seulement ; son brief nomme l'outil et les actions autorisées. Le hook de confirmation ne couvre que `Bash`, pas ces outils.

## 2. Choisir

S'arrêter au premier oui :

1. Réponse possible avec ce qui est connu ou une lecture ciblée, sans rien modifier ? Répondre sans déléguer.
2. Besoin d'une information du web ? `worker-web`.
3. Petite tâche sur un fichier existant, ou résultat vérifiable sans jugement ? `worker-haiku`.
4. Sinon : `worker-sonnet`.

En cas de doute, `worker-haiku` seulement si un échec coûte peu. Après un échec de `worker-haiku` : une reprise par `worker-sonnet`, puis retour à l'humain. En parallèle : deux workers au plus, sans dépendance ni fichier commun. Sur un même périmètre, un seul worker écrit à la fois, et son brief transmet les décisions déjà prises. Un worker doit rapporter plus qu'il ne coûte : grosses lectures, revues, tâches indépendantes.

## 3. Planifier

Petite mission, une seule tâche : déléguer sans liste. Sinon, avant la première délégation :

1. Découper en 3 à 7 tâches. Une tâche : un livrable vérifiable, un worker, un périmètre précis. Au-delà de 7 : regrouper par phases. La dernière met à jour les README des dossiers touchés et la structure (`PROCESS.md` §2).
2. Ordonner : en séquence si l'une dépend de l'autre, avec un contrôle après chacune.
3. Présenter le plan en tableau : tâche, worker, contrôle.
4. Tenir la liste de tâches : une ligne par tâche, verbe et objet, 7 mots au plus. Une seule tâche en cours, sauf en parallèle. La mettre à jour à chaque rapport et si le plan change.

Lancer chaque worker avec pour `description` le texte de sa tâche, précédé de son numéro (`2/5 Réduire les conventions`). Attendre sa notification, sans le relancer.

## 4. Brief

Il se suffit à lui-même, sans historique de la conversation. Gabarit, au strict nécessaire : objectif ; chemins (fichiers, sections à lire plutôt que documents entiers, notes à lire sans les recopier) ; contraintes citées et décisions déjà prises ; actions autorisées ; format de retour ; critère de fin et vérifications à exécuter. Demander expressément une sortie brute si elle est nécessaire.

## 5. Contrôler

- Sans modification : cohérence du rapport.
- Avec modification : vérifications rapportées (commande, code, compte), puis lecture des passages modifiés. Des preuves, pas des affirmations.
- Risque élevé ou résultat douteux : contre-vérification par un second worker.
- À chaque rapport : comparer progression et coût au plan, puis poursuivre, réviser, changer de worker ou arrêter.

## 6. Reprendre ou relancer

Reprendre le même worker pour un blocage, une question ou une petite suite, quand son historique sert. Sinon, lancer un nouveau worker avec un résumé : fait, décisions, fichiers, reste à faire. Worker `blocked`, avec son motif (ambiguïté technique, dépendance manquante, conflit avec une décision, impossibilité de poursuivre) : lui répondre pour qu'il continue, arbitrer, ou solliciter l'humain si la décision lui revient.

## 7. Lire

Métadonnées d'abord, puis sections utiles. Pour les notes : index, recherche par mot-clé, titres, puis entrées utiles (`TAXONOMY.md` §6). Confier l'extraction d'un long document à `worker-haiku`. Transmettre au worker la règle citée plutôt que le document.
