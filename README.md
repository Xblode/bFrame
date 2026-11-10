---
titre: bFrame
description: Ce qu'est bFrame, où sont les choses, comment l'installer et le modifier.
maj: 2026-11-10
---

# bFrame

Ma façon de travailler avec Claude Code, la même sur tous mes projets. bFrame s'installe une fois sur le compte : dans chaque projet, un orchestrateur discute avec moi, tient la mémoire du projet et fait faire le travail par des workers.

But : reprendre un projet après trois semaines sans tout relire.

## Ce qu'il fait

- **Il discute et contredit.** L'orchestrateur aide à décider, propose des méthodes, et dit ce qui lui paraît fragile.
- **Il tient la mémoire du projet.** Cinq boîtes dans le dossier `.bframe/` du projet, suivies par Git :

| Boîte | Ce qu'elle contient |
| --- | --- |
| `PROJET.md` | Le cap : pourquoi, pour qui, le rêve, le minimum utile |
| `ETAT.md` | Où on en est, sujet par sujet. Lue à chaque reprise |
| `DECISIONS.md` | Ce qui a été décidé, avec la date et la raison |
| `IDEES.md` | Les idées, rangées par sujet |
| `TACHES.md` | Maintenant, Ensuite, Plus tard, Fait |

- **Il délègue.** Trois workers : un pour le développement, un pour les petites tâches, un pour chercher sur le web.
- **Il sait deux gestes.** `onboarding` pose les cinq boîtes dans un projet ; `interview` aide à creuser un sujet par questions.

## Où sont les choses

| Chemin | Rôle |
| --- | --- |
| `compte/` | La source de bFrame. Tout changement se fait ici |
| `compte/CLAUDE.md` | Mes règles, valables partout |
| `compte/agents/` | L'orchestrateur, les trois workers, l'orchestrateur Fable |
| `compte/skills/` | `onboarding` et ses modèles de boîtes, `interview` |
| `compte/reglages.json` | Les réglages à fusionner dans ceux du compte |
| `archive/` | Tout l'ancien bFrame et l'histoire de la refonte. Hors Git |

## Installer

Le compte Claude Code est le dossier `C:\Users\<moi>\.claude\`.

1. Copier `compte/CLAUDE.md`, `compte/agents/` et `compte/skills/` dans ce dossier, aux mêmes endroits.
2. Fusionner `compte/reglages.json` dans `settings.json` du compte, sans rien retirer de ce qui y est déjà.
3. Ouvrir une nouvelle conversation dans un projet : l'orchestrateur répond et propose l'onboarding.

Le plus simple : ouvrir une conversation dans ce dossier et demander « installe bFrame sur mon compte ».

## Modifier bFrame

La source (`compte/`) et le compte sont deux copies. Deux gestes, toujours dans cet ordre :

1. **Modifier la source**, dans `compte/`. Ouvrir une conversation dans ce dossier et dire ce qu'il faut changer.
2. **Recopier sur le compte**, avec mon accord. Le changement vaut pour tous les projets à la conversation suivante.

Ne jamais modifier un fichier directement sur le compte : la prochaine recopie l'écraserait.

## Lancer l'orchestrateur Fable

Pour une grosse mission. Dans le projet concerné, créer `.claude/settings.local.json` avec `{ "agent": "orchestrator-fable" }`, ouvrir une nouvelle conversation, puis retirer ce fichier à la fin.

## Désinstaller

Retirer du compte les fichiers copiés à l'étape 1, puis les lignes ajoutées à `settings.json` (`agent`, et les entrées de `permissions` listées dans `compte/reglages.json`).

## Limites connues

- La lecture des fichiers `.env` est interdite à Claude, mais une commande du terminal peut encore les afficher.
- Pas encore là, par choix : tableau de bord, modules par type de projet, agent qui note tout seul.
