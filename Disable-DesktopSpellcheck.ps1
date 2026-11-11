#requires -Version 5.1
<#
.SYNOPSIS
Sets spellcheck.dictionaries to ["xx-XX"] in ChatGPT and Claude Desktop Preferences.

.DESCRIPTION
Changes only the existing spellcheck.dictionaries array. An existing
use_spelling_service value is preserved, and an absent key stays absent.

Run as the Windows user who uses the apps. Save any drafts and fully quit the
apps, including from the system tray if present. Reopen them after the script
finishes. Each changed file gets a dated, byte-for-byte backup next to it.
To undo a change, fully quit the app and copy the reported backup over the
original Preferences file. This restores all preferences from that backup.

.PARAMETER App
Select Both (default), ChatGPT, or Claude.

.EXAMPLE
.\Disable-DesktopSpellcheck.ps1 -WhatIf

.EXAMPLE
.\Disable-DesktopSpellcheck.ps1 -App Claude

.NOTES
Exit codes: 0 = completed, 1 = a file failed or an app must be closed,
2 = no supported Preferences file found for the selected app(s).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Both', 'ChatGPT', 'Claude')]
    [string] $App = 'Both'
)

$ErrorActionPreference = 'Stop'

# Validate the JSON grammar and find the exact value range to replace. A full
# PowerShell JSON round trip can change unrelated keys, numbers, and whitespace.
if (-not ('DesktopSpellcheck.PreferencesJson' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Text.RegularExpressions;

namespace DesktopSpellcheck
{
    public sealed class PreferencesJson
    {
        private static readonly Regex TokenPattern = new Regex(
            @"\G[ \t\r\n]*(?:""(?:[^""\\\x00-\x1F]|\\(?:[""\\/bfnrt]|u[0-9a-fA-F]{4}))*""|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?|true|false|null|[{}\[\],:])");
        private static readonly Regex EndPattern = new Regex(@"\G[ \t\r\n]*\z");
        private readonly string source;
        private int position;
        private int tokenStart;
        private string token;
        private bool foundSpellcheck;
        private bool foundDictionaries;
        private int arrayStart;
        private int arrayEnd;

        public bool IsDisabled { get; private set; }

        public PreferencesJson(string source)
        {
            this.source = source;
            Next();
            ReadObject(0, "spellcheck");
            Require(token == null, "Unexpected content after the root object.");
            Require(foundDictionaries, "Missing spellcheck.dictionaries.");
        }

        public string WithDisabledDictionaries()
        {
            return source.Substring(0, arrayStart) + "[\"xx-XX\"]" + source.Substring(arrayEnd);
        }

        private void Next()
        {
            Match match = TokenPattern.Match(source, position);
            if (!match.Success)
            {
                Require(EndPattern.IsMatch(source, position), "Invalid JSON token.");
                token = null;
                return;
            }
            position = match.Index + match.Length;
            token = match.Value.TrimStart(' ', '\t', '\r', '\n');
            tokenStart = position - token.Length;
        }

        private bool Take(string expected)
        {
            if (token != expected) return false;
            Next();
            return true;
        }

        private void Expect(string expected)
        {
            Require(Take(expected), "Expected JSON token " + expected + ".");
        }

        private bool AtString()
        {
            return token != null && token[0] == '"';
        }

        private string StringValue()
        {
            return Regex.Unescape(token.Substring(1, token.Length - 2));
        }

        private void ReadObject(int depth, string watchedKey)
        {
            Expect("{");
            if (Take("}")) return;
            do
            {
                Require(AtString(), "Expected a JSON property name.");
                bool watched = watchedKey != null && StringValue() == watchedKey;
                Next();
                Expect(":");
                if (watched && watchedKey == "spellcheck")
                {
                    Require(!foundSpellcheck, "Duplicate spellcheck property.");
                    foundSpellcheck = true;
                    ReadObject(depth + 1, "dictionaries");
                }
                else if (watched)
                {
                    Require(!foundDictionaries, "Duplicate spellcheck.dictionaries property.");
                    foundDictionaries = true;
                    ReadDictionaries();
                }
                else
                {
                    ReadValue(depth + 1);
                }
            } while (Take(","));
            Expect("}");
        }

        private void ReadDictionaries()
        {
            arrayStart = tokenStart;
            Require(Take("["), "Expected spellcheck.dictionaries to be an array.");
            int count = 0;
            bool placeholder = false;
            if (token != "]")
            {
                do
                {
                    Require(AtString(), "Expected dictionary names to be strings.");
                    if (count == 0) placeholder = StringValue() == "xx-XX";
                    count++;
                    Next();
                } while (Take(","));
            }
            arrayEnd = tokenStart + 1;
            Expect("]");
            IsDisabled = count == 1 && placeholder;
        }

        private void ReadValue(int depth)
        {
            Require(depth <= 256, "JSON nesting exceeds 256 levels.");
            if (token == "{")
            {
                ReadObject(depth, null);
            }
            else if (Take("["))
            {
                if (Take("]")) return;
                do { ReadValue(depth + 1); } while (Take(","));
                Expect("]");
            }
            else
            {
                Require(token != null && token != "}" && token != "]" &&
                    token != "," && token != ":", "Expected a JSON value.");
                Next();
            }
        }

        private void Require(bool condition, string message)
        {
            if (!condition)
                throw new FormatException(message + " Position: " + position + ".");
        }
    }
}
'@
}

function Assert-RegularPath {
    param([IO.FileSystemInfo] $Item)

    # Reject redirects anywhere in the candidate path, including parent folders.
    if ($item.PSIsContainer) {
        throw 'Expected a Preferences file.'
    }
    while ($null -ne $item) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Path contains a symbolic link or junction: $($item.FullName)"
        }
        if ($item -is [IO.FileInfo]) {
            $item = $item.Directory
        }
        else {
            $item = $item.Parent
        }
    }
}

