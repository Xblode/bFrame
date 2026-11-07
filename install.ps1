# bFrame - installe, met a jour ou retire bFrame dans le dossier courant.
# Sans fichier :  irm https://raw.githubusercontent.com/Xblode/bFrame/main/install.ps1 | iex
# Avec options :  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/Xblode/bFrame/main/install.ps1))) -Update
# Options : -Version vX.Y.Z  -Update  -Uninstall  -DryRun  -SourcePath <dossier local>  -Yes (tests)
# Regle de publication : la constante $Version ci-dessous est changee a chaque publication,
# puis un tag Git du meme nom est cree. Sans -Version, -Update vise cette constante (pas d'API).
# Rien n'est ecrit sans accord. Un remplacement de fichier ou d'agent existant exige un accord distinct,
# que -Yes ne donne jamais. Aucune donnee n'est envoyee. Fichier ASCII : les accents sont codes en \uXXXX.

param(
    [string]$Version = 'v0.1.1',   # version figee (tag GitHub) a installer
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
    # Fichiers sans lesquels le verrou d'ecriture et la confirmation des commandes ne tiennent pas.
    $Critical = @('.claude/agents/orchestrator.md', '.claude/hooks/write_guard.py', '.claude/hooks/bash_guard.py', '.claude/settings.json')
    $ReportRel = '.bframe/install-report.md'
    # Bloc balise du .gitignore du projet. Ni la memoire (.bframe/memory/) ni les .env : ils relevent du projet.
    $GiBegin = '# >>> bFrame'
    $GiEnd = '# <<< bFrame'
    $GiLines = @('__pycache__/', '*.pyc', '*.bak', '.claude/state/', '.claude/settings.local.json', '.bframe/backup/', '.bframe/install.json', '.bframe/install-report.md')
    $GiRx = '(?ms)^# >>> bFrame[ \t]*\r?\n.*?^# <<< bFrame[ \t]*(\r?\n|\z)'
    $lat1 = [Text.Encoding]::GetEncoding(28591)   # octets conserves un a un dans .gitignore
    $Target = (Get-Location).ProviderPath.TrimEnd('\')
    $enc = New-Object System.Text.UTF8Encoding($false)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bk = @{ Name = $null; Files = @(); Last = $null }
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
    # Comparaison sans tenir compte de CRLF/LF : empreinte "normalisee" (CRLF lu comme LF), sans toucher aux octets copies.
    function NormText([string]$t) { return $t.Replace("`r`n", "`n") }
    function HashNormFile([string]$p) { HashBytes ($lat1.GetBytes((NormText ($lat1.GetString([IO.File]::ReadAllBytes($p)))))) }
    # Texte contre empreinte du registre : empreinte exacte (anciens registres) ou normalisee.
    function EngMatch([string]$t, [string]$h) {
        if (-not $h) { return $false }
        return (((HashText $t) -eq $h) -or ((HashText (NormText $t)) -eq $h))
    }
    # Le fichier $p est-il encore tel que le registre l'a note (octets exacts, ou identique a CRLF/LF pres) ?
    function UnmodReg([string]$rel, [string]$p) {
        if ((HashFile $p) -eq $regFiles[$rel]) { return $true }
        return [bool]($regNorm.ContainsKey($rel) -and ((HashNormFile $p) -eq $regNorm[$rel]))
    }
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
        if ($Yes) { return $general }   # -Yes ne force jamais un remplacement
        try { $a = Read-Host (T $q) } catch { return $false }
        return ($a -match '^\s*(o|oui|y|yes)\s*$')
    }

    # Dossier de sauvegarde unique : deux lancements dans la meme seconde ne s'ecrasent pas.
    function BkRel([string]$rel) {
        if (-not $bk.Name) {
            $base = Get-Date -Format 'yyyyMMdd-HHmmss'
            $n = $base; $i = 1
            while (Test-Path -LiteralPath (Join-Path $Target ('.bframe\backup\' + $n))) { $i++; $n = $base + '-' + $i }
            [void][IO.Directory]::CreateDirectory((Join-Path $Target ('.bframe\backup\' + $n)))
            $bk.Name = $n
        }
        return ('.bframe/backup/' + $bk.Name + '/' + $rel)
    }
    function Backup([string]$rel) {
        $to = BkRel $rel
        CopyFile (Dest $rel) (Dest $to)
        $bk.Files += ,@($rel, $to)
        $bk.Last = $to
        $lines = @(('Sauvegarde bFrame du ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
                   'Ces fichiers ont \u00e9t\u00e9 copi\u00e9s ici avant d''\u00eatre modifi\u00e9s, remplac\u00e9s ou retir\u00e9s par bFrame.',
                   ('Chaque copie garde son chemin d''origine, relatif \u00e0 la racine du projet (' + $Target + ').'),
                   '', 'Fichiers :')
        foreach ($f in $bk.Files) { $lines += ('- chemin d''origine : ' + $f[0] + '   copie : ' + $f[1]) }
        WriteText (Dest ('.bframe/backup/' + $bk.Name + '/LISEZMOI.txt')) ((T ($lines -join "`r`n")) + "`r`n")
    }
    # Valide un chemin de sauvegarde lu dans le registre ; renvoie le chemin complet ou $null.
    function BackupFull([string]$rel) {
        if (-not $rel) { return $null }
        $r = $rel.Replace('\', '/')
        if ($r -notmatch '^\.bframe/backup/[^/]+/' -or $r -match '(^|/)\.\.(/|$)' -or $r.Contains(':')) { return $null }
        if ($r -match '[<>|"*?]') { return $null }
        foreach ($seg in $r.Split('/')) { if ($seg -eq '' -or $seg -eq '.' -or $seg -match '[. ]$') { return $null } }
        $f = Dest $r
        $base = [IO.Path]::GetFullPath((Dest '.bframe/backup'))
        if (-not [IO.Path]::GetFullPath($f).StartsWith($base + '\', [StringComparison]::OrdinalIgnoreCase)) { return $null }
        # aucune jonction ni lien symbolique sur le chemin, de .bframe jusqu'au fichier
        $cur = $Target
        foreach ($seg in $r.Split('/')) {
            $cur = Join-Path $cur $seg
            if (-not (Test-Path -LiteralPath $cur)) { return $null }
            if (IsReparse $cur) { return $null }
        }
        if (Test-Path -LiteralPath $f -PathType Leaf) { return $f } else { return $null }
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
    # JSON strict : ni commentaire, ni virgule de fin (ce que Claude Code refuse aussi).
    function JsonStrictOk([string]$t) {
        $inS = $false; $esc = $false; $n = $t.Length
        for ($i = 0; $i -lt $n; $i++) {
            $c = $t[$i]
            if ($inS) {
                if ($esc) { $esc = $false } elseif ($c -eq [char]92) { $esc = $true } elseif ($c -eq [char]34) { $inS = $false }
                continue
            }
            if ($c -eq [char]34) { $inS = $true; continue }
            if ($c -eq [char]47) { return $false }
            if ($c -eq [char]44) {
                $j = $i + 1
                while ($j -lt $n -and [char]::IsWhiteSpace($t[$j])) { $j++ }
                if ($j -lt $n -and ($t[$j] -eq [char]93 -or $t[$j] -eq [char]125)) { return $false }
            }
        }
        return $true
    }
    # Renvoie l'objet JSON, ou $null si le texte n'est pas un objet JSON strict.
    function ParseSettings([string]$t) {
        if (-not (JsonStrictOk $t)) { return $null }
        try { $o = $t | ConvertFrom-Json } catch { return $null }
        if (IsObj $o) { return $o }
        return $null
    }
    # Copie un objet du registre en dictionnaire ordonne (champs conserves).
    function Carry($o) {
        $h = [ordered]@{}
        if ($o) { foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = $p.Value } }
        return $h
    }

    # Ajoute "agent" et les hooks de bFrame dans $cur sans rien retirer.
    # $force : remplace une cle "agent" differente. Kind : 'agent' (conflit d'agent) ou 'shape' (forme inattendue).
    function MergeSettings($cur, $src, [bool]$force = $false) {
        $r = @{ Error = $null; Kind = $null; Agent = $null; Prev = $null; Hooks = @() }
        $ap = $cur.PSObject.Properties['agent']
        $diff = [bool]($src.agent -and $ap -and ([string]$ap.Value -ne [string]$src.agent))
        if ($diff -and -not $force) {
            $r.Kind = 'agent'
            $r.Error = 'la cl\u00e9 "agent" vaut d\u00e9j\u00e0 "' + $ap.Value + '" (bFrame veut "' + $src.agent + '")'
            return $r
        }
        $hp = $cur.PSObject.Properties['hooks']
        if ($hp -and -not (IsObj $hp.Value)) { $r.Kind = 'shape'; $r.Error = 'la cl\u00e9 "hooks" n''a pas la forme attendue'; return $r }
        if ($hp) {
            foreach ($ev in $src.hooks.PSObject.Properties) {
                $ex = $hp.Value.PSObject.Properties[$ev.Name]
                if ($ex -and ($ex.Value -isnot [array])) { $r.Kind = 'shape'; $r.Error = 'la liste de hooks "' + $ev.Name + '" n''a pas la forme attendue'; return $r }
            }
        }
        if ($diff) {
            $r.Prev = [string]$ap.Value
            $ap.Value = [string]$src.agent
            $r.Agent = [string]$src.agent
        } elseif ($src.agent -and -not $ap) {
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
            if ($rs.prev_agent) {
                Add-Member -InputObject $cur -NotePropertyName agent -NotePropertyValue ([string]$rs.prev_agent)
                $out += ('agent r\u00e9tabli : ' + $rs.prev_agent)
            }
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

    # Retrait exact : si le fichier est inchange depuis l'installation, on le remet comme avant.
    function ExactPlan($e, [string]$curHash) {
        $r = @{ Kind = 'none'; Path = $null }
        if (-not $e -or -not $e.result_hash -or ([string]$e.result_hash -ne $curHash)) { return $r }
        if ($e.existed -eq $false) { $r.Kind = 'delete'; return $r }
        $bf = BackupFull ([string]$e.backup)
        if ($bf -and $e.original_hash -and ((HashFile $bf) -eq [string]$e.original_hash)) { $r.Kind = 'restore'; $r.Path = $bf }
        return $r
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

    # ---------- .gitignore : bloc balise (octets et fins de ligne conserves) ----------
    function GiBlock([string]$eol) { return ((@($GiBegin) + $GiLines + @($GiEnd)) -join $eol) + $eol }
    function GiRead([string]$p) { return $lat1.GetString([IO.File]::ReadAllBytes($p)) }
    function GiWrite([string]$p, [string]$t) { [IO.File]::WriteAllBytes($p, $lat1.GetBytes($t)) }
    # UTF-16 (BOM) ou fichier avec octets nuls : on n'y touche pas.
    function GiIsUtf16([string]$p) {
        $b = [IO.File]::ReadAllBytes($p)
        if ($b.Length -ge 2 -and (($b[0] -eq 255 -and $b[1] -eq 254) -or ($b[0] -eq 254 -and $b[1] -eq 255))) { return $true }
        $n = [Math]::Min($b.Length, 4096)
        for ($i = 0; $i -lt $n; $i++) { if ($b[$i] -eq 0) { return $true } }
        return $false
    }
    $Utf16Note = '.gitignore est en UTF-16 : non modifi\u00e9 pour ne pas l''abimer. Ajoutez-y \u00e0 la main le bloc "# >>> bFrame" ou convertissez-le en UTF-8.'
    # Plan d'ajout ou de rafraichissement. Modes : none, create, add, update, skip.
    function PlanGitignore {
        $g = @{ Mode = 'none'; Text = ''; Note = ''; Warn = ''; Old = '' }
        $p = Dest '.gitignore'
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { $g.Mode = 'create'; $g.Text = GiBlock "`n"; return $g }
        if (GiIsUtf16 $p) { $g.Mode = 'skip'; $g.Note = $Utf16Note; return $g }
        $t = GiRead $p
        $eol = "`n"; if ($t.Contains("`r`n")) { $eol = "`r`n" }
        $want = GiBlock $eol
        $ms = @([regex]::Matches($t, $GiRx))
        $rest = $t
        if ($ms.Count -gt 1) { $g.Mode = 'skip'; $g.Note = '.gitignore contient plusieurs blocs bFrame : non modifi\u00e9. Gardez-en un seul \u00e0 la main.'; return $g }
        if ($ms.Count -eq 1) {
            $m = $ms[0]
            $rest = $t.Remove($m.Index, $m.Length)
            if ($m.Value -ne $want) { $g.Mode = 'update'; $g.Old = $m.Value; $g.Text = $t.Substring(0, $m.Index) + $want + $t.Substring($m.Index + $m.Length) }
        } elseif ($t -match '(?m)^# (>>>|<<<) bFrame') {
            $g.Mode = 'skip'; $g.Note = '.gitignore contient un rep\u00e8re bFrame incomplet : non modifi\u00e9. Corrigez-le \u00e0 la main.'; return $g
        } else {
            $base = $t
            if ($base.Length -gt 0 -and -not $base.EndsWith("`n")) { $base += $eol }
            $g.Mode = 'add'; $g.Text = $base + $want
        }
        $ignoresMem = $false
        foreach ($ln in ($rest -split "\r?\n")) {
            $l = $ln.Trim()
            if ($l -eq '' -or $l.StartsWith('#') -or $l.StartsWith('!')) { continue }
            # .bframe, /.bframe/, .bframe/*, .bframe/**, .bframe/memory/*, **/.bframe/ ... (avec ou sans / final)
            if ($l -match '^(\*\*/|/)?\.bframe(/(memory(/\*{0,2})?|\*{1,2})?)?$') { $ignoresMem = $true }
        }
        if ($ignoresMem) { $g.Warn = 'Votre .gitignore ignore d\u00e9j\u00e0 .bframe/ ou .bframe/memory/ : la m\u00e9moire du projet ne suivra pas Git.' }
        return $g
    }
    # Plan de retrait. Modes : none, write, delete.
    function PlanGitignoreRemove([bool]$created) {
        $g = @{ Mode = 'none'; Text = ''; Note = ''; Path = $null }
        $p = Dest '.gitignore'
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return $g }
        if (GiIsUtf16 $p) { $g.Note = $Utf16Note; return $g }
        $t = GiRead $p
        $ms = @([regex]::Matches($t, $GiRx))
        if ($ms.Count -eq 0) { return $g }
        $rest = $t
        for ($i = $ms.Count - 1; $i -ge 0; $i--) { $rest = $rest.Remove($ms[$i].Index, $ms[$i].Length) }
        $g.Text = $rest
        if ($created -and $rest.Trim().Length -eq 0) { $g.Mode = 'delete' } else { $g.Mode = 'write' }
        return $g
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

    # ---------- Jonctions et liens symboliques ----------
    function IsReparse([string]$p) {
        try { $a = [IO.File]::GetAttributes($p) } catch { return $false }
        return (($a -band [IO.FileAttributes]::ReparsePoint) -ne 0)
    }
    function WalkReparse([string]$dir, $hits) {
        if (IsReparse $dir) { [void]$hits.Add($dir); return }
        foreach ($e in [IO.Directory]::GetFileSystemEntries($dir)) {
            if (IsReparse $e) { [void]$hits.Add($e); continue }
            if ([IO.Directory]::Exists($e)) { WalkReparse $e $hits }
        }
    }
    # Liste les points de reprise du dossier du projet, de .claude, de .bframe et de leur contenu.
    function FindReparse {
        $hits = New-Object System.Collections.ArrayList
        if (IsReparse $Target) { [void]$hits.Add($Target); return @($hits) }
        foreach ($r in @('.claude', '.bframe')) {
            $p = Dest $r
            if ([IO.Directory]::Exists($p)) { WalkReparse $p $hits }
            elseif ([IO.File]::Exists($p) -and (IsReparse $p)) { [void]$hits.Add($p) }
        }
        foreach ($f in @('CLAUDE.md', '.gitignore')) {
            $p = Dest $f
            if ([IO.File]::Exists($p) -and (IsReparse $p)) { [void]$hits.Add($p) }
        }
        return @($hits)
    }

    # ---------- Depot Git parent ----------
    function ParentRepo {
        $d = Split-Path $Target -Parent
        while ($d) {
            if (Test-Path -LiteralPath (Join-Path $d '.git')) { return $d }
            $n = Split-Path $d -Parent
            if (-not $n -or $n -eq $d) { break }
            $d = $n
        }
        return $null
    }
    # CLAUDE.md des dossiers parents (jusqu'a la racine du depot ; sans depot, le parent direct seulement).
    function ParentClaudeFiles([string]$repoRoot) {
        $out = @()
        $d = Split-Path $Target -Parent
        while ($d) {
            if (Test-Path -LiteralPath (Join-Path $d 'CLAUDE.md') -PathType Leaf) { $out += (Join-Path $d 'CLAUDE.md') }
            if (-not $repoRoot) { break }
            if ($d -ieq $repoRoot) { break }
            $n = Split-Path $d -Parent
            if (-not $n -or $n -eq $d) { break }
            $d = $n
        }
        return $out
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
    # Kind : ok, absent, store (raccourci du Microsoft Store), broken.
    function PythonState {
        $cmd = $null
        try { $cmd = Get-Command python -ErrorAction SilentlyContinue | Select-Object -First 1 } catch { }
        if (-not $cmd) { return @{ Ok = $false; Kind = 'absent'; Text = 'Python est introuvable (la commande "python" n''existe pas)' } }
        $path = ''
        try { $path = [string]$cmd.Source } catch { }
        $o = ''; $good = $false
        try { $o = & python --version 2>&1 | Out-String; $good = ($LASTEXITCODE -eq 0 -and $o -match 'Python \d') } catch { $good = $false }
        if ($good) { return @{ Ok = $true; Kind = 'ok'; Text = ('Python disponible (' + $o.Trim() + ')') } }
        if ($path -match '(?i)\\Microsoft\\WindowsApps\\') { return @{ Ok = $false; Kind = 'store'; Text = 'la commande "python" est le raccourci du Microsoft Store : Python n''est pas install\u00e9' } }
        return @{ Ok = $false; Kind = 'broken'; Text = 'la commande "python" ne fonctionne pas' }
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

    # Consequence, pour l'utilisateur, du remplacement d'un de ses fichiers par celui de bFrame.
    function Implication([string]$rel) {
        $parts = $rel.Split('/')
        $leaf = $parts[$parts.Length - 1]
        if ($rel -match '^\.claude/agents/') { return ('votre agent ' + [IO.Path]::GetFileNameWithoutExtension($leaf) + ' ne sera plus actif ; une copie sera gard\u00e9e') }
        if ($rel -match '^\.claude/hooks/') { return ('votre hook ' + $leaf + ' sera remplac\u00e9 et ne fera plus ce que vous aviez pr\u00e9vu ; une copie sera gard\u00e9e') }
        if ($rel -match '^\.claude/rules/') { return ('votre r\u00e8gle ' + $leaf + ' ne s''appliquera plus telle quelle ; une copie sera gard\u00e9e') }
        if ($rel -match '^\.claude/skills/') { return ('votre skill ' + $parts[2] + ' sera remplac\u00e9 (' + $leaf + ') ; une copie sera gard\u00e9e') }
        return 'votre fichier sera remplac\u00e9 ; une copie sera gard\u00e9e'
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

        # Jonctions et liens symboliques : arret avant toute ecriture
        $links = @(FindReparse)
        if ($links.Count -gt 0) {
            $shown = ($links | Select-Object -First 5) -join ' ; '
            throw ('Point de reprise (jonction ou lien symbolique) d\u00e9tect\u00e9 : ' + $shown + '. bFrame refuse d''\u00e9crire \u00e0 travers un tel lien, qui pourrait mener hors du projet. Remplacez-le par un vrai dossier, puis relancez. Rien n''a \u00e9t\u00e9 \u00e9crit.')
        }

        # Registre : absent, valide, ou illisible (alors reconstruit)
        $regPath = Dest '.bframe/install.json'
        $reg = $null
        $regRebuilt = $false
        if (Test-Path -LiteralPath $regPath -PathType Leaf) {
            try { $reg = (ReadText $regPath) | ConvertFrom-Json } catch { $reg = $null }
            if (-not $reg -or -not $reg.files) { $reg = $null; $regRebuilt = $true }
        }
        $regFiles = @{}
        $regNorm = @{}   # empreintes normalisees (CRLF = LF), absentes des anciens registres
        $replMap = @{}   # fichiers du moteur qui avaient remplace un fichier de l'utilisateur : chemin -> sauvegarde
        $pre = @{}
        if ($reg) {
            foreach ($p in $reg.files.PSObject.Properties) {
                $bad = BadRegPath $p.Name
                if ($bad) { throw ('Le fichier .bframe/install.json contient un chemin refus\u00e9 : "' + $p.Name + '" (' + $bad + '). Arr\u00eat : rien n''a \u00e9t\u00e9 \u00e9crit ni supprim\u00e9. Corrigez ou supprimez ce fichier de suivi \u00e0 la main.') }
                $regFiles[$p.Name.Replace('\', '/')] = [string]$p.Value
            }
            if ($reg.files_norm -and (IsObj $reg.files_norm)) {
                foreach ($p in $reg.files_norm.PSObject.Properties) {
                    $k = $p.Name.Replace('\', '/')
                    if ($regFiles.ContainsKey($k) -and $p.Value) { $regNorm[$k] = [string]$p.Value }
                }
            }
            if ($reg.replaced -and (IsObj $reg.replaced)) {
                foreach ($p in $reg.replaced.PSObject.Properties) {
                    $k = $p.Name.Replace('\', '/')
                    if ($regFiles.ContainsKey($k)) { $replMap[$k] = [string]$p.Value }
                }
            }
            foreach ($p in @($reg.preexisting)) {
                if (-not $p) { continue }
                $bad = BadRegPath ([string]$p)
                if ($bad) { throw ('Le fichier .bframe/install.json contient un chemin refus\u00e9 : "' + $p + '" (' + $bad + '). Arr\u00eat : rien n''a \u00e9t\u00e9 \u00e9crit ni supprim\u00e9. Corrigez ou supprimez ce fichier de suivi \u00e0 la main.') }
                $pre[([string]$p).Replace('\', '/')] = $true
            }
        }

        $mode = 'install'
        if ($Uninstall) { $mode = 'uninstall' } elseif ($Update) { $mode = 'update' }
        if ($mode -eq 'update' -and -not $reg -and -not $regRebuilt) { throw 'bFrame n''est pas install\u00e9 ici (pas de .bframe/install.json). Lancez la commande sans -Update.' }
        if ($mode -eq 'update' -and -not $reg) { $mode = 'install' }   # registre illisible : reconstruit comme une installation
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

        # Sous-dossier d'un depot Git
        $rep = @{ ParentRepo = $null; ParentClaude = @(); Replaced = @(); Updated = @(); ClBackup = '' }
        if ($mode -ne 'uninstall') {
            $pr = ParentRepo
            $rep.ParentRepo = $pr
            $rep.ParentClaude = @(ParentClaudeFiles $pr)
            if ($pr) {
                Say ''
                Say ('Attention : ce dossier est un sous-dossier d''un d\u00e9p\u00f4t Git. Racine trouv\u00e9e : ' + $pr) 'Yellow'
                Say '  bFrame serait install\u00e9 ici, pas \u00e0 la racine du d\u00e9p\u00f4t.' 'Yellow'
            }
            foreach ($pc in $rep.ParentClaude) { Say ('Attention : un CLAUDE.md existe dans un dossier parent : ' + $pc + ' (Claude Code le lira aussi).') 'Yellow' }
            if ($pr -and -not $DryRun) {
                if ($Yes) { throw ('Sous-dossier d''un d\u00e9p\u00f4t Git (racine : ' + $pr + ') : confirmation impossible avec -Yes. Relancez sans -Yes. Rien n''a \u00e9t\u00e9 \u00e9crit.') }
                if (-not (Ask 'Installer bFrame dans ce sous-dossier ? (oui/non, non par d\u00e9faut) ' $false)) { throw 'Installation non confirm\u00e9e : aucune installation n''a eu lieu. Rien n''a \u00e9t\u00e9 \u00e9crit.' }
            }
        }

        # =================== RETRAIT ===================
        if ($mode -eq 'uninstall') {
            $noReg = (-not $reg)
            $root = $null
            $srcFilesU = @()
            if ($noReg) {
                if ($regRebuilt) { Say 'Le fichier de suivi .bframe/install.json est illisible ou incomplet.' 'Yellow' }
                else { Say 'Pas de fichier de suivi .bframe/install.json.' 'Yellow' }
                Say ('  bFrame ' + $Version + ' sert de r\u00e9f\u00e9rence : seuls les fichiers identiques \u00e0 cette version seront propos\u00e9s au retrait.') 'Yellow'
                $src = GetSource
                $root = $src.Root
                $srcFilesU = @(ListFiles $root)
                foreach ($rel in $srcFilesU) {
                    $d = Dest $rel
                    $sfU = Join-Path $root ($rel -replace '/', '\')
                    if ((Test-Path -LiteralPath $d -PathType Leaf) -and (((HashFile $d) -eq (HashFile $sfU)) -or ((HashNormFile $d) -eq (HashNormFile $sfU)))) { $regFiles[$rel] = HashFile $d; $regNorm[$rel] = HashNormFile $d }
                }
                $srcClU = ReadText (Join-Path $root 'CLAUDE.md')
                $srcSetU = (ReadText (Join-Path $root '.claude\settings.json')) | ConvertFrom-Json
                $mu = MergeSettings ([pscustomobject]@{}) $srcSetU
                $spU = SplitClaude $srcClU
                $reg = [pscustomobject]@{
                    version = $Version
                    claude_md = [pscustomobject]@{ engine_hash = (HashText $spU.Engine) }
                    settings = [pscustomobject]@{ created = $false; agent = $mu.Agent; hooks = @($mu.Hooks) }
                    gitignore = [pscustomobject]@{ created = $false }
                }
            }
            Say ('Retrait de bFrame ' + $reg.version) 'Cyan'
            $toRemove = @(); $modified = @(); $gone = @(); $keptPre = @(); $differ = @()
            foreach ($rel in ($regFiles.Keys | Sort-Object)) {
                $d = Dest $rel
                if (-not (Test-Path -LiteralPath $d -PathType Leaf)) { $gone += $rel }
                elseif ($pre.ContainsKey($rel)) { $keptPre += $rel }
                elseif (UnmodReg $rel $d) { $toRemove += $rel }
                else { $modified += $rel }
            }
            # Fichiers du moteur qui avaient remplace un fichier de l'utilisateur : retablir l'original si possible.
            $toRestore = @(); $replKept = @()   # restaurations (rel|chemin de sauvegarde) ; (rel|explication)
            foreach ($rel in @($toRemove)) {
                if (-not $replMap.ContainsKey($rel)) { continue }
                $bf = BackupFull $replMap[$rel]
                if ($bf) { $toRestore += ($rel + '|' + $bf); $toRemove = @($toRemove | Where-Object { $_ -ne $rel }) }
                else { $toRemove = @($toRemove | Where-Object { $_ -ne $rel }); $replKept += ($rel + '|sauvegarde introuvable ou refus\u00e9e (' + $replMap[$rel] + ')') }
            }
            foreach ($rel in $modified) { if ($replMap.ContainsKey($rel)) { $replKept += ($rel + '|modifi\u00e9 depuis l''installation ; votre original est dans ' + $replMap[$rel]) } }
            if ($noReg) {
                foreach ($rel in $srcFilesU) { if ((Test-Path -LiteralPath (Dest $rel) -PathType Leaf) -and -not $regFiles.ContainsKey($rel)) { $differ += $rel } }
            }
            $repFile = Dest $ReportRel
            $hasReport = Test-Path -LiteralPath $repFile -PathType Leaf

            # settings.json
            $setPlan = @{ Mode = 'none'; Items = @(); Obj = $null; Delete = $false; Note = ''; Path = $null }
            $sd = Dest '.claude/settings.json'
            if ($reg.settings -and (Test-Path -LiteralPath $sd -PathType Leaf)) {
                $curH = HashFile $sd
                $ex = ExactPlan $reg.settings $curH
                if ($noReg -and $curH -eq (HashFile (Join-Path $root '.claude\settings.json'))) {
                    $setPlan.Mode = 'delete'; $setPlan.Items = @('fichier identique \u00e0 celui de bFrame')
                } elseif ($ex.Kind -eq 'delete') {
                    $setPlan.Mode = 'delete'; $setPlan.Items = @('fichier cr\u00e9\u00e9 par bFrame et inchang\u00e9')
                } elseif ($ex.Kind -eq 'restore') {
                    $setPlan.Mode = 'restore'; $setPlan.Path = $ex.Path; $setPlan.Items = @('inchang\u00e9 depuis l''installation : votre version d''origine est r\u00e9tablie telle quelle')
                } else {
                    $cur = ParseSettings (ReadText $sd)
                    if (-not $cur) { $setPlan.Note = '.claude/settings.json n''est pas un JSON valide : laiss\u00e9 tel quel, retirez-y \u00e0 la main "agent" et les hooks de bFrame.' }
                    else {
                        $items = @(UnmergeSettings $cur $reg.settings)
                        if ($items.Count -gt 0) {
                            $setPlan.Mode = 'write'; $setPlan.Items = $items; $setPlan.Obj = $cur
                            if (@($cur.PSObject.Properties).Count -eq 0 -and $reg.settings.created) { $setPlan.Delete = $true }
                            if ($reg.settings.result_hash) { $setPlan.Note = '.claude/settings.json a chang\u00e9 depuis l''installation : seul ce qui vient de bFrame est retir\u00e9, le reste est gard\u00e9.' }
                        }
                    }
                }
            }
            # CLAUDE.md
            $clPlan = @{ Mode = 'none'; Text = ''; Note = ''; Path = $null }
            $cd = Dest 'CLAUDE.md'
            if ($reg.claude_md -and (Test-Path -LiteralPath $cd -PathType Leaf)) {
                $curH = HashFile $cd
                $ex = ExactPlan $reg.claude_md $curH
                if ($ex.Kind -eq 'delete') { $clPlan.Mode = 'delete' }
                elseif ($ex.Kind -eq 'restore') { $clPlan.Mode = 'restore'; $clPlan.Path = $ex.Path }
                else {
                    $sp = SplitClaude (ReadText $cd)
                    if (-not $sp.Found) { $clPlan.Note = 'CLAUDE.md n''a plus de section "# Projet" : laiss\u00e9 tel quel.' }
                    elseif ($noReg -and -not (EngMatch $sp.Engine ([string]$reg.claude_md.engine_hash))) { $clPlan.Note = 'CLAUDE.md ne correspond pas \u00e0 la partie bFrame de ' + $Version + ' : laiss\u00e9 tel quel.' }
                    elseif (-not $reg.claude_md.pending_hash -and -not (EngMatch $sp.Engine ([string]$reg.claude_md.engine_hash))) { $clPlan.Note = 'La partie bFrame de CLAUDE.md (au-dessus de "# Projet") a \u00e9t\u00e9 modifi\u00e9e depuis l''installation : CLAUDE.md est laiss\u00e9 tel quel, aucune de vos r\u00e8gles n''est perdue.' }
                    elseif ($reg.claude_md.pending_hash -and -not (EngMatch $sp.Engine ([string]$reg.claude_md.pending_hash)) -and -not (EngMatch $sp.Engine ([string]$reg.claude_md.engine_hash))) { $clPlan.Note = 'CLAUDE.md ne correspond pas \u00e0 une \u00e9criture de bFrame (installation interrompue) : laiss\u00e9 tel quel.' }
                    elseif (ProjectIsEmpty $sp.Project) { $clPlan.Mode = 'delete-empty' }
                    else { $clPlan.Mode = 'keep-project'; $clPlan.Text = $sp.Project }
                    if ($clPlan.Mode -in @('delete-empty', 'keep-project') -and $reg.claude_md.result_hash) { $clPlan.Note = 'CLAUDE.md a chang\u00e9 depuis l''installation : seule la partie bFrame est retir\u00e9e.' }
                }
            }

            # .gitignore
            $giCreatedBefore = $false
            if ($reg.gitignore -and $reg.gitignore.created) { $giCreatedBefore = $true }
            $gid = Dest '.gitignore'
            $giPlan = @{ Mode = 'none'; Text = ''; Note = ''; Path = $null }
            if ($reg.gitignore -and (Test-Path -LiteralPath $gid -PathType Leaf) -and -not (GiIsUtf16 $gid)) {
                $ex = ExactPlan $reg.gitignore (HashFile $gid)
                if ($ex.Kind -eq 'delete') { $giPlan.Mode = 'delete' }
                elseif ($ex.Kind -eq 'restore') { $giPlan.Mode = 'restore'; $giPlan.Path = $ex.Path }
            }
            if ($giPlan.Mode -eq 'none') { $giPlan = PlanGitignoreRemove $giCreatedBefore }

            # Avertissements : ce qui reste et ce qui en dependait
            $warn = @()
            foreach ($m in $modified) {
                if ($m -like '.claude/hooks/*') { $warn += ($m + ' (hook adapt\u00e9 par vous) reste, mais sa d\u00e9claration de bFrame dans settings.json est retir\u00e9e : il ne sera plus appel\u00e9.') }
                elseif ($m -like '.claude/agents/*') { $warn += ($m + ' (agent adapt\u00e9 par vous) reste, mais "agent" est retir\u00e9 de settings.json : il n''est plus l''agent de d\u00e9marrage.') }
            }
            if ($setPlan.Mode -eq 'none' -and $setPlan.Note) {
                $rh = @($toRemove | Where-Object { $_ -like '.claude/hooks/*' -or $_ -like '.claude/agents/*' })
                if ($rh.Count -gt 0) { $warn += 'settings.json n''a pas \u00e9t\u00e9 modifi\u00e9 et peut encore appeler des hooks ou un agent retir\u00e9s.' }
            }

            Say ''
            Say 'Aper\u00e7u de ce qui serait fait :' 'White'
            Say ('  Fichiers de bFrame \u00e0 retirer : ' + $toRemove.Count)
            foreach ($r in $toRemove) { Say ('    - ' + $r) }
            if ($toRestore.Count -gt 0) {
                Say ('  Fichiers de bFrame qui avaient remplac\u00e9 un des v\u00f4tres : votre original est r\u00e9tabli (' + $toRestore.Count + ') :')
                foreach ($x in $toRestore) { $pp = $x.Split('|'); Say ('    <- ' + $pp[0] + ' (depuis ' + (Split-Path $pp[1] -Leaf) + ' dans la sauvegarde)') }
            }
            if ($replKept.Count -gt 0) {
                Say ('  Fichiers de bFrame qui avaient remplac\u00e9 un des v\u00f4tres, LAISS\u00c9S EN PLACE : ' + $replKept.Count) 'Yellow'
                foreach ($x in $replKept) { $pp = $x.Split('|'); Say ('    ! ' + $pp[0] + ' : ' + $pp[1]) 'Yellow' }
            }
            if ($hasReport) { Say '  Rapport .bframe/install-report.md : retir\u00e9.' }
            if ($keptPre.Count -gt 0) {
                Say ('  D\u00e9j\u00e0 pr\u00e9sents avant bFrame (identiques), GARD\u00c9S : ' + $keptPre.Count) 'Yellow'
                foreach ($r in $keptPre) { Say ('    = ' + $r) 'Yellow' }
            }
            if ($modified.Count -gt 0) {
                Say ('  Fichiers modifi\u00e9s par vous : GARD\u00c9S (\u00e0 supprimer \u00e0 la main si besoin) : ' + $modified.Count) 'Yellow'
                foreach ($r in $modified) { Say ('    ! ' + $r) 'Yellow' }
            }
            if ($differ.Count -gt 0) {
                Say ('  Pr\u00e9sents mais diff\u00e9rents de bFrame ' + $Version + ' : GARD\u00c9S : ' + $differ.Count) 'Yellow'
                foreach ($r in $differ) { Say ('    ! ' + $r) 'Yellow' }
            }
            switch ($setPlan.Mode) {
                'write' {
                    Say '  .claude/settings.json : retrait des r\u00e9glages de bFrame (les v\u00f4tres sont gard\u00e9s)'
                    foreach ($i in $setPlan.Items) { Say ('    - ' + $i) }
                    if ($setPlan.Delete) { Say '    (le fichier devient vide : il sera supprim\u00e9)' }
                }
                'delete' { Say ('  .claude/settings.json : sera supprim\u00e9 (' + $setPlan.Items[0] + ').') }
                'restore' { Say ('  .claude/settings.json : ' + $setPlan.Items[0] + '.') }
            }
            if ($setPlan.Note) { Say ('  ' + $setPlan.Note) 'Yellow' }
            switch ($clPlan.Mode) {
                'delete' { Say '  CLAUDE.md : cr\u00e9\u00e9 par bFrame et inchang\u00e9, il sera supprim\u00e9.' }
                'delete-empty' { Say '  CLAUDE.md : la section "# Projet" est vide, le fichier sera supprim\u00e9.' }
                'restore' { Say '  CLAUDE.md : inchang\u00e9 depuis l''installation, votre version d''origine est r\u00e9tablie telle quelle.' }
                'keep-project' { Say '  CLAUDE.md : la partie bFrame est retir\u00e9e, seule votre section "# Projet" est gard\u00e9e.' }
            }
            if ($clPlan.Note) { Say ('  ' + $clPlan.Note) 'Yellow' }
            switch ($giPlan.Mode) {
                'write' { Say '  .gitignore : le bloc "# >>> bFrame" est retir\u00e9, le reste est gard\u00e9. Sauvegarde dans .bframe/backup/.' }
                'delete' { Say '  .gitignore : cr\u00e9\u00e9 par bFrame, il sera supprim\u00e9. Copie dans .bframe/backup/.' }
                'restore' { Say '  .gitignore : inchang\u00e9 depuis l''installation, votre version d''origine est r\u00e9tablie telle quelle.' }
            }
            if ($giPlan.Note) { Say ('  ' + $giPlan.Note) 'Yellow' }
            foreach ($w in $warn) { Say ('  Attention : ' + $w) 'Yellow' }
            Say '  Gard\u00e9s dans tous les cas : .bframe/memory/ (votre m\u00e9moire) et .bframe/backup/ (sauvegardes).'
            Say '  Une sauvegarde de CLAUDE.md, de settings.json et de .gitignore est faite avant toute modification.'

            $cnt = $toRemove.Count + $toRestore.Count
            if ($hasReport) { $cnt++ }
            if ($setPlan.Mode -ne 'none') { $cnt++ }
            if ($clPlan.Mode -ne 'none') { $cnt++ }
            if ($giPlan.Mode -ne 'none') { $cnt++ }
            if ($cnt -eq 0) {
                Say ''
                Say 'Rien n''a \u00e9t\u00e9 retir\u00e9 : aucun \u00e9l\u00e9ment de bFrame reconnu \u00e0 retirer.' 'Yellow'
                if ($regRebuilt) { Say '  Le fichier de suivi illisible .bframe/install.json est laiss\u00e9 tel quel.' 'Yellow' }
                return 0
            }
            if ($DryRun) { Say ''; Say 'Mode essai (-DryRun) : rien n''a \u00e9t\u00e9 \u00e9crit.' 'Green'; return 0 }
            Say ''
            if (-not (Ask 'Retirer bFrame comme indiqu\u00e9 ? (oui/non) ' $true)) { Say 'Rien n''a \u00e9t\u00e9 modifi\u00e9.' 'Yellow'; return 0 }
            $state.Wrote = $true

            switch ($clPlan.Mode) {
                { $_ -in @('delete', 'delete-empty') } { Backup 'CLAUDE.md'; Remove-Item -LiteralPath $cd }
                'restore' { Backup 'CLAUDE.md'; [IO.File]::Copy($clPlan.Path, $cd, $true) }
                'keep-project' { Backup 'CLAUDE.md'; WriteText $cd $clPlan.Text }
            }
            switch ($setPlan.Mode) {
                'delete' { Backup '.claude/settings.json'; Remove-Item -LiteralPath $sd }
                'restore' { Backup '.claude/settings.json'; [IO.File]::Copy($setPlan.Path, $sd, $true) }
                'write' { Backup '.claude/settings.json'; if ($setPlan.Delete) { Remove-Item -LiteralPath $sd } else { WriteText $sd ((ToJson $setPlan.Obj) + "`n") } }
            }
            switch ($giPlan.Mode) {
                'delete' { Backup '.gitignore'; Remove-Item -LiteralPath $gid }
                'restore' { Backup '.gitignore'; [IO.File]::Copy($giPlan.Path, $gid, $true) }
                'write' { Backup '.gitignore'; GiWrite $gid $giPlan.Text }
            }
            foreach ($r in $toRemove) { Remove-Item -LiteralPath (Dest $r); CleanDirs $r }
            foreach ($x in $toRestore) { $pp = $x.Split('|'); Backup $pp[0]; [IO.File]::Copy($pp[1], (Dest $pp[0]), $true) }
            if ($hasReport) { Remove-Item -LiteralPath $repFile; CleanDirs $ReportRel }
            if (-not $noReg) { Remove-Item -LiteralPath $regPath; CleanDirs '.bframe/install.json' }
            elseif ($regRebuilt) { Backup '.bframe/install.json'; Remove-Item -LiteralPath $regPath; CleanDirs '.bframe/install.json' }
            CleanDirs '.claude/settings.json'

            Say ''
            if (($keptPre.Count + $modified.Count + $differ.Count + $replKept.Count) -gt 0 -or ($toRemove.Count + $toRestore.Count) -eq 0) { Say ('Retrait partiel : ' + ($toRemove.Count + $toRestore.Count) + ' fichier(s) du moteur retir\u00e9(s) ou r\u00e9tabli(s), les autres sont rest\u00e9s en place (voir ci-dessous).') 'Yellow' }
            else { Say 'bFrame est retir\u00e9.' 'Green' }
            Say ('  Retir\u00e9 : ' + $toRemove.Count + ' fichier(s) de bFrame.')
            foreach ($x in $toRestore) { $pp = $x.Split('|'); Say ('  Original r\u00e9tabli : ' + $pp[0] + ' (votre fichier d''avant bFrame, depuis ' + (Split-Path $pp[1] -Parent) + ')') }
            foreach ($x in $replKept) { $pp = $x.Split('|'); Say ('  Laiss\u00e9 en place : ' + $pp[0] + ' : ' + $pp[1]) 'Yellow' }
            if ($keptPre.Count -gt 0) { Say ('  Rest\u00e9s en place car pr\u00e9sents avant bFrame : ' + ($keptPre -join ', ')) 'Yellow' }
            if ($modified.Count -gt 0) { Say ('  Rest\u00e9s en place car modifi\u00e9s par vous : ' + ($modified -join ', ')) 'Yellow' }
            if ($differ.Count -gt 0) { Say ('  Rest\u00e9s en place car diff\u00e9rents de bFrame : ' + ($differ -join ', ')) 'Yellow' }
            if ($noReg) { Say '  Sans fichier de suivi, seuls les fichiers identiques \u00e0 bFrame ont pu \u00eatre reconnus : v\u00e9rifiez le reste de .claude/ et .bframe/.' 'Yellow' }
            Say '  Gard\u00e9 : .bframe/memory/ (m\u00e9moire) et .bframe/backup/ (sauvegardes).'
            if ($clPlan.Mode -eq 'restore') { Say '  CLAUDE.md : version d''origine r\u00e9tablie telle quelle.' }
            elseif ($clPlan.Mode -like 'delete*') { Say '  CLAUDE.md : supprim\u00e9. Copie dans .bframe/backup/.' }
            elseif ($clPlan.Mode -eq 'none' -and $clPlan.Note) { Say ('  CLAUDE.md : ' + $clPlan.Note) 'Yellow' }
            elseif ($clPlan.Mode -eq 'keep-project') { Say '  CLAUDE.md : seule votre section "# Projet" est conserv\u00e9e. Ancienne version dans .bframe/backup/.' }
            foreach ($w in $warn) { Say ('  Attention : ' + $w) 'Yellow' }
            Say '  Relancez Claude Code pour que le retrait soit pris en compte.'
            return 0
        }

        # =================== INSTALLATION / MISE A JOUR ===================
        $src = GetSource
        $root = $src.Root
        $srcFiles = @(ListFiles $root)

        if ($mode -eq 'update') { Say ('Mise \u00e0 jour de bFrame ' + $reg.version + ' vers ' + $Version) 'Cyan' }
        else { Say ('Installation de bFrame ' + $Version) 'Cyan' }
        if ($regRebuilt) { Say '  Le fichier de suivi .bframe/install.json \u00e9tait illisible ou incomplet : il sera reconstruit \u00e0 partir de bFrame (copie de l''ancien dans .bframe/backup/).' 'Yellow' }

        # --- fichiers du moteur ---
        $ops = New-Object System.Collections.ArrayList
        $newReg = @{}
        foreach ($k in $regFiles.Keys) { $newReg[$k] = $regFiles[$k] }
        $newNorm = @{}
        foreach ($k in $regNorm.Keys) { $newNorm[$k] = $regNorm[$k] }
        $same = 0; $sameNew = @()
        foreach ($rel in $srcFiles) {
            $sf = Join-Path $root ($rel -replace '/', '\')
            $sh = HashFile $sf
            $shN = HashNormFile $sf
            $d = Dest $rel
            $tracked = $regFiles.ContainsKey($rel)
            if (-not (Test-Path -LiteralPath $d -PathType Leaf)) { [void]$ops.Add(@{ Type = 'add'; Rel = $rel; Src = $sf; Hash = $sh; Norm = $shN }); continue }
            $dh = HashFile $d
            $dhN = HashNormFile $d
            # identique a la source, a CRLF/LF pres : rien a remplacer (octets du projet inchanges)
            if ($dh -eq $sh -or $dhN -eq $shN) {
                $same++; $newReg[$rel] = $dh; $newNorm[$rel] = $shN
                if (-not $tracked) { $pre[$rel] = $true; $sameNew += $rel }
                continue
            }
            if ($tracked) {
                $rh = $regFiles[$rel]
                $unmod = ($dh -eq $rh) -or ($regNorm.ContainsKey($rel) -and ($dhN -eq $regNorm[$rel]))
                $srcSame = ($sh -eq $rh) -or ($regNorm.ContainsKey($rel) -and ($shN -eq $regNorm[$rel]))
                if ($unmod) { [void]$ops.Add(@{ Type = 'replace'; Rel = $rel; Src = $sf; Hash = $sh; Norm = $shN }) }
                elseif ($srcSame) { [void]$ops.Add(@{ Type = 'keep'; Rel = $rel }) }
                else { [void]$ops.Add(@{ Type = 'ask'; Rel = $rel; Src = $sf; Hash = $sh; Norm = $shN }) }
            } else {
                [void]$ops.Add(@{ Type = 'conflict'; Rel = $rel; Src = $sf; Hash = $sh; Norm = $shN })
            }
        }
        foreach ($rel in ($regFiles.Keys | Sort-Object)) {
            if ($srcFiles -contains $rel) { continue }
            $d = Dest $rel
            if (-not (Test-Path -LiteralPath $d -PathType Leaf)) { [void]$newReg.Remove($rel); [void]$newNorm.Remove($rel); [void]$pre.Remove($rel); continue }
            if ($pre.ContainsKey($rel)) { [void]$ops.Add(@{ Type = 'keep-old'; Rel = $rel }); [void]$newReg.Remove($rel); [void]$newNorm.Remove($rel); [void]$pre.Remove($rel) }
            elseif (UnmodReg $rel $d) { [void]$ops.Add(@{ Type = 'remove'; Rel = $rel }) }
            else { [void]$ops.Add(@{ Type = 'keep-old'; Rel = $rel }); [void]$newReg.Remove($rel); [void]$newNorm.Remove($rel) }
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
                    if (($dh -eq $srcEngineHash) -or ((NormText $dp.Engine) -eq (NormText $sp.Engine))) { $cl.Hash = $srcEngineHash }
                    elseif (EngMatch $dp.Engine $regClaudeHash) { $cl.Mode = 'update'; $cl.Text = $sp.Engine + $dp.Project; $cl.Hash = $srcEngineHash }
                    elseif (($srcEngineHash -eq $regClaudeHash) -or (EngMatch $sp.Engine $regClaudeHash)) { $cl.Note = 'CLAUDE.md : la partie bFrame a \u00e9t\u00e9 modifi\u00e9e par vous, gard\u00e9e telle quelle.' }
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
        $srcSetText = ReadText (Join-Path $root '.claude\settings.json')
        $srcSet = $srcSetText | ConvertFrom-Json
        $sd = Dest '.claude/settings.json'
        $st = @{ Mode = 'none'; Text = ''; Note = ''; Agent = $null; Prev = $null; Hooks = @() }
        $regHasAgent = [bool]($reg -and $reg.settings -and $reg.settings.agent)
        $curAgentName = ''
        if (-not (Test-Path -LiteralPath $sd -PathType Leaf)) {
            $m = MergeSettings ([pscustomobject]@{}) $srcSet
            $st.Mode = 'create'; $st.Text = $srcSetText; $st.Agent = $m.Agent; $st.Hooks = $m.Hooks
        } else {
            $cur = ParseSettings (ReadText $sd)
            $whole = $false
            if (-not $cur) {
                if ($regHasAgent) { $st.Mode = 'keep-broken'; $st.Note = '.claude/settings.json est devenu illisible : laiss\u00e9 intact. Corrigez-le puis relancez la commande.' }
                else { $whole = $true; $st.Note = 'illisible (commentaires, virgule de fin ou JSON invalide)' }
            } else {
                $m = MergeSettings $cur $srcSet
                if ($m.Error -and $m.Kind -eq 'agent') {
                    $curAgentName = [string]$cur.agent
                    if ($regHasAgent) { $st.Mode = 'keep-agent'; $st.Note = '.claude/settings.json fixe l''agent "' + $curAgentName + '" (choix fait apr\u00e8s l''installation) : gard\u00e9, bFrame n''est pas l''agent de d\u00e9marrage.' }
                    else {
                        $m2 = MergeSettings $cur $srcSet $true
                        if ($m2.Error) { $whole = $true; $st.Note = 'ne se fusionne pas : ' + $m2.Error }
                        else { $st.Mode = 'replace-agent'; $st.Text = (ToJson $cur) + "`n"; $st.Agent = $m2.Agent; $st.Prev = $m2.Prev; $st.Hooks = $m2.Hooks }
                    }
                } elseif ($m.Error) {
                    if ($regHasAgent) { $st.Mode = 'keep-broken'; $st.Note = '.claude/settings.json laiss\u00e9 intact : ' + $m.Error + '. Corrigez-le puis relancez la commande.' }
                    else { $whole = $true; $st.Note = 'ne se fusionne pas : ' + $m.Error }
                } elseif ((-not $m.Agent) -and @($m.Hooks).Count -eq 0) { $st.Mode = 'none' }
                else { $st.Mode = 'merge'; $st.Text = (ToJson $cur) + "`n"; $st.Agent = $m.Agent; $st.Hooks = $m.Hooks }
            }
            if ($whole) {
                $m = MergeSettings ([pscustomobject]@{}) $srcSet
                $st.Mode = 'replace-all'; $st.Text = $srcSetText; $st.Agent = $m.Agent; $st.Hooks = $m.Hooks
            }
        }
        $setConflict = ($st.Mode -in @('replace-agent', 'replace-all'))

        # --- .gitignore ---
        $gi = PlanGitignore
        $gid = Dest '.gitignore'
        $giCreated = [bool]($reg -and $reg.gitignore -and $reg.gitignore.created) -or ($gi.Mode -eq 'create')

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
        $confOps = @($ops | Where-Object { $_.Type -eq 'conflict' })
        $hasConf = ($confOps.Count -gt 0) -or $setConflict
        Say ''
        Say 'Aper\u00e7u de ce qui serait fait :' 'White'
        Show 'add' 'Fichiers \u00e0 ajouter' 'Gray'
        Show 'replace' 'Fichiers \u00e0 remplacer (non modifi\u00e9s par vous, sauvegard\u00e9s)' 'Gray'
        Show 'remove' 'Fichiers retir\u00e9s de la nouvelle version (non modifi\u00e9s par vous)' 'Gray'
        Show 'ask' 'Modifi\u00e9s par vous ET chang\u00e9s dans la nouvelle version : gard\u00e9s par d\u00e9faut, question ensuite' 'Yellow'
        Show 'keep' 'Modifi\u00e9s par vous, inchang\u00e9s dans la nouvelle version : gard\u00e9s' 'Gray'
        Show 'keep-old' 'Retir\u00e9s de la nouvelle version mais modifi\u00e9s par vous (ou pr\u00e9existants) : gard\u00e9s' 'Gray'
        if ($same -gt 0) { Say ''; Say ('  D\u00e9j\u00e0 en place et identiques : ' + $same + ' (suivis ; ceux qui ne venaient pas de bFrame sont marqu\u00e9s pr\u00e9existants et ne seront pas supprim\u00e9s au retrait)') }
        if ($hasConf) {
            Say ''
            Say '  ATTENTION - REMPLACEMENTS : vos fichiers existants diff\u00e8rent de ceux de bFrame. Un accord distinct vous sera demand\u00e9 ensuite ; chaque original est sauvegard\u00e9 dans .bframe/backup/ :' 'Red'
            foreach ($o in $confOps) { Say ('    ' + $o.Rel + ' : ' + (Implication $o.Rel)) 'Red' }
            if ($st.Mode -eq 'replace-agent') { Say ('    .claude/settings.json : votre agent de d\u00e9marrage "' + $curAgentName + '" sera remplac\u00e9 par "' + $st.Agent + '" ; vos autres r\u00e9glages sont gard\u00e9s ; une copie sera gard\u00e9e') 'Red' }
            if ($st.Mode -eq 'replace-all') { Say ('    .claude/settings.json : ' + $st.Note + ' ; il sera remplac\u00e9 par celui de bFrame ; une copie sera gard\u00e9e, vos r\u00e9glages devront \u00eatre refusionn\u00e9s \u00e0 la main') 'Red' }
        }

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
            'replace-agent' {
                Say '  .claude/settings.json : fusion avec remplacement de l''agent (voir ATTENTION). Ajout\u00e9 :' 'Yellow'
                Say ('    - agent : ' + $st.Agent + ' (remplace "' + $st.Prev + '")')
                foreach ($h in $st.Hooks) { Say ('    - hook ' + ($h -replace '\|', ' : ')) }
            }
            'replace-all' { Say '  .claude/settings.json : remplac\u00e9 en entier (voir ATTENTION).' 'Yellow' }
            'keep-agent' { Say ('  ' + $st.Note) 'Red' }
            'keep-broken' { Say ('  ' + $st.Note) 'Red' }
        }
        switch ($gi.Mode) {
            'create' { Say '  .gitignore : sera cr\u00e9\u00e9, avec ce bloc :' }
            'add' { Say '  .gitignore existe d\u00e9j\u00e0 : vos lignes et leurs fins de ligne sont gard\u00e9es, ce bloc est ajout\u00e9 \u00e0 la fin. Sauvegarde dans .bframe/backup/ :' 'Yellow' }
            'update' {
                Say '  .gitignore : le bloc bFrame actuel ci-dessous (peut-\u00eatre modifi\u00e9 par vous) sera REMPLAC\u00c9 ; le reste est gard\u00e9. Sauvegarde dans .bframe/backup/.' 'Yellow'
                Say '    Bloc actuel :' 'Yellow'
                foreach ($l in ($gi.Old -split "\r?\n")) { if ($l -ne '') { Say ('      | ' + $l) 'Yellow' } }
                Say '    Nouveau bloc :'
            }
        }
        if (@('create', 'add', 'update') -contains $gi.Mode) {
            Say ('    ' + $GiBegin)
            foreach ($l in $GiLines) { Say ('    ' + $l) }
            Say ('    ' + $GiEnd)
            Say '    (ni la m\u00e9moire .bframe/memory/ ni les fichiers .env : ils suivent les r\u00e8gles de votre projet)'
        }
        if ($gi.Note) { Say ('  ' + $gi.Note) 'Yellow' }
        if ($gi.Warn) { Say ('  ' + $gi.Warn) 'Yellow' }
        if ($memDirsToMake.Count + $memFilesToMake.Count -gt 0) {
            Say '  M\u00e9moire du projet (jamais remplac\u00e9e ni supprim\u00e9e) : cr\u00e9ation de ce qui manque, vide :'
            foreach ($x in $memDirsToMake) { Say ('    ' + $x) }
            foreach ($x in $memFilesToMake) { Say ('    ' + $x + ' (index vierge)') }
        }
        Say '  Fichier de suivi : .bframe/install.json (version et empreintes). Rapport : .bframe/install-report.md.'

        $actionable = @($ops | Where-Object { $_.Type -notin @('keep', 'keep-old') }).Count
        if (@('create', 'merge', 'update', 'ask') -contains $cl.Mode) { $actionable++ }
        if (@('create', 'merge', 'replace-agent', 'replace-all') -contains $st.Mode) { $actionable++ }
        if (@('create', 'add', 'update') -contains $gi.Mode) { $actionable++ }
        $actionable += $memDirsToMake.Count + $memFilesToMake.Count
        $needReg = (-not $reg) -or ([string]$reg.version -ne $Version) -or $regRebuilt
        $skipped = @()
        $noop = ($actionable -eq 0 -and -not $needReg)
        if (-not $noop) {
            if ($DryRun) {
                if ($hasConf) { Say ''; Say 'Un accord distinct de remplacement serait demand\u00e9 (-Yes ne le donne pas).' 'Yellow' }
                Say ''; Say 'Mode essai (-DryRun) : rien n''a \u00e9t\u00e9 \u00e9crit.' 'Green'; return 0
            }
            if ($hasConf) {
                if ($Yes) { throw 'Des fichiers ou r\u00e9glages existants diff\u00e8rent de ceux de bFrame : leur remplacement exige votre accord explicite, que -Yes ne donne pas. Relancez la commande sans -Yes. Aucune installation n''a eu lieu : rien n''a \u00e9t\u00e9 \u00e9crit.' }
                Say ''
                if (-not (Ask 'Remplacer les \u00e9l\u00e9ments list\u00e9s en ATTENTION (originaux sauvegard\u00e9s dans .bframe/backup/) ? (oui/non, non par d\u00e9faut) ' $false)) {
                    throw 'Remplacement refus\u00e9 : aucune installation n''a eu lieu. Rien n''a \u00e9t\u00e9 \u00e9crit.'
                }
            }
            Say ''
            if (-not (Ask 'Appliquer ces changements ? (oui/non) ' $true)) { Say 'Rien n''a \u00e9t\u00e9 modifi\u00e9.' 'Yellow'; return 0 }
            $state.Wrote = $true

            # --- etat initial des fichiers qui seront touches (pour un retrait exact) ---
            $orig = (($mode -eq 'install') -and -not $regRebuilt)
            $eCl = Carry $(if ($reg) { $reg.claude_md } else { $null })
            $eSet = Carry $(if ($reg) { $reg.settings } else { $null })
            $eGi = Carry $(if ($reg) { $reg.gitignore } else { $null })
            $eRepl = Carry $(if ($reg) { $reg.replaced } else { $null })
            function SetOrig($e, [string]$rel, [bool]$willWrite) {
                if (-not ($willWrite -and $orig)) { return }
                if ($e.Contains('existed') -or $e.Contains('original_hash')) { return }
                $ex = Test-Path -LiteralPath (Dest $rel) -PathType Leaf
                $e['existed'] = [bool]$ex
                if ($ex) { $e['original_hash'] = HashFile (Dest $rel); $e['backup'] = BkRel $rel }
            }
            SetOrig $eCl 'CLAUDE.md' (@('create', 'merge') -contains $cl.Mode)
            SetOrig $eSet '.claude/settings.json' (@('create', 'merge', 'replace-agent', 'replace-all') -contains $st.Mode)
            SetOrig $eGi '.gitignore' (@('create', 'add') -contains $gi.Mode)

            # --- registre preliminaire : une installation interrompue reste recuperable et retirable ---
            if (@('create', 'merge', 'replace-agent', 'replace-all') -contains $st.Mode) {
                if (-not $eSet.Contains('created')) { $eSet['created'] = ($st.Mode -eq 'create') }
                if (-not $eSet.Contains('agent')) { $eSet['agent'] = $null }
                if ($st.Agent) { $eSet['agent'] = $st.Agent }
                if ($st.Prev -and -not $eSet.Contains('prev_agent')) { $eSet['prev_agent'] = $st.Prev }
                if ($st.Mode -eq 'replace-all') { $eSet['replaced_all'] = $true }
                $eSet['hooks'] = @(@($eSet['hooks']) + @($st.Hooks) | Where-Object { $_ } | Select-Object -Unique)
            }
            if (@('create', 'merge', 'update') -contains $cl.Mode) {
                if (-not $eCl.Contains('engine_hash')) { $eCl['engine_hash'] = '' }
                $eCl['pending_hash'] = $cl.Hash
            }
            if ($gi.Mode -ne 'skip' -and -not $eGi.Contains('created')) { $eGi['created'] = $giCreated }
            if ($regRebuilt) { Backup '.bframe/install.json' }
            $preFiles = [ordered]@{}
            $preAll = @{}
            foreach ($k in $newReg.Keys) { $preAll[$k] = $newReg[$k] }
            foreach ($o in $ops) { if ($o.Type -eq 'add') { $preAll[$o.Rel] = $o.Hash } }
            foreach ($k in ($preAll.Keys | Sort-Object)) { $preFiles[$k] = $preAll[$k] }
            $preVersion = $Version
            if ($reg) { $preVersion = [string]$reg.version }
            $preDoc = [ordered]@{ version = $preVersion; installed = (Get-Date -Format 's'); files = $preFiles; preexisting = @($pre.Keys | Sort-Object) }
            $preNorm = [ordered]@{}
            foreach ($k in ($regNorm.Keys | Sort-Object)) { if ($preFiles.Contains($k)) { $preNorm[$k] = $regNorm[$k] } }
            if ($preNorm.Count -gt 0) { $preDoc.files_norm = $preNorm }
            if ($eRepl.Count -gt 0) { $preDoc.replaced = $eRepl }
            if ($eGi.Count -gt 0) { $preDoc.gitignore = $eGi }
            if ($eCl.Count -gt 0) { $preDoc.claude_md = $eCl }
            if ($eSet.Count -gt 0) { $preDoc.settings = $eSet }
            WriteText $regPath ((ToJson $preDoc) + "`n")

            # --- application ---
            foreach ($o in $ops) {
                switch ($o.Type) {
                    'add' { CopyFile $o.Src (Dest $o.Rel); $newReg[$o.Rel] = $o.Hash; $newNorm[$o.Rel] = $o.Norm }
                    'replace' { Backup $o.Rel; CopyFile $o.Src (Dest $o.Rel); $newReg[$o.Rel] = $o.Hash; $newNorm[$o.Rel] = $o.Norm; $rep.Updated += ($o.Rel + '|' + $bk.Last) }
                    'remove' { Remove-Item -LiteralPath (Dest $o.Rel); CleanDirs $o.Rel; [void]$newReg.Remove($o.Rel); [void]$newNorm.Remove($o.Rel) }
                    'conflict' {
                        Backup $o.Rel; CopyFile $o.Src (Dest $o.Rel); $newReg[$o.Rel] = $o.Hash; $newNorm[$o.Rel] = $o.Norm
                        $eRepl[$o.Rel] = $bk.Last; $rep.Replaced += ($o.Rel + '|' + $bk.Last)
                    }
                    'ask' {
                        if (Ask ('Remplacer ' + $o.Rel + ' par la version de bFrame ? Votre fichier est sauvegard\u00e9. (oui/non, non par d\u00e9faut) ') $false) {
                            Backup $o.Rel; CopyFile $o.Src (Dest $o.Rel); $newReg[$o.Rel] = $o.Hash; $newNorm[$o.Rel] = $o.Norm
                            $eRepl[$o.Rel] = $bk.Last; $rep.Replaced += ($o.Rel + '|' + $bk.Last)
                        } else { $skipped += $o.Rel }
                    }
                }
            }
            $newClaude = $null
            if ($reg -and $reg.claude_md) { $newClaude = [string]$reg.claude_md.engine_hash }
            $wroteCl = $false
            switch ($cl.Mode) {
                'create' { WriteText $cd $cl.Text; $newClaude = $cl.Hash; $wroteCl = $true }
                { $_ -eq 'merge' -or $_ -eq 'update' } { Backup 'CLAUDE.md'; $rep.ClBackup = $bk.Last; WriteText $cd $cl.Text; $newClaude = $cl.Hash; $wroteCl = $true }
                'ask' {
                    if (Ask 'Remplacer la partie bFrame de CLAUDE.md (votre section "# Projet" est gard\u00e9e, sauvegarde faite) ? (oui/non, non par d\u00e9faut) ' $false) {
                        Backup 'CLAUDE.md'; $rep.ClBackup = $bk.Last; WriteText $cd $cl.Text; $newClaude = $cl.Hash; $wroteCl = $true
                    } else { $skipped += 'CLAUDE.md' }
                }
                'none' { if ($cl.Hash) { $newClaude = $cl.Hash } }
            }
            $wroteSet = $false
            if ($st.Mode -eq 'create') { WriteText $sd $st.Text; $wroteSet = $true }
            elseif (@('merge', 'replace-agent', 'replace-all') -contains $st.Mode) {
                Backup '.claude/settings.json'; WriteText $sd $st.Text; $wroteSet = $true
                if ($st.Mode -ne 'merge') { $eRepl['.claude/settings.json'] = $bk.Last; $rep.Replaced += ('.claude/settings.json|' + $bk.Last) }
            }
            $wroteGi = $false
            if (@('add', 'update') -contains $gi.Mode) { Backup '.gitignore' }
            if (@('create', 'add', 'update') -contains $gi.Mode) { GiWrite $gid $gi.Text; $wroteGi = $true }
            foreach ($d in $MemoryDirs) { EnsureDir (Dest ('.bframe/memory/' + $d)) }
            $today = Get-Date -Format 'yyyy-MM-dd'
            foreach ($f in $MemoryModels) {
                $to = Dest ('.bframe/memory/' + $f)
                if (-not (Test-Path -LiteralPath $to)) {
                    $t = ReadText (Join-Path $root ('.bframe\template\memory\' + ($f -replace '/', '\')))
                    WriteText $to ($t.Replace('{{date}}', $today))
                }
            }
            if ($newClaude) { $eCl['engine_hash'] = $newClaude }
            [void]$eCl.Remove('pending_hash')
            if ($wroteCl) { $eCl['result_hash'] = HashFile $cd }
            if ($wroteSet) { $eSet['result_hash'] = HashFile $sd }
            if ($wroteGi) { $eGi['result_hash'] = HashFile $gid }
            $files = [ordered]@{}
            foreach ($k in ($newReg.Keys | Sort-Object)) { $files[$k] = $newReg[$k] }
            $filesN = [ordered]@{}
            foreach ($k in ($newNorm.Keys | Sort-Object)) { if ($files.Contains($k) -and $newNorm[$k]) { $filesN[$k] = $newNorm[$k] } }
            $doc = [ordered]@{ version = $Version; installed = (Get-Date -Format 's'); files = $files; preexisting = @($pre.Keys | Sort-Object) }
            if ($filesN.Count -gt 0) { $doc.files_norm = $filesN }
            if ($eRepl.Count -gt 0) { $doc.replaced = $eRepl }
            if ($eCl.Count -gt 0) { $doc.claude_md = $eCl }
            if ($eSet.Count -gt 0) { $doc.settings = $eSet }
            if ($eGi.Count -gt 0) { $doc.gitignore = $eGi }
            WriteText $regPath ((ToJson $doc) + "`n")
            # Dossier de sauvegarde reste vide : on l'enleve.
            if ($bk.Name -and $bk.Files.Count -eq 0) {
                $bd = Dest ('.bframe/backup/' + $bk.Name)
                if (Test-Path -LiteralPath $bd) { Remove-Item -LiteralPath $bd -Recurse -Force }
                CleanDirs ('.bframe/backup/' + $bk.Name + '/x')
            }
        }

        # --- verification de l'etat reel ---
        $miss = @()
        foreach ($rel in $srcFiles) { if (-not (Test-Path -LiteralPath (Dest $rel) -PathType Leaf)) { $miss += ('fichier absent : ' + $rel) } }
        $sdp = Dest '.claude/settings.json'
        if (-not (Test-Path -LiteralPath $sdp -PathType Leaf)) { $miss += 'fichier absent : .claude/settings.json' }
        else {
            $fc = ParseSettings (ReadText $sdp)
            if (-not $fc) { $miss += '.claude/settings.json est illisible : l''agent et les hooks de bFrame ne sont pas actifs' }
            else {
                $fa = ''
                if ($fc.PSObject.Properties['agent']) { $fa = [string]$fc.agent }
                if ($fa -ne [string]$srcSet.agent) { $miss += ('l''agent de d\u00e9marrage de .claude/settings.json est "' + $fa + '" au lieu de "' + $srcSet.agent + '"') }
                foreach ($ev in $srcSet.hooks.PSObject.Properties) {
                    foreach ($grp in @($ev.Value)) {
                        foreach ($h in @($grp.hooks)) {
                            $found = $false
                            $hp2 = $null
                            if ($fc.PSObject.Properties['hooks'] -and (IsObj $fc.hooks)) { $hp2 = $fc.hooks.PSObject.Properties[$ev.Name] }
                            if ($hp2) { foreach ($eg in @($hp2.Value)) { foreach ($fh2 in @($eg.hooks)) { if ($fh2.command -eq $h.command) { $found = $true } } } }
                            if (-not $found) { $miss += ('hook non d\u00e9clar\u00e9 dans settings.json : ' + $ev.Name + ' : ' + $h.command) }
                        }
                    }
                }
            }
        }
        $crit = @()
        foreach ($o in $ops) { if ($o.Type -eq 'keep' -and ($Critical -contains $o.Rel)) { $crit += $o.Rel } }
        foreach ($s in $skipped) { if ($Critical -contains $s) { $crit += $s } }
        if ($st.Mode -in @('keep-agent', 'keep-broken')) { $crit += '.claude/settings.json' }
        # Un fichier indispensable au verrou, modifie et garde : l'installation n'est pas complete (code de sortie non nul).
        foreach ($c in ($crit | Where-Object { $_ -ne '.claude/settings.json' })) { $miss += ('fichier indispensable au verrou, modifi\u00e9 par vous et gard\u00e9, diff\u00e8re de bFrame : ' + $c) }

        # --- etat de Python ---
        $py = PythonState

        # --- rapport ---
        $localAgent = $null
        # Rien d'autre n'a ete ecrit mais l'etat est incomplet : le rapport deja present est mis a jour (jamais cree sans accord, jamais en -DryRun).
        $refreshRep = (-not $state.Wrote) -and (-not $DryRun) -and ($miss.Count -gt 0) -and (Test-Path -LiteralPath (Dest $ReportRel) -PathType Leaf)
        if ($state.Wrote -or $refreshRep) {
            $L = New-Object System.Collections.ArrayList
            $dt = Get-Date -Format 'yyyy-MM-dd'
            [void]$L.Add('---')
            [void]$L.Add('metadata_version: 1')
            [void]$L.Add('title: "Rapport d''installation bFrame"')
            [void]$L.Add('type: report')
            [void]$L.Add('description: "\u00c9tat constat\u00e9 \u00e0 la fin de l''installation de bFrame, \u00e0 lire par l''onboarding."')
            [void]$L.Add('status: draft')
            [void]$L.Add('created: "' + $dt + '"')
            [void]$L.Add('updated: "' + $dt + '"')
            [void]$L.Add('---')
            [void]$L.Add('')
            [void]$L.Add('# Rapport d''installation bFrame')
            [void]$L.Add('')
            [void]$L.Add('- Version : ' + $Version + ' (' + $mode + ')')
            [void]$L.Add('- Date : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm'))
            if ($miss.Count -eq 0) { [void]$L.Add('- R\u00e9sultat : complet (agent orchestrator actif, fichiers du moteur en place)') }
            else { [void]$L.Add('- R\u00e9sultat : INCOMPLET'); foreach ($x in $miss) { [void]$L.Add('  - manque : ' + $x) } }
            if ($regRebuilt) { [void]$L.Add('- Registre .bframe/install.json : illisible, reconstruit (ancien en sauvegarde)') }
            [void]$L.Add('')
            [void]$L.Add('## CLAUDE.md')
            switch ($cl.Mode) {
                'create' { [void]$L.Add('- Aucun CLAUDE.md existant : celui de bFrame a \u00e9t\u00e9 cr\u00e9\u00e9.') }
                'merge' { [void]$L.Add('- CLAUDE.md existant d\u00e9plac\u00e9 : tout son contenu est dans CLAUDE.md, sous la section "# Projet".'); [void]$L.Add('- Original sauvegard\u00e9 : ' + $rep.ClBackup) }
                'update' { [void]$L.Add('- Partie bFrame mise \u00e0 jour, section "# Projet" conserv\u00e9e. Ancienne version : ' + $rep.ClBackup) }
                'ask' { if ($skipped -contains 'CLAUDE.md') { [void]$L.Add('- Partie bFrame modifi\u00e9e par l''utilisateur : gard\u00e9e telle quelle.') } else { [void]$L.Add('- Partie bFrame remplac\u00e9e, section "# Projet" conserv\u00e9e. Ancienne version : ' + $rep.ClBackup) } }
                default { [void]$L.Add('- Non modifi\u00e9. ' + $cl.Note) }
            }
            if ($rep.ParentClaude.Count -gt 0) { [void]$L.Add('- CLAUDE.md dans un dossier parent : ' + ($rep.ParentClaude -join ', ')) }
            if ($rep.ParentRepo) { [void]$L.Add('- Projet install\u00e9 dans un sous-dossier du d\u00e9p\u00f4t Git ' + $rep.ParentRepo) }
            [void]$L.Add('')
            [void]$L.Add('## Fichiers remplac\u00e9s')
            if ($rep.Replaced.Count -eq 0 -and $rep.Updated.Count -eq 0) { [void]$L.Add('- Aucun.') }
            elseif ($rep.Replaced.Count -eq 0) { [void]$L.Add('- Aucun fichier de l''utilisateur remplac\u00e9 (voir les fichiers du moteur mis \u00e0 jour ci-dessous).') }
            foreach ($x in $rep.Replaced) { $pp = $x.Split('|'); [void]$L.Add('- ' + $pp[0] + ' (sauvegarde : ' + $pp[1] + ')') }
            foreach ($x in $rep.Updated) { $pp = $x.Split('|'); [void]$L.Add('- ' + $pp[0] + ' : mis \u00e0 jour (version pr\u00e9c\u00e9dente du moteur, non modifi\u00e9e par vous ; sauvegarde : ' + $pp[1] + ')') }
            if ($st.Mode -eq 'replace-agent') { [void]$L.Add('- Agent de d\u00e9marrage pr\u00e9c\u00e9dent : "' + $st.Prev + '" (remplac\u00e9 par ' + $st.Agent + ').') }
            if ($st.Mode -eq 'replace-all') { [void]$L.Add('- settings.json \u00e9tait illisible : remplac\u00e9, ses r\u00e9glages d''origine sont \u00e0 refusionner \u00e0 la main depuis la sauvegarde.') }
            if ($skipped.Count -gt 0) { [void]$L.Add('- Gard\u00e9s tels quels (non remplac\u00e9s) : ' + ($skipped -join ', ')) }
            foreach ($c in $crit) { [void]$L.Add('- Fichier indispensable au verrou, modifi\u00e9 par l''utilisateur et gard\u00e9 : ' + $c) }
            [void]$L.Add('')
            [void]$L.Add('## Fichiers trouv\u00e9s dans le projet')
            $det = @()
            foreach ($f in @('.claude/CLAUDE.md', 'AGENTS.md', 'CLAUDE.local.md', '.claude/settings.local.json')) { if (Test-Path -LiteralPath (Dest $f) -PathType Leaf) { $det += $f } }
            if ($det.Count -eq 0) { [void]$L.Add('- Aucun de : .claude/CLAUDE.md, AGENTS.md, CLAUDE.local.md, .claude/settings.local.json.') }
            foreach ($f in $det) { [void]$L.Add('- ' + $f) }
            if ($det -contains '.claude/settings.local.json') {
                $lj = $null
                try { $lj = (ReadText (Dest '.claude/settings.local.json')) | ConvertFrom-Json } catch { $lj = $null }
                if (-not (IsObj $lj)) { [void]$L.Add('- settings.local.json est illisible : on ne sait pas s''il fixe un autre agent.') }
                elseif ($lj.PSObject.Properties['agent']) {
                    $localAgent = [string]$lj.agent
                    if ($localAgent -ne [string]$srcSet.agent) { [void]$L.Add('- settings.local.json fixe un autre agent : "' + $localAgent + '" (il prime sur settings.json).') }
                    else { [void]$L.Add('- settings.local.json fixe le m\u00eame agent (' + $localAgent + ').') }
                } else { [void]$L.Add('- settings.local.json ne fixe pas d''agent.') }
            }
            [void]$L.Add('')
            [void]$L.Add('## Agents, skills, r\u00e8gles, hooks pr\u00e9existants non remplac\u00e9s')
            $own = @()
            foreach ($dn in @('agents', 'skills', 'rules', 'hooks')) {
                $dp2 = Dest ('.claude/' + $dn)
                if (Test-Path -LiteralPath $dp2 -PathType Container) {
                    foreach ($f in (Get-ChildItem -LiteralPath $dp2 -Recurse -File)) {
                        $rel = $f.FullName.Substring($Target.Length).TrimStart('\').Replace('\', '/')
                        if ($rel -match '(^|/)__pycache__/' -or $rel -match '\.pyc$') { continue }
                        if ($srcFiles -notcontains $rel) { $own += $rel }
                    }
                }
            }
            foreach ($o in $ops) { if ($o.Type -eq 'keep' -or ($o.Type -eq 'ask' -and $skipped -contains $o.Rel) -or $o.Type -eq 'keep-old') { $own += ($o.Rel + ' (version de bFrame non appliqu\u00e9e)') } }
            if ($own.Count -eq 0) { [void]$L.Add('- Aucun.') }
            foreach ($x in ($own | Select-Object -First 60)) { [void]$L.Add('- ' + $x) }
            [void]$L.Add('')
            [void]$L.Add('## Serveurs MCP')
            $mp = Dest '.mcp.json'
            if (-not (Test-Path -LiteralPath $mp -PathType Leaf)) { [void]$L.Add('- Pas de .mcp.json.') }
            else {
                $mj = $null
                try { $mj = (ReadText $mp) | ConvertFrom-Json } catch { $mj = $null }
                if (-not (IsObj $mj)) { [void]$L.Add('- .mcp.json pr\u00e9sent mais illisible.') }
                else {
                    $names = @()
                    foreach ($k in @('mcpServers', 'servers')) { if ($mj.PSObject.Properties[$k] -and (IsObj $mj.$k)) { $names += @($mj.$k.PSObject.Properties | ForEach-Object { $_.Name }) } }
                    if ($names.Count -eq 0) { [void]$L.Add('- .mcp.json pr\u00e9sent, aucun serveur d\u00e9clar\u00e9.') }
                    else { [void]$L.Add('- .mcp.json, serveurs d\u00e9clar\u00e9s (noms seulement) : ' + ($names -join ', ')) }
                }
            }
            [void]$L.Add('')
            [void]$L.Add('## Python')
            if ($py.Ok) { [void]$L.Add('- ' + $py.Text) }
            else { [void]$L.Add('- ATTENTION : ' + $py.Text + '. Le verrou d''\u00e9criture et la confirmation des commandes ne fonctionneront pas.') }
            [void]$L.Add('')
            [void]$L.Add('## .gitignore')
            switch ($gi.Mode) {
                'skip' { [void]$L.Add('- Non modifi\u00e9 : ' + $gi.Note) }
                'none' { [void]$L.Add('- D\u00e9j\u00e0 \u00e0 jour, non modifi\u00e9.') }
                'update' { [void]$L.Add('- Bloc bFrame rafra\u00eechi (ancien bloc dans la sauvegarde).') }
                'add' { [void]$L.Add('- Bloc bFrame ajout\u00e9 \u00e0 la fin.') }
                'create' { [void]$L.Add('- Cr\u00e9\u00e9 avec le bloc bFrame.') }
            }
            if ($gi.Warn) { [void]$L.Add('- ' + $gi.Warn) }
            [void]$L.Add('')
            [void]$L.Add('Ce rapport ne contient ni valeur de secret, ni variable d''environnement, ni contenu de .env.')
            WriteText (Dest $ReportRel) ((T ($L -join "`n")) + "`n")
        }

        # --- messages de fin ---
        if ($skipped.Count -gt 0) { Say ('  Gard\u00e9s tels quels (non remplac\u00e9s) : ' + ($skipped -join ', ')) 'Yellow' }
        if ($cl.Mode -eq 'skip') { Say ('  \u00c0 voir : ' + $cl.Note) 'Yellow' }
        if ($gi.Mode -eq 'skip') { Say ('  \u00c0 voir : ' + $gi.Note) 'Yellow' }
        foreach ($c in $crit) { Say ('  ATTENTION : ' + $c + ' est indispensable au verrou et diff\u00e8re de la version de bFrame (modifi\u00e9 par vous, gard\u00e9).') 'Red' }
        if ($localAgent -and $localAgent -ne [string]$srcSet.agent) { Say ('  ATTENTION : .claude/settings.local.json fixe l''agent "' + $localAgent + '" et prime sur settings.json.') 'Red' }
        if (-not $py.Ok) {
            Say ''
            Say '################################################################' 'Red'
            Say ('ATTENTION : ' + $py.Text + '.') 'Red'
            Say 'SANS PYTHON, LE VERROU D''\u00c9CRITURE ET LA CONFIRMATION DES COMMANDES NE FONCTIONNERONT PAS.' 'Red'
            Say 'Installez Python et v\u00e9rifiez que la commande "python" fonctionne.' 'Red'
            Say '################################################################' 'Red'
        }
        if ($miss.Count -gt 0) {
            Say ''
            Say '================================================================' 'Red'
            Say 'INSTALLATION INCOMPL\u00c8TE' 'Red'
            Say '================================================================' 'Red'
            Say 'Ce qui manque :' 'Red'
            foreach ($x in $miss) { Say ('  - ' + $x) 'Red' }
            if ($state.Wrote) { Say '  Les d\u00e9tails sont dans .bframe/install-report.md.' 'Yellow' }
            return 1
        }
        Say ''
        if ($noop) { Say 'Rien \u00e0 faire : bFrame est d\u00e9j\u00e0 \u00e0 jour, sans doublon.' 'Green' }
        else { Say ('bFrame ' + $Version + ' est en place.') 'Green' }
        if ($state.Wrote) { Say '  Rapport : .bframe/install-report.md' }
        Say ''
        Say 'Relancez Claude Code dans ce dossier, puis demandez l''onboarding : il lira .bframe/install-report.md.' 'Cyan'
        $missingRef = @($ReferenceDocs | Where-Object { -not (Test-Path -LiteralPath (Dest ('.bframe/memory/reference/' + $_)) -PathType Leaf) })
        if ($missingRef.Count -gt 0) {
            Say ''
            Say ('Il manque encore dans .bframe/memory/reference/ : ' + ($missingRef -join ', ') + '.') 'Cyan'
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
