# Installer bFrame

Prérequis : Windows, PowerShell, et Python pour les hooks. Sans Python, l'installation avertit.

**Installer**, dans le dossier du projet (version figée `v0.1.1` dans l'adresse) :

```powershell
irm https://raw.githubusercontent.com/Xblode/bFrame/v0.1.1/install.ps1 | iex
```

**Voir sans rien écrire :**

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Xblode/bFrame/v0.1.1/install.ps1))) -DryRun
```

**Mettre à jour :**

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Xblode/bFrame/main/install.ps1))) -Update
```

Sans `-Version vX.Y.Z`, la mise à jour vise la version écrite dans le script (`v0.1.1` pour l'instant), pas forcément la dernière publiée.

**Retirer :**

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Xblode/bFrame/main/install.ps1))) -Uninstall
```

`.bframe/memory/` et `.bframe/backup/` sont gardés.

## Ce que fait l'installation

1. Aperçu de ce qui va changer, puis accord demandé avant toute écriture. Copie du moteur de bFrame (agents, hooks, règles, skills, conventions, routeur).
2. Création de `.bframe/memory/` avec ses dossiers et README de départ, sans contenu de projet.
3. Un `CLAUDE.md` existant passe sous la section `# Projet`.
4. Fichiers remplacés sauvegardés dans `.bframe/backup/` (avec un `LISEZMOI.txt`). Si un de vos fichiers du moteur (agent, hook, règle, skill) ou votre `agent` de démarrage existe déjà et diffère, l'aperçu le dit et un **accord de remplacement distinct** est demandé ; `-Yes` ne le donne jamais. Refus : rien n'est écrit, code de sortie non nul.
5. La mémoire (`.bframe/memory/`) n'est jamais modifiée.
6. Un bloc `# >>> bFrame` est ajouté au `.gitignore` du projet (créé au besoin), après aperçu et accord : caches, sauvegardes, état local et `.bframe/install.json`. Ni la mémoire ni les `.env` : ils suivent Git comme le reste du projet. `-Update` rafraîchit ce bloc, `-Uninstall` le retire sans toucher au reste.

Un rapport `.bframe/install-report.md` (non versionné, sans secret) résume ce qui a été trouvé et remplacé. Si l'installation est incomplète, le script écrit `INSTALLATION INCOMPLÈTE` et sort en erreur.

**Après l'installation :** relancez Claude Code, puis demandez l'onboarding : il lira ce rapport.

**Conseil :** ces commandes exécutent un script téléchargé. Vous pouvez d'abord ouvrir `https://raw.githubusercontent.com/Xblode/bFrame/v0.1.1/install.ps1` et le lire.