function Test-AppRunning {
    param([string] $Name)

    # ChatGPT.exe is also the GUI process in the merged OpenAI.Codex package.
    return [bool](Get-Process -Name $Name -ErrorAction SilentlyContinue)
}

if (-not $env:APPDATA -or -not $env:LOCALAPPDATA) {
    throw 'APPDATA and LOCALAPPDATA must be set. Run as the Windows user of the apps.'
}

$packageRoot = Join-Path $env:LOCALAPPDATA 'Packages'
$chatGptPaths = @(
    (Join-Path $packageRoot 'OpenAI.ChatGPT-Desktop_2p2nqsd0c76g0\LocalCache\Roaming\ChatGPT\Preferences')
    (Join-Path $env:APPDATA 'ChatGPT\Preferences')
)
if (Test-Path -LiteralPath (Join-Path $packageRoot 'OpenAI.Codex_2p2nqsd0c76g0') -PathType Container) {
    $chatGptPaths += Join-Path $env:APPDATA 'Codex\web\Codex\Default\Preferences'
}

$claudePaths = foreach ($family in 'Claude_pzs8sxrjxfjjc', 'AnthropicPBC.Claude_fnn82j28hfe8t') {
    Join-Path $env:LOCALAPPDATA "Claude-Data\$family\Preferences"
    Join-Path $packageRoot "$family\LocalCache\Roaming\Claude\Preferences"
}
$claudePaths = @($claudePaths) + @(
    (Join-Path $env:LOCALAPPDATA 'Claude-Data\Preferences')
    (Join-Path $env:APPDATA 'Claude\Preferences')
)

$pathsByApp = @{ ChatGPT = $chatGptPaths; Claude = $claudePaths }
$selectedApps = if ($App -eq 'Both') { 'ChatGPT', 'Claude' } else { $App }
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$foundAny = $false
$hadFailure = $false

