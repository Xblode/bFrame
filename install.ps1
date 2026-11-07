# bFrame - installe, met a jour ou retire bFrame dans le dossier courant.
# Sans fichier :  irm https://raw.githubusercontent.com/Xblode/bFrame/main/install.ps1 | iex
# Avec options :  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/Xblode/bFrame/main/install.ps1))) -Update
# Options : -Version vX.Y.Z  -Update  -Uninstall  -DryRun  -SourcePath <dossier local>  -Yes (tests)
# Regle de publication : la constante $Version ci-dessous est changee a chaque publication,
# puis un tag Git du meme nom est cree. Sans -Version, -Update vise cette constante (pas d'API).
# Rien n'est ecrit sans accord. Aucune donnee n'est envoyee. Fichier ASCII : les accents sont codes en \uXXXX.

param(
    [string]$Version = 'v0.1.0',   # version figee (tag GitHub) a installer
    [switch]$Update,
    [switch]$Uninstall,
    [switch]$DryRun,
    [string]$SourcePath,
    [switch]$Yes
)

$exitCode = @(& {
    param($Version, $Update, $Uninstall, $DryRun, $SourcePath, $Yes)
    $ErrorActionPreference = 'Stop'

    # ---------- Reglages ----------
    $RepoUrl = 'https://github.com/Xblode/bFrame'
    # Liste explicite de ce que bFrame installe (un dossier = tout son contenu).
    # Cas particuliers traites a part : CLAUDE.md et .claude/settings.json.
    $Engine = @('.claude/agents', '.claude/hooks', '.claude/rules', '.claude/skills', '.claude/README.md',
                '.bframe/ROUTER.md', '.bframe/README.md', '.bframe/conventions')
    $MemoryDirs = @('notes', 'reference', 'tasks')
    $MemoryModels = @('README.md', 'notes/README.md', 'tasks/README.md')
    $ReferenceDocs = @('VISION.md', 'CADRAGE.md', 'STRUCTURE.md')
    $Target = (Get-Location).ProviderPath.TrimEnd('\')
    $enc = New-Object System.Text.UTF8Encoding($false)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bk = @{ Dir = $null }
    $state = @{ Temp = $null; Wrote = $false }

    # ---------- Outils ----------
    function T([string]$s) {
        [regex]::Replace($s, '\\u([0-9a-fA-F]{4})', { param($m) [string][char][Convert]::ToInt32($m.Groups[1].Value, 16) })
    }
    function Say([string]$m = '', [string]$c = 'Gray') { Write-Host (T $m) -ForegroundColor $c }
    function Dest([string]$rel) { Join-Path $Target ($rel -replace '/', '\') }
    function EnsureDir([string]$d) { if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }
    function HashBytes([byte[]]$b) { ([BitConverter]::ToString($sha.ComputeHash($b)) -replace '-', '').ToLower() }
    function HashFile([string]$p) { HashBytes ([IO.File]::ReadAllBytes($p)) }
    function HashText([string]$t) { HashBytes ($enc.GetBytes($t)) }
    function ReadText([string]$p) {
        $b = [IO.File]::ReadAllBytes($p)
        try { $t = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($b) }
        catch {
            # UTF-8 invalide : relecture en encodage Windows (ANSI), pour garder le contenu exact.
            try { $ansi = [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage) }
            catch { $ansi = [Text.Encoding]::GetEncoding(1252) }
            $t = $ansi.GetString($b)
        }
        return $t.TrimStart([char]0xFEFF)
    }
    function WriteText([string]$p, [string]$t) { EnsureDir (Split-Path $p); [IO.File]::WriteAllBytes($p, $enc.GetBytes($t)) }
    function CopyFile([string]$from, [string]$to) { EnsureDir (Split-Path $to); [IO.File]::Copy($from, $to, $true) }

    function Ask([string]$q, [bool]$general) {
        if ($Yes) { return $general }   # -Yes ne force jamais un ecrasement
        try { $a = Read-Host (T $q) } catch { return $false }
        return ($a -match '^\s*(o|oui|y|yes)\s*$')
    }

    function Backup([string]$rel) {
        if (-not $bk.Dir) { $bk.Dir = Join-Path $Target ('.bframe\backup\' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
        CopyFile (Dest $rel) (Join-Path $bk.Dir ($rel -replace '/', '\'))
    }

    function CleanDirs([string]$rel) {
        $d = Split-Path (Dest $rel)
        while ($d.Length -gt $Target.Length -and $d.StartsWith($Target) -and (Test-Path -LiteralPath $d) -and -not (Get-ChildItem -LiteralPath $d -Force | Select-Object -First 1)) {
            Remove-Item -LiteralPath $d
            $d = Split-Path $d
        }
    }

    # ---------- JSON (ecriture propre, indentation 2) ----------
    function JsonStr([string]$s) {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append('"')
        foreach ($ch in $s.ToCharArray()) {
            $n = [int]$ch
            if ($n -eq 34) { [void]$sb.Append('\"') }
            elseif ($n -eq 92) { [void]$sb.Append('\\') }
            elseif ($n -eq 10) { [void]$sb.Append('\n') }
            elseif ($n -eq 13) { [void]$sb.Append('\r') }
            elseif ($n -eq 9) { [void]$sb.Append('\t') }
            elseif ($n -lt 32) { [void]$sb.Append(('\u{0:x4}' -f $n)) }
            else { [void]$sb.Append($ch) }
        }
        [void]$sb.Append('"')
        return $sb.ToString()
    }
    function ToJson($v, [string]$ind = '') {
        if ($null -eq $v) { return 'null' }
        if ($v -is [string]) { return (JsonStr $v) }
        if ($v -is [bool]) { if ($v) { return 'true' } else { return 'false' } }
        $in2 = $ind + '  '
        $names = New-Object System.Collections.ArrayList
        $vals = New-Object System.Collections.ArrayList
        if ($v -is [System.Collections.IDictionary]) {
            foreach ($k in $v.Keys) { [void]$names.Add([string]$k); [void]$vals.Add($v[$k]) }
        } elseif ($v -is [System.Management.Automation.PSCustomObject]) {
            foreach ($p in $v.PSObject.Properties) { [void]$names.Add($p.Name); [void]$vals.Add($p.Value) }
        } elseif ($v -is [System.Collections.IEnumerable]) {
            $items = @($v)
            if ($items.Count -eq 0) { return '[]' }
            $lines = New-Object System.Collections.ArrayList
            foreach ($i in $items) { [void]$lines.Add($in2 + (ToJson $i $in2)) }
            return "[`n" + ($lines -join ",`n") + "`n" + $ind + ']'
        } else {
            return [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0}', $v)
        }
        if ($names.Count -eq 0) { return '{}' }
        $lines = New-Object System.Collections.ArrayList
        for ($i = 0; $i -lt $names.Count; $i++) { [void]$lines.Add($in2 + (JsonStr $names[$i]) + ': ' + (ToJson $vals[$i] $in2)) }
        return "{`n" + ($lines -join ",`n") + "`n" + $ind + '}'
    }
    function IsObj($x) { return ($x -is [System.Management.Automation.PSCustomObject]) }

    # Ajoute "agent" et les hooks de bFrame dans $cur sans rien retirer.
    function MergeSettings($cur, $src) {
        $r = @{ Error = $null; Agent = $null; Hooks = @() }
        $ap = $cur.PSObject.Properties['agent']
        if ($src.agent -and $ap -and ([string]$ap.Value -ne [string]$src.agent)) {
            $r.Error = 'la cl\u00e9 "agent" vaut d\u00e9j\u00e0 "' + $ap.Value + '" (bFrame veut "' + $src.agent + '")'
            return $r
        }
        $hp = $cur.PSObject.Properties['hooks']
        if ($hp -and -not (IsObj $hp.Value)) { $r.Error = 'la cl\u00e9 "hooks" n''a pas la forme attendue'; return $r }
        if ($hp) {
            foreach ($ev in $src.hooks.PSObject.Properties) {
                $ex = $hp.Value.PSObject.Properties[$ev.Name]
                if ($ex -and ($ex.Value -isnot [array])) { $r.Error = 'la liste de hooks "' + $ev.Name + '" n''a pas la forme attendue'; return $r }
            }
        }
        if ($src.agent -and -not $ap) {
            Add-Member -InputObject $cur -NotePropertyName agent -NotePropertyValue $src.agent
            $r.Agent = [string]$src.agent
        }
        if ($src.hooks) {
            if (-not $hp) {
                Add-Member -InputObject $cur -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{})
            }
            $ch = $cur.hooks
            foreach ($ev in $src.hooks.PSObject.Properties) {
                foreach ($grp in @($ev.Value)) {
                    $cmds = @($grp.hooks | ForEach-Object { $_.command })
                    $ex = $ch.PSObject.Properties[$ev.Name]
                    $present = $false
                    if ($ex) {
                        foreach ($eg in @($ex.Value)) { foreach ($h in @($eg.hooks)) { if ($cmds -contains $h.command) { $present = $true } } }
                    }
                    if ($present) { continue }
                    if ($ex) { $ex.Value = @($ex.Value) + @($grp) }
                    else { Add-Member -InputObject $ch -NotePropertyName $ev.Name -NotePropertyValue @($grp) }
                    foreach ($c in $cmds) { $r.Hooks += ($ev.Name + '|' + $c) }
                }
            }
        }
        return $r
    }

    # Retire de $cur ce que le registre dit avoir ajoute. Renvoie la liste des retraits.
    function UnmergeSettings($cur, $rs) {
        $out = @()
        $added = @($rs.hooks)
        $ap = $cur.PSObject.Properties['agent']
        if ($rs.agent -and $ap -and ([string]$ap.Value -eq [string]$rs.agent)) {
            $cur.PSObject.Properties.Remove('agent'); $out += ('agent : ' + $rs.agent)
        }
        $hp = $cur.PSObject.Properties['hooks']
        if ($hp -and (IsObj $hp.Value)) {
            foreach ($evp in @($hp.Value.PSObject.Properties)) {
                $ev = $evp.Name
                if ($evp.Value -isnot [array]) { continue }
                $keep = @(); $changed = $false
                foreach ($grp in @($evp.Value)) {
                    if (-not $grp.hooks) { $keep += $grp; continue }
                    $hs = @($grp.hooks)
                    $left = @($hs | Where-Object { $added -notcontains ($ev + '|' + $_.command) })
                    if ($left.Count -eq $hs.Count) { $keep += $grp; continue }
                    $changed = $true
                    foreach ($h in $hs) { if ($added -contains ($ev + '|' + $h.command)) { $out += ($ev + ' : ' + $h.command) } }
                    if ($left.Count -gt 0) { $grp.hooks = $left; $keep += $grp }
                }
                if ($keep.Count -eq 0) { $hp.Value.PSObject.Properties.Remove($ev) }
                elseif ($changed) { $evp.Value = $keep }
            }
            if (@($hp.Value.PSObject.Properties).Count -eq 0) { $cur.PSObject.Properties.Remove('hooks') }
        }
        return $out
    }

    # ---------- CLAUDE.md : partie bFrame (avant "# Projet") et partie projet ----------
    function SplitClaude([string]$t) {
        $m = [regex]::Match($t, '(?m)^# Projet[ \t]*\r?$')
        if (-not $m.Success) { return @{ Found = $false; Engine = $t; Project = '' } }
        return @{ Found = $true; Engine = $t.Substring(0, $m.Index); Project = $t.Substring($m.Index) }
    }
    function ProjectIsEmpty([string]$project) {
        $body = ($project -replace '^# Projet[ \t]*\r?\n?', '')
        $body = [regex]::Replace($body, '(?s)<!--.*?-->', '')
        return ($body.Trim().Length -eq 0)
    }

    # ---------- Dossier de travail dangereux ----------
    # Renvoie $null (ok), ou 'refuse:<raison>' / 'confirme:<raison>'.
    function DangerReason([string]$path) {
        $sc = [StringComparison]::OrdinalIgnoreCase
        $p = $path.Replace('/', '\').TrimEnd('\')
        if ($p -eq '') { return 'refuse:racine d''un disque' }
        if ($p -match '^[A-Za-z]:$') { return 'refuse:racine d''un disque' }
        if ($path -match '^\\\\[^\\]+\\[^\\]+\\?$') { return 'refuse:racine d''un partage r\u00e9seau' }
        $sys = @($env:windir, $env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432, $env:ProgramData)
        foreach ($s in $sys) {
            if (-not $s) { continue }
            $s = $s.Replace('/', '\').TrimEnd('\')
            if ($p.Equals($s, $sc) -or $p.StartsWith($s + '\', $sc)) { return 'refuse:dossier syst\u00e8me (' + $s + ')' }
        }
        if ($env:USERPROFILE -and $p.Equals($env:USERPROFILE.Replace('/', '\').TrimEnd('\'), $sc)) { return 'confirme:dossier personnel' }
        return $null
    }

    # ---------- Chemins du registre ----------
    # Renvoie $null si le chemin relatif est acceptable, sinon la raison du refus.
    function BadRegPath([string]$raw) {
        $sc = [StringComparison]::OrdinalIgnoreCase
        $r = $raw.Replace('\', '/')
        if ($r.Trim() -eq '') { return 'chemin vide' }
        if ($r.StartsWith('/')) { return 'chemin absolu' }
        if ($r.Contains(':')) { return 'lettre de lecteur ou flux' }
        if ($r -match '[<>|"*?]') { return 'caract\u00e8re interdit' }
        foreach ($seg in $r.Split('/')) {
            if ($seg -eq '' -or $seg -eq '.' -or $seg -eq '..') { return 'segment interdit' }
            if ($seg -match '[. ]$') { return 'segment interdit' }
        }
        if ($r -match '(?i)^\.bframe/memory(/|$)') { return 'm\u00e9moire du projet' }
        $ok = $false
        foreach ($e in $Engine) { if ($r.Equals($e, $sc) -or $r.StartsWith($e + '/', $sc)) { $ok = $true } }
        if (-not $ok) { return 'hors de la liste du moteur' }
        $full = [IO.Path]::GetFullPath((Dest $r))
        if (-not $full.StartsWith($Target + '\', $sc)) { return 'sort du dossier du projet' }
        return $null
    }

    # ---------- Python ----------
    function PythonOk {
        try {
            $o = & python --version 2>&1 | Out-String
            return ($LASTEXITCODE -eq 0 -and $o -match 'Python \d')
        } catch { return $false }
    }

    # ---------- Source ----------
    function ListFiles([string]$root) {
        $list = New-Object System.Collections.ArrayList
        foreach ($e in $Engine) {
            $p = Join-Path $root ($e -replace '/', '\')
            if (Test-Path -LiteralPath $p -PathType Container) {
                foreach ($f in (Get-ChildItem -LiteralPath $p -Recurse -File)) {
                    $rel = $f.FullName.Substring($root.Length).TrimStart('\').Replace('\', '/')
                    if ($rel -notmatch '(^|/)__pycache__/' -and $rel -notmatch '\.pyc$') { [void]$list.Add($rel) }
                }
            } elseif (Test-Path -LiteralPath $p -PathType Leaf) {
                [void]$list.Add($e)
            } else {
                throw ('Le contenu de bFrame est incomplet : ' + $e + ' est introuvable.')
            }
        }
        return ($list | Sort-Object)
    }

    function GetSource {
        $res = @{ Root = $null }
        if ($SourcePath) {
            if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)) { throw ('Le dossier source n''existe pas : ' + $SourcePath) }
            $res.Root = (Resolve-Path -LiteralPath $SourcePath).ProviderPath.TrimEnd('\')
        } else {
            $url = $RepoUrl + '/archive/refs/tags/' + $Version + '.zip'
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ('bframe-' + [guid]::NewGuid().ToString('N'))
            $state.Temp = $tmp
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            $zip = Join-Path $tmp 'bframe.zip'
            $ProgressPreference = 'SilentlyContinue'
            try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
            Say ('T\u00e9l\u00e9chargement de bFrame ' + $Version + ' ...')
            try { Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing }
            catch {
                $code = 0
                try { $code = [int]$_.Exception.Response.StatusCode } catch { }
                if ($code -eq 404) { throw ('La version ' + $Version + ' n''existe pas (' + $url + '). V\u00e9rifiez la version : sans -Version, le script vise la version qui y est \u00e9crite, et un tag du m\u00eame nom doit exister.') }
                throw ('Le t\u00e9l\u00e9chargement a \u00e9chou\u00e9 (' + $url + '). V\u00e9rifiez la version et votre connexion Internet. D\u00e9tail : ' + $_.Exception.Message)
            }
            $head = [IO.File]::ReadAllBytes($zip) | Select-Object -First 2
            if ($head.Count -lt 2 -or $head[0] -ne 80 -or $head[1] -ne 75) { throw ('Version introuvable : ' + $Version + ' (le serveur n''a pas renvoy\u00e9 une archive). V\u00e9rifiez le num\u00e9ro de version.') }
            try { Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $tmp 'x') -Force }
            catch { throw 'L''archive t\u00e9l\u00e9charg\u00e9e est invalide ou illisible.' }
            $dirs = @(Get-ChildItem -LiteralPath (Join-Path $tmp 'x') -Directory)
            if ($dirs.Count -ne 1) { throw 'L''archive t\u00e9l\u00e9charg\u00e9e n''a pas la forme attendue.' }
            $res.Root = $dirs[0].FullName.TrimEnd('\')
        }
        foreach ($need in @('CLAUDE.md', '.claude/settings.json', '.bframe/ROUTER.md', '.bframe/template/memory/README.md', '.bframe/template/memory/notes/README.md', '.bframe/template/memory/tasks/README.md')) {
            if (-not (Test-Path -LiteralPath (Join-Path $res.Root ($need -replace '/', '\')) -PathType Leaf)) {
                throw ('Ce contenu n''est pas bFrame (fichier absent : ' + $need + '). Rien n''a \u00e9t\u00e9 \u00e9crit.')
            }
        }
        return $res
    }

    # ---------- Programme ----------
    try {
        if ($Version -notmatch '^v?\d+(\.\d+){1,3}([-+][0-9A-Za-z.\-]+)?$') { throw ('Version invalide : ' + $Version + ' (exemple : v0.1.0).') }
        if ($Update -and $Uninstall) { throw 'Choisissez -Update ou -Uninstall, pas les deux.' }

        # Refus dans le depot source de bFrame
        $isSource = Test-Path -LiteralPath (Dest '.bframe/template/memory') -PathType Container
        if (-not $isSource -and $SourcePath -and (Test-Path -LiteralPath $SourcePath)) {
            $isSource = ((Resolve-Path -LiteralPath $SourcePath).ProviderPath.TrimEnd('\') -ieq $Target)
        }
        if ($isSource) { throw 'Ce dossier est le d\u00e9p\u00f4t source de bFrame : installation refus\u00e9e. Lancez la commande dans le dossier de votre projet.' }

        # Registre
        $regPath = Dest '.bframe/install.json'
        $reg = $null
        if (Test-Path -LiteralPath $regPath -PathType Leaf) {
            try { $reg = (ReadText $regPath) | ConvertFrom-Json } catch { throw 'Le fichier .bframe/install.json est illisible. Rien n''a \u00e9t\u00e9 \u00e9crit.' }
            if (-not $reg -or -not $reg.files) { throw 'Le fichier .bframe/install.json est incomplet. Rien n''a \u00e9t\u00e9 \u00e9crit.' }
        }
        $regFiles = @{}
        if ($reg) { foreach ($p in $reg.files.PSObject.Properties) {
            $bad = BadRegPath $p.Name
            if ($bad) { throw ('Le fichier .bframe/install.json contient un chemin refus\u00e9 : "' + $p.Name + '" (' + $bad + '). Arr\u00eat : rien n''a \u00e9t\u00e9 \u00e9crit ni supprim\u00e9. Corrigez ou supprimez ce fichier de suivi \u00e0 la main.') }
            $regFiles[$p.Name.Replace('\', '/')] = [string]$p.Value
        } }

        $mode = 'install'
        if ($Uninstall) { $mode = 'uninstall' } elseif ($Update) { $mode = 'update' }
        if ($mode -eq 'update' -and -not $reg) { throw 'bFrame n''est pas install\u00e9 ici (pas de .bframe/install.json). Lancez la commande sans -Update.' }
        if ($mode -eq 'uninstall' -and -not $reg) { throw 'bFrame n''est pas install\u00e9 ici (pas de .bframe/install.json) : rien \u00e0 retirer.' }
        if ($mode -eq 'install' -and $reg -and ([string]$reg.version -ne $Version)) {
            Say ('bFrame ' + $reg.version + ' est d\u00e9j\u00e0 install\u00e9 ici. Pour passer \u00e0 ' + $Version + ', lancez la commande avec -Update.') 'Yellow'
            return 0
        }

        Say ''
        Say ('Dossier du projet : ' + $Target) 'Cyan'
        $danger = DangerReason $Target
        if ($danger) {
            $kind = $danger.Substring(0, $danger.IndexOf(':')); $why = $danger.Substring($danger.IndexOf(':') + 1)
            Say ('Attention : ce dossier est un ' + $why + '.') 'Red'
            if ($kind -eq 'refuse') { throw ('Dossier refus\u00e9 (' + $why + '). Placez-vous dans le dossier de votre projet puis relancez la commande.') }
            if (-not $DryRun) {
                if ($Yes) { throw 'Dossier personnel : confirmation renforc\u00e9e impossible avec -Yes. Placez-vous dans le dossier de votre projet.' }
                $leaf = Split-Path $Target -Leaf
                $a = ''
                try { $a = Read-Host (T ('Pour confirmer, retapez le nom du dossier (' + $leaf + ')')) } catch { $a = '' }
                if ($a.Trim() -ne $leaf) { throw 'Confirmation non donn\u00e9e : arr\u00eat, rien n''a \u00e9t\u00e9 \u00e9crit.' }
            }
        }

        # =================== RETRAIT ===================
        if ($mode -eq 'uninstall') {
            Say ('Retrait de bFrame ' + $reg.version) 'Cyan'
            $toRemove = @(); $modified = @(); $gone = @()
            foreach ($rel in ($regFiles.Keys | Sort-Object)) {
                $d = Dest $rel
                if (-not (Test-Path -LiteralPath $d -PathType Leaf)) { $gone += $rel }
                elseif ((HashFile $d) -eq $regFiles[$rel]) { $toRemove += $rel }
                else { $modified += $rel }
            }
            # settings.json
            $setPlan = @{ Mode = 'none'; Items = @(); Obj = $null; Delete = $false; Note = '' }
            $sd = Dest '.claude/settings.json'
            if ($reg.settings -and (Test-Path -LiteralPath $sd -PathType Leaf)) {
                try { $cur = (ReadText $sd) | ConvertFrom-Json } catch { $cur = $null }
                if (-not (IsObj $cur)) { $setPlan.Note = '.claude/settings.json n''est pas un JSON valide : laiss\u00e9 tel quel, retirez-y \u00e0 la main "agent" et les hooks de bFrame.' }
                else {
                    $items = @(UnmergeSettings $cur $reg.settings)
                    if ($items.Count -gt 0) {
                        $setPlan.Mode = 'write'; $setPlan.Items = $items; $setPlan.Obj = $cur
                        if (@($cur.PSObject.Properties).Count -eq 0 -and $reg.settings.created) { $setPlan.Delete = $true }
                    }
                }
            }
            # CLAUDE.md
            $clPlan = @{ Mode = 'none'; Text = ''; Note = '' }
            $cd = Dest 'CLAUDE.md'
            if ($reg.claude_md -and (Test-Path -LiteralPath $cd -PathType Leaf)) {
                $sp = SplitClaude (ReadText $cd)
                if (-not $sp.Found) { $clPlan.Note = 'CLAUDE.md n''a plus de section "# Projet" : laiss\u00e9 tel quel.' }
                elseif ($reg.claude_md.pending_hash -and ((HashText $sp.Engine) -ne [string]$reg.claude_md.pending_hash) -and ((HashText $sp.Engine) -ne [string]$reg.claude_md.engine_hash)) { $clPlan.Note = 'CLAUDE.md ne correspond pas \u00e0 une \u00e9criture de bFrame (installation interrompue) : laiss\u00e9 tel quel.' }
                elseif (ProjectIsEmpty $sp.Project) { $clPlan.Mode = 'delete' }
                else { $clPlan.Mode = 'keep-project'; $clPlan.Text = $sp.Project }
            }

            Say ''
            Say 'Aper\u00e7u de ce qui serait fait :' 'White'
            Say ('  Fichiers de bFrame \u00e0 retirer : ' + $toRemove.Count)
            foreach ($r in $toRemove) { Say ('    - ' + $r) }
            if ($modified.Count -gt 0) {
                Say ('  Fichiers modifi\u00e9s par vous : GARD\u00c9S (\u00e0 supprimer \u00e0 la main si besoin) : ' + $modified.Count) 'Yellow'
                foreach ($r in $modified) { Say ('    ! ' + $r) 'Yellow' }
            }
            if ($setPlan.Mode -eq 'write') {
                Say '  .claude/settings.json : retrait des r\u00e9glages de bFrame (les v\u00f4tres sont gard\u00e9s)'
                foreach ($i in $setPlan.Items) { Say ('    - ' + $i) }
                if ($setPlan.Delete) { Say '    (le fichier devient vide : il sera supprim\u00e9)' }
            }
            if ($setPlan.Note) { Say ('  ' + $setPlan.Note) 'Yellow' }
            if ($clPlan.Mode -eq 'delete') { Say '  CLAUDE.md : la section "# Projet" est vide, le fichier sera supprim\u00e9.' }
            elseif ($clPlan.Mode -eq 'keep-project') { Say '  CLAUDE.md : la partie bFrame est retir\u00e9e, seule votre section "# Projet" est gard\u00e9e.' }
            if ($clPlan.Note) { Say ('  ' + $clPlan.Note) 'Yellow' }
            Say '  Gard\u00e9s dans tous les cas : .bframe/memory/ (votre m\u00e9moire) et .bframe/backup/ (sauvegardes).'
            Say '  Une sauvegarde de CLAUDE.md et de settings.json est faite avant toute modification.'

            if ($DryRun) { Say ''; Say 'Mode essai (-DryRun) : rien n''a \u00e9t\u00e9 \u00e9crit.' 'Green'; return 0 }
            Say ''
            if (-not (Ask 'Retirer bFrame comme indiqu\u00e9 ? (oui/non) ' $true)) { Say 'Rien n''a \u00e9t\u00e9 modifi\u00e9.' 'Yellow'; return 0 }
            $state.Wrote = $true

            if ($clPlan.Mode -ne 'none' -and $clPlan.Mode -ne 'skip') {
                if ($clPlan.Mode -eq 'delete' -or $clPlan.Mode -eq 'keep-project') { Backup 'CLAUDE.md' }
                if ($clPlan.Mode -eq 'delete') { Remove-Item -LiteralPath $cd }
                else { WriteText $cd $clPlan.Text }
            }
            if ($setPlan.Mode -eq 'write') {
                Backup '.claude/settings.json'
                if ($setPlan.Delete) { Remove-Item -LiteralPath $sd } else { WriteText $sd ((ToJson $setPlan.Obj) + "`n") }
            }
            foreach ($r in $toRemove) { Remove-Item -LiteralPath (Dest $r); CleanDirs $r }
            Remove-Item -LiteralPath $regPath
            CleanDirs '.bframe/install.json'

            Say ''
            Say 'bFrame est retir\u00e9.' 'Green'
            Say ('  Retir\u00e9 : ' + $toRemove.Count + ' fichier(s) de bFrame.')
            if ($modified.Count -gt 0) { Say ('  Rest\u00e9s en place car modifi\u00e9s par vous : ' + ($modified -join ', ')) 'Yellow' }
            Say '  Gard\u00e9 : .bframe/memory/ (m\u00e9moire) et .bframe/backup/ (sauvegardes).'
            if ($clPlan.Mode -eq 'delete') { Say '  CLAUDE.md : supprim\u00e9 (il ne contenait plus que la partie bFrame). Copie dans .bframe/backup/.' }
            elseif ($clPlan.Mode -eq 'keep-project') { Say '  CLAUDE.md : seule votre section "# Projet" est conserv\u00e9e. Ancienne version dans .bframe/backup/.' }
            Say '  Relancez Claude Code pour que le retrait soit pris en compte.'
            return 0
        }

        # =================== INSTALLATION / MISE A JOUR ===================
        $src = GetSource
        $root = $src.Root
        $srcFiles = @(ListFiles $root)

        if ($mode -eq 'update') { Say ('Mise \u00e0 jour de bFrame ' + $reg.version + ' vers ' + $Version) 'Cyan' }
        else { Say ('Installation de bFrame ' + $Version) 'Cyan' }

        # --- fichiers du moteur ---
        $ops = New-Object System.Collections.ArrayList
        $newReg = @{}
        foreach ($k in $regFiles.Keys) { $newReg[$k] = $regFiles[$k] }
        $same = 0
        foreach ($rel in $srcFiles) {
            $sf = Join-Path $root ($rel -replace '/', '\')
            $sh = HashFile $sf
            $d = Dest $rel
            $tracked = $regFiles.ContainsKey($rel)
            if (-not (Test-Path -LiteralPath $d -PathType Leaf)) { [void]$ops.Add(@{ Type = 'add'; Rel = $rel; Src = $sf; Hash = $sh }); continue }
            $dh = HashFile $d
            if ($dh -eq $sh) { $same++; if ($tracked) { $newReg[$rel] = $sh }; continue }
            if ($tracked) {
                $rh = $regFiles[$rel]
                if ($dh -eq $rh) { [void]$ops.Add(@{ Type = 'replace'; Rel = $rel; Src = $sf; Hash = $sh }) }
                elseif ($sh -eq $rh) { [void]$ops.Add(@{ Type = 'keep'; Rel = $rel }) }
                else { [void]$ops.Add(@{ Type = 'ask'; Rel = $rel; Src = $sf; Hash = $sh }) }
            } else {
                [void]$ops.Add(@{ Type = 'conflict'; Rel = $rel; Src = $sf; Hash = $sh })
            }
        }
        foreach ($rel in ($regFiles.Keys | Sort-Object)) {
            if ($srcFiles -contains $rel) { continue }
            $d = Dest $rel
            if (-not (Test-Path -LiteralPath $d -PathType Leaf)) { [void]$newReg.Remove($rel); continue }
            if ((HashFile $d) -eq $regFiles[$rel]) { [void]$ops.Add(@{ Type = 'remove'; Rel = $rel }) }
            else { [void]$ops.Add(@{ Type = 'keep-old'; Rel = $rel }); [void]$newReg.Remove($rel) }
        }

        # --- CLAUDE.md ---
        $srcClaudeText = ReadText (Join-Path $root 'CLAUDE.md')
        $sp = SplitClaude $srcClaudeText
        if (-not $sp.Found) { throw 'Le CLAUDE.md de bFrame n''a pas de section "# Projet" : contenu invalide.' }
        $srcEngineHash = HashText $sp.Engine
        $nl = "`n"; if ($srcClaudeText.Contains("`r`n")) { $nl = "`r`n" }
        $cd = Dest 'CLAUDE.md'
        $cl = @{ Mode = 'none'; Text = ''; Note = ''; Hash = $null }
        $regClaudeHash = $null
        if ($reg -and $reg.claude_md) {
            $regClaudeHash = [string]$reg.claude_md.engine_hash
            # Installation interrompue : si CLAUDE.md porte deja la partie bFrame annoncee, il reste gere.
            $pend = [string]$reg.claude_md.pending_hash
            if ($pend -and (Test-Path -LiteralPath $cd -PathType Leaf)) {
                $o2 = ReadText $cd; $d2 = SplitClaude $o2
                if ($d2.Found -and ($o2 -match '@\.bframe/ROUTER\.md')) { $regClaudeHash = $pend }
            }
        }
        if (-not (Test-Path -LiteralPath $cd -PathType Leaf)) {
            $cl.Mode = 'create'; $cl.Text = $srcClaudeText; $cl.Hash = $srcEngineHash
        } else {
            $old = ReadText $cd
            $dp = SplitClaude $old
            if ($regClaudeHash) {
                if (-not $dp.Found) { $cl.Mode = 'skip'; $cl.Note = 'CLAUDE.md n''a plus de section "# Projet" : non modifi\u00e9.' }
                else {
                    $dh = HashText $dp.Engine
                    if ($dh -eq $srcEngineHash) { $cl.Hash = $srcEngineHash }
                    elseif ($dh -eq $regClaudeHash) { $cl.Mode = 'update'; $cl.Text = $sp.Engine + $dp.Project; $cl.Hash = $srcEngineHash }
                    elseif ($srcEngineHash -eq $regClaudeHash) { $cl.Note = 'CLAUDE.md : la partie bFrame a \u00e9t\u00e9 modifi\u00e9e par vous, gard\u00e9e telle quelle.' }
                    else { $cl.Mode = 'ask'; $cl.Text = $sp.Engine + $dp.Project; $cl.Hash = $srcEngineHash }
                }
            } elseif ($old -match '@\.bframe/ROUTER\.md') {
                $cl.Mode = 'skip'; $cl.Note = 'CLAUDE.md semble d\u00e9j\u00e0 contenir bFrame : non modifi\u00e9. Retirez-y l''ancienne partie bFrame \u00e0 la main si vous voulez que ce script la g\u00e8re.'
            } else {
                $cl.Mode = 'merge'; $cl.Hash = $srcEngineHash
                $cl.Text = $sp.Engine + '# Projet' + $nl + $nl + $old.Trim("`r", "`n") + $nl
            }
        }

        # --- settings.json ---
        $srcSet = (ReadText (Join-Path $root '.claude\settings.json')) | ConvertFrom-Json
        $sd = Dest '.claude/settings.json'
        $st = @{ Mode = 'none'; Text = ''; Note = ''; Agent = $null; Hooks = @() }
        if (-not (Test-Path -LiteralPath $sd -PathType Leaf)) {
            $m = MergeSettings ([pscustomobject]@{}) $srcSet
            $st.Mode = 'create'; $st.Text = ReadText (Join-Path $root '.claude\settings.json'); $st.Agent = $m.Agent; $st.Hooks = $m.Hooks
        } else {
            $cur = $null
            try { $cur = (ReadText $sd) | ConvertFrom-Json } catch { $cur = $null }
            if (-not (IsObj $cur)) {
                $st.Mode = 'refuse'
                $st.Note = '.claude/settings.json n''est pas un JSON valide : fichier laiss\u00e9 intact. Corrigez-le (ou renommez-le), puis relancez la commande.'
            } else {
                $m = MergeSettings $cur $srcSet
                if ($m.Error) {
                    $st.Mode = 'refuse'
                    $st.Note = '.claude/settings.json laiss\u00e9 intact : ' + $m.Error + '. Mettez-le d''accord \u00e0 la main (ou renommez-le), puis relancez la commande.'
                } elseif ((-not $m.Agent) -and @($m.Hooks).Count -eq 0) { $st.Mode = 'none' }
                else { $st.Mode = 'merge'; $st.Text = (ToJson $cur) + "`n"; $st.Agent = $m.Agent; $st.Hooks = $m.Hooks }
            }
        }

        # --- memoire (jamais remplacee) ---
        $memDirsToMake = @(); $memFilesToMake = @()
        foreach ($d in $MemoryDirs) { if (-not (Test-Path -LiteralPath (Dest ('.bframe/memory/' + $d)) -PathType Container)) { $memDirsToMake += ('.bframe/memory/' + $d + '/') } }
        foreach ($f in $MemoryModels) { if (-not (Test-Path -LiteralPath (Dest ('.bframe/memory/' + $f)))) { $memFilesToMake += ('.bframe/memory/' + $f) } }

        # --- apercu ---
        function Show([string]$type, [string]$title, [string]$color) {
            $sel = @($ops | Where-Object { $_.Type -eq $type })
            if ($sel.Count -eq 0) { return }
            Say ''
            Say ('  ' + $title + ' (' + $sel.Count + ') :') $color
            foreach ($o in $sel) { Say ('    ' + $o.Rel) }
        }
        Say ''
        Say 'Aper\u00e7u de ce qui serait fait :' 'White'
        Show 'add' 'Fichiers \u00e0 ajouter' 'Gray'
        Show 'replace' 'Fichiers \u00e0 remplacer (non modifi\u00e9s par vous, sauvegard\u00e9s)' 'Gray'
        Show 'remove' 'Fichiers retir\u00e9s de la nouvelle version (non modifi\u00e9s par vous)' 'Gray'
        Show 'ask' 'Modifi\u00e9s par vous ET chang\u00e9s dans la nouvelle version : gard\u00e9s par d\u00e9faut, question ensuite' 'Yellow'
        Show 'conflict' 'D\u00e9j\u00e0 pr\u00e9sents, diff\u00e9rents, non install\u00e9s par bFrame : NON \u00e9cras\u00e9s, question ensuite' 'Yellow'
        Show 'keep' 'Modifi\u00e9s par vous, inchang\u00e9s dans la nouvelle version : gard\u00e9s' 'Gray'
        Show 'keep-old' 'Retir\u00e9s de la nouvelle version mais modifi\u00e9s par vous : gard\u00e9s' 'Gray'
        if ($same -gt 0) { Say ''; Say ('  D\u00e9j\u00e0 en place et identiques : ' + $same) }

        Say ''
        switch ($cl.Mode) {
            'create' { Say '  CLAUDE.md : sera cr\u00e9\u00e9.' }
            'merge' { Say '  CLAUDE.md existe d\u00e9j\u00e0 : le nouveau fichier reprend tout l''ancien contenu, en bas, sous "# Projet". Sauvegarde dans .bframe/backup/.' 'Yellow' }
            'update' { Say '  CLAUDE.md : la partie bFrame est mise \u00e0 jour, votre section "# Projet" est conserv\u00e9e. Sauvegarde dans .bframe/backup/.' }
            'ask' { Say '  CLAUDE.md : la partie bFrame a \u00e9t\u00e9 modifi\u00e9e par vous ET chang\u00e9e dans la nouvelle version : gard\u00e9e par d\u00e9faut, question ensuite.' 'Yellow' }
        }
        if ($cl.Note) { Say ('  ' + $cl.Note) 'Yellow' }
        switch ($st.Mode) {
            'create' { Say '  .claude/settings.json : sera cr\u00e9\u00e9.' }
            'merge' {
                Say '  .claude/settings.json existe d\u00e9j\u00e0 : fusion prudente, vos r\u00e9glages sont gard\u00e9s. Sauvegarde dans .bframe/backup/. Ajout\u00e9 :' 'Yellow'
                if ($st.Agent) { Say ('    - agent : ' + $st.Agent) }
                foreach ($h in $st.Hooks) { Say ('    - hook ' + ($h -replace '\|', ' : ')) }
            }
            'refuse' { Say ('  ' + $st.Note) 'Red' }
        }
        if ($memDirsToMake.Count + $memFilesToMake.Count -gt 0) {
            Say '  M\u00e9moire du projet (jamais remplac\u00e9e ni supprim\u00e9e) : cr\u00e9ation de ce qui manque, vide :'
            foreach ($x in $memDirsToMake) { Say ('    ' + $x) }
            foreach ($x in $memFilesToMake) { Say ('    ' + $x + ' (index vierge)') }
        }
        Say '  Fichier de suivi : .bframe/install.json (version et empreintes).'

        $actionable = @($ops | Where-Object { $_.Type -notin @('keep', 'keep-old') }).Count
        if (@('create', 'merge', 'update', 'ask') -contains $cl.Mode) { $actionable++ }
        if (@('create', 'merge') -contains $st.Mode) { $actionable++ }
        $actionable += $memDirsToMake.Count + $memFilesToMake.Count
        $needReg = (-not $reg) -or ([string]$reg.version -ne $Version)
        if ($actionable -eq 0 -and -not $needReg) {
            Say ''
            Say 'Rien \u00e0 faire : bFrame est d\u00e9j\u00e0 \u00e0 jour, sans doublon.' 'Green'
        } else {
            if ($DryRun) { Say ''; Say 'Mode essai (-DryRun) : rien n''a \u00e9t\u00e9 \u00e9crit.' 'Green'; return 0 }
            Say ''
            if (-not (Ask 'Appliquer ces changements ? (oui/non) ' $true)) { Say 'Rien n''a \u00e9t\u00e9 modifi\u00e9.' 'Yellow'; return 0 }
            $state.Wrote = $true

            # --- registre preliminaire : une installation interrompue reste recuperable et retirable ---
            $newSet = $null
            if ($reg -and $reg.settings) { $newSet = [ordered]@{ created = [bool]$reg.settings.created; agent = $reg.settings.agent; hooks = @($reg.settings.hooks) } }
            if ($st.Mode -eq 'create' -or $st.Mode -eq 'merge') {
                if (-not $newSet) { $newSet = [ordered]@{ created = ($st.Mode -eq 'create'); agent = $null; hooks = @() } }
                if ($st.Agent) { $newSet.agent = $st.Agent }
                $newSet.hooks = @(@($newSet.hooks) + @($st.Hooks) | Select-Object -Unique)
            }
            $preFiles = [ordered]@{}
            $preAll = @{}
            foreach ($k in $newReg.Keys) { $preAll[$k] = $newReg[$k] }
            foreach ($o in $ops) { if ($o.Type -eq 'add') { $preAll[$o.Rel] = $o.Hash } }
            foreach ($k in ($preAll.Keys | Sort-Object)) { $preFiles[$k] = $preAll[$k] }
            $preVersion = $Version
            if ($reg) { $preVersion = [string]$reg.version }
            $preDoc = [ordered]@{ version = $preVersion; installed = (Get-Date -Format 's'); files = $preFiles }
            $preClaude = $null
            if ($reg -and $reg.claude_md) { $preClaude = [ordered]@{ engine_hash = [string]$reg.claude_md.engine_hash } }
            if (@('create', 'merge', 'update') -contains $cl.Mode) {
                if (-not $preClaude) { $preClaude = [ordered]@{ engine_hash = '' } }
                $preClaude.pending_hash = $cl.Hash
            }
            if ($preClaude) { $preDoc.claude_md = $preClaude }
            if ($newSet) { $preDoc.settings = $newSet }
            WriteText $regPath ((ToJson $preDoc) + "`n")

            # --- application ---
            $skipped = @()
            foreach ($o in $ops) {
                switch ($o.Type) {
                    'add' { CopyFile $o.Src (Dest $o.Rel); $newReg[$o.Rel] = $o.Hash }
                    'replace' { Backup $o.Rel; CopyFile $o.Src (Dest $o.Rel); $newReg[$o.Rel] = $o.Hash }
                    'remove' { Remove-Item -LiteralPath (Dest $o.Rel); CleanDirs $o.Rel; [void]$newReg.Remove($o.Rel) }
                    { $_ -eq 'ask' -or $_ -eq 'conflict' } {
                        if (Ask ('Remplacer ' + $o.Rel + ' par la version de bFrame ? Votre fichier est sauvegard\u00e9. (oui/non, non par d\u00e9faut) ') $false) {
                            Backup $o.Rel; CopyFile $o.Src (Dest $o.Rel); $newReg[$o.Rel] = $o.Hash
                        } else { $skipped += $o.Rel }
                    }
                }
            }
            $newClaude = $null
            if ($reg -and $reg.claude_md) { $newClaude = [string]$reg.claude_md.engine_hash }
            switch ($cl.Mode) {
                'create' { WriteText $cd $cl.Text; $newClaude = $cl.Hash }
                { $_ -eq 'merge' -or $_ -eq 'update' } { Backup 'CLAUDE.md'; WriteText $cd $cl.Text; $newClaude = $cl.Hash }
                'ask' {
                    if (Ask 'Remplacer la partie bFrame de CLAUDE.md (votre section "# Projet" est gard\u00e9e, sauvegarde faite) ? (oui/non, non par d\u00e9faut) ' $false) {
                        Backup 'CLAUDE.md'; WriteText $cd $cl.Text; $newClaude = $cl.Hash
                    } else { $skipped += 'CLAUDE.md' }
                }
                'none' { if ($cl.Hash) { $newClaude = $cl.Hash } }
            }
            if ($st.Mode -eq 'create') { WriteText $sd $st.Text }
            elseif ($st.Mode -eq 'merge') { Backup '.claude/settings.json'; WriteText $sd $st.Text }
            foreach ($d in $MemoryDirs) { EnsureDir (Dest ('.bframe/memory/' + $d)) }
            $today = Get-Date -Format 'yyyy-MM-dd'
            foreach ($f in $MemoryModels) {
                $to = Dest ('.bframe/memory/' + $f)
                if (-not (Test-Path -LiteralPath $to)) {
                    $t = ReadText (Join-Path $root ('.bframe\template\memory\' + ($f -replace '/', '\')))
                    WriteText $to ($t.Replace('{{date}}', $today))
                }
            }
            $files = [ordered]@{}
            foreach ($k in ($newReg.Keys | Sort-Object)) { $files[$k] = $newReg[$k] }
            $doc = [ordered]@{ version = $Version; installed = (Get-Date -Format 's'); files = $files }
            if ($newClaude) { $doc.claude_md = [ordered]@{ engine_hash = $newClaude } }
            if ($newSet) { $doc.settings = $newSet }
            WriteText $regPath ((ToJson $doc) + "`n")

            Say ''
            Say ('bFrame ' + $Version + ' est en place.') 'Green'
            if ($skipped.Count -gt 0) { Say ('  Gard\u00e9s tels quels (non remplac\u00e9s) : ' + ($skipped -join ', ')) 'Yellow' }
        }
        if ($st.Mode -eq 'refuse') { Say '  \u00c0 faire : .claude/settings.json n''a pas \u00e9t\u00e9 touch\u00e9 (voir plus haut). Corrigez-le, puis relancez la commande.' 'Yellow' }
        if ($cl.Mode -eq 'skip') { Say ('  \u00c0 voir : ' + $cl.Note) 'Yellow' }

        # --- messages de fin ---
        if (-not (PythonOk)) {
            Say ''
            Say 'Attention : Python est introuvable. Les garde-fous de bFrame (hooks) en ont besoin : installez Python et v\u00e9rifiez que la commande "python" fonctionne.' 'Yellow'
        }
        Say ''
        Say 'Relancez Claude Code dans ce dossier pour que bFrame soit pris en compte.' 'Cyan'
        $missing = @($ReferenceDocs | Where-Object { -not (Test-Path -LiteralPath (Dest ('.bframe/memory/reference/' + $_)) -PathType Leaf) })
        if ($missing.Count -gt 0) {
            Say ''
            Say ('Il manque encore dans .bframe/memory/reference/ : ' + ($missing -join ', ') + '.') 'Cyan'
            Say 'Pour les mettre en place, dites \u00e0 Claude : "Fais l''onboarding du projet". Ce script ne le lance pas.' 'Cyan'
        }
        return 0
    }
    catch {
        Say ''
        Say ('Erreur : ' + $_.Exception.Message) 'Red'
        if ($state.Wrote) {
            Say 'Des fichiers ont peut-\u00eatre \u00e9t\u00e9 modifi\u00e9s avant l''erreur (les anciennes versions sont dans .bframe/backup/). Corrigez la cause puis relancez la m\u00eame commande : elle reprend o\u00f9 elle s''est arr\u00eat\u00e9e. Pour tout retirer, lancez-la avec -Uninstall.' 'Red'
        } else { Say 'Rien n''a \u00e9t\u00e9 modifi\u00e9 par cette commande.' 'Red' }
        return 1
    }
    finally {
        if ($state.Temp -and (Test-Path -LiteralPath $state.Temp)) { Remove-Item -LiteralPath $state.Temp -Recurse -Force -ErrorAction SilentlyContinue }
    }
} $Version ([bool]$Update) ([bool]$Uninstall) ([bool]$DryRun) $SourcePath ([bool]$Yes))[-1]

if ($PSCommandPath) { exit ([int]$exitCode) }