foreach ($name in $selectedApps) {
    $foundForApp = $false
    foreach ($path in $pathsByApp[$name]) {
        $tempPath = $null
        $backupPath = $null
        $writeMutex = $null
        $ownsMutex = $false
        try {
            $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        }
        catch [System.Management.Automation.ItemNotFoundException] {
            continue
        }
        catch {
            $foundForApp = $true
            $hadFailure = $true
            Write-Host "[$name] FAILED  $path"
            Write-Host "  $($_.Exception.Message)"
            continue
        }
        $foundForApp = $true
        $foundAny = $true

        try {
            Assert-RegularPath $item
            $original = [IO.File]::ReadAllBytes($path)
            $hasBom = $original.Length -ge 3 -and $original[0] -eq 0xEF -and
                $original[1] -eq 0xBB -and $original[2] -eq 0xBF
            $offset = if ($hasBom) { 3 } else { 0 }
            $source = $utf8.GetString($original, $offset, $original.Length - $offset)
            $preferences = [DesktopSpellcheck.PreferencesJson]::new($source)
            if ($preferences.IsDisabled) {
                Write-Host "[$name] ALREADY SET  $path"
                continue
            }

            $action = 'Back up Preferences and set spellcheck.dictionaries to ["xx-XX"]'
            if (-not $PSCmdlet.ShouldProcess($path, $action)) {
                $status = if ($WhatIfPreference) { 'WOULD UPDATE' } else { 'SKIPPED' }
                Write-Host "[$name] $status  $path"
                if (Test-AppRunning $name) {
                    Write-Host "  Quit $name completely before applying."
                }
                continue
            }
            if (Test-AppRunning $name) {
                Write-Host "[$name] RUNNING  $path"
                Write-Host "  Quit $name completely, then run the script again."
                $hadFailure = $true
                continue
            }

            $userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
            $writeMutex = [Threading.Mutex]::new($false, "Global\DesktopSpellcheck-$userSid")
            try {
                $ownsMutex = $writeMutex.WaitOne(0)
            }
            catch [Threading.AbandonedMutexException] {
                $ownsMutex = $true
            }
            if (-not $ownsMutex) {
                throw 'Another copy of the script is updating Preferences. Run again when it finishes.'
            }

            $updated = $preferences.WithDisabledDictionaries()
            if (-not [DesktopSpellcheck.PreferencesJson]::new($updated).IsDisabled) {
                throw 'The updated JSON did not pass verification.'
            }
            $encoding = if ($hasBom) { [Text.UTF8Encoding]::new($true, $true) } else { $utf8 }
            $tempPath = "$path.spellcheck.$([Guid]::NewGuid().ToString('N')).tmp"
            [IO.File]::WriteAllText($tempPath, $updated, $encoding)

            Assert-RegularPath (Get-Item -LiteralPath $path -Force)
            $current = [IO.File]::ReadAllBytes($path)
            if ([Convert]::ToBase64String($current) -cne [Convert]::ToBase64String($original)) {
                throw 'Preferences changed during this run. Close the app and retry.'
            }
            if (Test-AppRunning $name) {
                throw "$name started during this run. Quit it completely and retry."
            }

            $timestamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ', [Globalization.CultureInfo]::InvariantCulture)
            $backupPath = "$path.spellcheck.$timestamp.$([Guid]::NewGuid().ToString('N')).bak"
            [IO.File]::Replace($tempPath, $path, $backupPath)
            if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($backupPath)) -cne
                [Convert]::ToBase64String($original)) {
                throw 'The backup differs from the file first read. Preferences changed during the update.'
            }
            $written = [IO.File]::ReadAllText($path, $utf8)
            if ($written -cne $updated) {
                throw 'The saved Preferences differ from the verified JSON.'
            }
            Write-Host "[$name] UPDATED  $path"
            Write-Host "  Backup: $backupPath"
        }
        catch {
            $hadFailure = $true
            Write-Host "[$name] FAILED  $path"
            Write-Host "  $($_.Exception.GetBaseException().Message)"
            if ($backupPath -and [IO.File]::Exists($backupPath)) {
                Write-Host "  Backup: $backupPath"
            }
        }
        finally {
            if ($ownsMutex) {
                $writeMutex.ReleaseMutex()
            }
            if ($null -ne $writeMutex) {
                $writeMutex.Dispose()
            }
            if ($tempPath -and [IO.File]::Exists($tempPath)) {
                try {
                    [IO.File]::Delete($tempPath)
                }
                catch {
                    $hadFailure = $true
                    Write-Warning "Could not remove temporary file: $tempPath"
                }
            }
        }
    }
    if (-not $foundForApp) {
        Write-Host "[$name] NOT FOUND  No supported Preferences file was found."
    }
}

if ($hadFailure) { exit 1 }
if (-not $foundAny) { exit 2 }
exit 0
