# ===========================================================================
#  switch-php - switch between side-by-side PHP versions on Windows
#  https://github.com/samiulislamsharan/php-switch
#
#  install.ps1 puts this file in ~\.php-switch and loads it from your profile.
#
#    switch-php                 pick a version from a list
#    switch-php 8.3             switch this terminal to the newest 8.3.x
#    switch-php 8.3 -Persist    ...and make it the default for new terminals
#    switch-php -List           show installed versions and which one is active
#    Set-PhpBasePath            change the folder that holds your PHP versions
#    Restore-PhpUserPath        undo the last -Persist
#    Update-PhpSwitch           download the latest version of this script
#    Uninstall-PhpSwitch        remove php-switch
# ===========================================================================

$Global:PhpSwitchHome      = Join-Path $HOME '.php-switch'
$Global:PhpSwitchSourceUrl = 'https://raw.githubusercontent.com/samiulislamsharan/php-switch/main/switch-php.ps1'

# Lines added to your PowerShell profile by install.ps1
$Global:PhpSwitchProfileBlock = @'
# >>> php-switch >>>
if (Test-Path "$HOME\.php-switch\switch-php.ps1") { . "$HOME\.php-switch\switch-php.ps1" }
# <<< php-switch <<<
'@

# ---------------------------------------------------------------------------
#  Finding PHP
# ---------------------------------------------------------------------------

function Get-PhpInstall {
    <#
    .SYNOPSIS
        Lists the PHP versions in your PHP folder, newest first.
    #>
    [CmdletBinding()]
    param(
        [string]$BasePath = $env:PHP_BASE_PATH
    )

    if (-not $BasePath -or -not (Test-Path -LiteralPath $BasePath -PathType Container)) { return }

    $activeExe  = Get-Command php.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $activeDir  = if ($activeExe) { Split-Path -Parent $activeExe.Source }
    $defaultDir = Get-PhpDefaultDir

    Get-ChildItem -LiteralPath $BasePath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -match '^php-(?<ver>\d+(?:\.\d+){1,3})(?!\d)' -and
            (Test-Path -LiteralPath (Join-Path $_.FullName 'php.exe'))) {
            [pscustomobject]@{
                Version = [version]$Matches.ver
                Name    = $_.Name
                Path    = $_.FullName
                Active  = ($_.FullName -eq $activeDir)
                Default = ($_.FullName -eq $defaultDir)
            }
        }
    } | Sort-Object Version -Descending
}

# The folder new terminals will get php.exe from (System PATH first, then user PATH).
function Get-PhpDefaultDir {
    $entries = (@(
        [Environment]::GetEnvironmentVariable('Path', 'Machine'),
        [Environment]::GetEnvironmentVariable('Path', 'User')
    ) -join ';') -split ';'

    foreach ($entry in $entries) {
        if (-not $entry -or -not $entry.Trim()) { continue }
        try {
            $dir = [Environment]::ExpandEnvironmentVariables($entry.Trim().Trim('"')).TrimEnd('\')
            if ([IO.File]::Exists([IO.Path]::Combine($dir, 'php.exe'))) { return $dir }
        }
        catch { }
    }
}

# Looks in the usual places on every local drive.
function Find-PhpBasePath {
    $candidates = @()
    if ($env:PHP_BASE_PATH) { $candidates += $env:PHP_BASE_PATH }

    $drives = [IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady }
    foreach ($drive in $drives) {
        $root = $drive.RootDirectory.FullName
        $candidates += Join-Path $root 'laragon\bin\php'
        $candidates += Join-Path $root 'php'
        $candidates += Join-Path $root 'tools\php'
    }

    $seen = @{}
    foreach ($path in $candidates) {
        if ($seen.ContainsKey($path.ToLower())) { continue }
        $seen[$path.ToLower()] = $true
        $installs = @(Get-PhpInstall -BasePath $path)
        if ($installs.Count) {
            [pscustomobject]@{ Path = $path; Versions = $installs.Version }
        }
    }
}

function Set-PhpBasePath {
    <#
    .SYNOPSIS
        Sets the folder that holds your php-x.y.z folders. Run without a path to detect it.
    .EXAMPLE
        Set-PhpBasePath
    .EXAMPLE
        Set-PhpBasePath 'C:\laragon\bin\php'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Path
    )

    if (-not $Path) {
        $found = @(Find-PhpBasePath)
        if (-not $found.Count) {
            Write-Error "Couldn't find any PHP versions. Run: Set-PhpBasePath 'C:\path\to\your\php\folders'"
            return
        }
        if ($found.Count -eq 1) {
            $Path = $found[0].Path
        }
        else {
            $labels = $found | ForEach-Object { Format-PhpBasePath $_ }
            $choice = Read-PhpSwitchChoice -Title 'PHP versions were found in more than one folder:' -Labels $labels -Default 1
            if ($choice -lt 0) { return }
            $Path = $found[$choice].Path
        }
    }

    $Path = $Path.Trim().Trim('"')
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Error "Folder not found: $Path"
        return
    }
    $Path = (Resolve-Path -LiteralPath $Path).ProviderPath
    if ($Path.Length -gt 3) { $Path = $Path.TrimEnd('\') }

    $installs = @(Get-PhpInstall -BasePath $Path)
    if (-not $installs.Count) {
        Write-Error "No PHP versions in $Path. Expected folders like php-8.3.14-Win32-vs16-x64 with php.exe inside."
        return
    }

    [Environment]::SetEnvironmentVariable('PHP_BASE_PATH', $Path, 'User')
    $env:PHP_BASE_PATH = $Path
    Write-Host ("PHP folder set to {0}  (PHP {1})" -f $Path, (($installs | ForEach-Object { "$($_.Version)" }) -join ', ')) -ForegroundColor Green
}

# ---------------------------------------------------------------------------
#  Display helpers
# ---------------------------------------------------------------------------

function Format-PhpInstall {
    param($Install)
    $tags = @()
    if ($Install.Active)  { $tags += 'this terminal' }
    if ($Install.Default) { $tags += 'default' }
    $line = '{0,-10} {1}' -f "$($Install.Version)", $Install.Name
    if ($tags.Count) { $line += '   (' + ($tags -join ', ') + ')' }
    $line
}

function Format-PhpBasePath {
    param($Found)
    '{0}   (PHP {1})' -f $Found.Path, (($Found.Versions | ForEach-Object { "$_" }) -join ', ')
}

# Shows a numbered list and returns the 0-based index picked, or -1 to cancel.
function Read-PhpSwitchChoice {
    param(
        [string]$Title,
        [string[]]$Labels,
        [int]$Default = 0     # 1-based; 0 = Enter cancels
    )

    if ($Title) { Write-Host $Title }
    for ($i = 0; $i -lt $Labels.Count; $i++) {
        Write-Host ('  {0,2}) {1}' -f ($i + 1), $Labels[$i])
    }

    $hint = if ($Default) { "1-$($Labels.Count), Enter = $Default, q = cancel" } else { "1-$($Labels.Count), Enter = cancel" }
    while ($true) {
        $answer = "$(Read-Host "Choose ($hint)")".Trim()
        if (-not $answer) { return ($Default - 1) }
        if ($answer -eq 'q') { return -1 }
        $n = 0
        if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $Labels.Count) { return ($n - 1) }
        Write-Host "  Please type a number from 1 to $($Labels.Count)." -ForegroundColor Yellow
    }
}

function Show-PhpStatus {
    param([string]$BasePath = $env:PHP_BASE_PATH)

    $installs = @(Get-PhpInstall -BasePath $BasePath)
    $active   = Get-Command php.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $default  = Get-PhpDefaultDir

    Write-Host ''
    Write-Host ('  PHP folder:     {0}' -f $BasePath)
    Write-Host ('  This terminal:  {0}' -f $(if ($active) { $active.Source } else { '(no php on PATH)' }))
    Write-Host ('  New terminals:  {0}' -f $(if ($default) { Join-Path $default 'php.exe' } else { '(no php on PATH)' }))
    Write-Host ''
    foreach ($p in $installs) {
        $mark  = if ($p.Active) { '*' } else { ' ' }
        $color = if ($p.Active) { 'Green' } else { 'Gray' }
        Write-Host ('  {0} {1}' -f $mark, (Format-PhpInstall $p)) -ForegroundColor $color
    }
    Write-Host ''
}

# ---------------------------------------------------------------------------
#  Switching
# ---------------------------------------------------------------------------

function Switch-PhpVersion {
    <#
    .SYNOPSIS
        Switches PHP in this terminal, and optionally in every new terminal.
    .DESCRIPTION
        Run without a version to pick one from a list.
        "8.3" picks the newest installed 8.3.x; "8" picks the newest 8.x.
    .EXAMPLE
        switch-php
    .EXAMPLE
        switch-php 8.3
    .EXAMPLE
        switch-php 8.3 -Persist
    .EXAMPLE
        switch-php -List
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)]
        [string]$Version,

        # Also make this the default for new terminals (updates your user PATH)
        [Alias('Global')]
        [switch]$Persist,

        # Show installed versions and which one is active
        [switch]$List,

        [string]$BasePath = $env:PHP_BASE_PATH,

        # Return the selected version as an object
        [switch]$PassThru
    )

    if (-not $BasePath) {
        Write-Host "switch-php doesn't know where your PHP versions are yet." -ForegroundColor Yellow
        Write-Host "Run Set-PhpBasePath to find them, or Set-PhpBasePath 'C:\laragon\bin\php'."
        return
    }

    $installs = @(Get-PhpInstall -BasePath $BasePath)
    if (-not $installs.Count) {
        Write-Error ("No PHP versions found in $BasePath. Expected folders like php-8.3.14-Win32-vs16-x64 " +
            "with php.exe inside. Run Set-PhpBasePath to choose another folder.")
        return
    }

    if ($List) {
        Show-PhpStatus -BasePath $BasePath
        return
    }

    if ($Version) {
        $Version = $Version.Trim() -replace '^(php-?|v)', ''
        $target = $installs | Where-Object {
            $v = $_.Version.ToString()
            $v -eq $Version -or $v.StartsWith("$Version.")
        } | Select-Object -First 1   # newest first

        if (-not $target) {
            $available = ($installs | ForEach-Object { "$($_.Version)" }) -join ', '
            Write-Error "PHP $Version isn't installed in $BasePath. Installed: $available"
            return
        }
    }
    elseif ([Environment]::UserInteractive) {
        $labels = $installs | ForEach-Object { Format-PhpInstall $_ }
        $choice = Read-PhpSwitchChoice -Title "PHP versions in ${BasePath}:" -Labels $labels
        if ($choice -lt 0) { return }
        $target = $installs[$choice]
    }
    else {
        Show-PhpStatus -BasePath $BasePath
        return
    }

    $doSession = $PSCmdlet.ShouldProcess('This terminal', "Switch to PHP $($target.Version)")
    $doPersist = $Persist -and $PSCmdlet.ShouldProcess('New terminals (user PATH and PHPRC)', "Make PHP $($target.Version) the default")

    if ($doSession) {
        $env:PATH  = Update-PhpPathValue -PathValue $env:PATH -BasePath $BasePath -PhpPath $target.Path
        # A PHPRC set elsewhere would make this php.exe load another version's php.ini
        $env:PHPRC = $target.Path

        $php = Join-Path $target.Path 'php.exe'
        Write-Host "PHP $($target.Version) is now active in this terminal" -ForegroundColor Green
        & $php -v 2>$null | Select-Object -First 1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }

        $iniLine = & $php --ini 2>$null | Select-String 'Loaded Configuration File:\s*(.+)$'
        $iniPath = if ($iniLine) { $iniLine.Matches[0].Groups[1].Value.Trim() } else { '(unknown)' }
        if ($iniPath -eq '(none)') {
            Write-Warning "No php.ini loaded. Copy php.ini-development to php.ini in $($target.Path)."
        }
        else {
            Write-Host "  php.ini: $iniPath" -ForegroundColor DarkGray
        }
    }

    if ($doPersist) {
        Set-PhpUserEnvironment -BasePath $BasePath -PhpPath $target.Path -Version $target.Version
    }
    elseif ($doSession -and -not $Persist -and -not $target.Default) {
        Write-Host "  Tip: add -Persist to use this version in new terminals too." -ForegroundColor DarkGray
    }

    if ($PassThru) { $target }
}

# ---------------------------------------------------------------------------
#  PATH handling
# ---------------------------------------------------------------------------

# Removes every entry under $BasePath (anchored, so D:\PhpStorm etc. survive),
# drops empty entries, and puts $PhpPath first.
function Update-PhpPathValue {
    param([string]$PathValue, [string]$BasePath, [string]$PhpPath)
    $prefix = $BasePath.TrimEnd('\') + '\'
    $rest = $PathValue -split ';' | Where-Object {
        $_ -and -not $_.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
    }
    (@($PhpPath) + $rest) -join ';'
}

# Tells Explorer and other apps that environment variables changed,
# so terminals opened from now on see the new values.
function Send-EnvironmentChange {
    if (-not ('Win32.PhpSwitchEnvBroadcast' -as [type])) {
        Add-Type -Namespace Win32 -Name PhpSwitchEnvBroadcast -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam,
    string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }
    $result = [UIntPtr]::Zero
    # HWND_BROADCAST = 0xffff, WM_SETTINGCHANGE = 0x1A, SMTO_ABORTIFHUNG = 2
    [void][Win32.PhpSwitchEnvBroadcast]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero,
        'Environment', 2, 5000, [ref]$result)
}

function Open-UserEnvironmentKey {
    [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
}

# Writes the chosen PHP into HKCU\Environment (user PATH + PHPRC). No admin needed.
function Set-PhpUserEnvironment {
    param([string]$BasePath, [string]$PhpPath, [version]$Version)

    $backupDir = Join-Path $Global:PhpSwitchHome 'backups'
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

    $key = Open-UserEnvironmentKey
    try {
        # Read the raw value so entries like %USERPROFILE%\bin stay unexpanded
        $old = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

        # The first backup is kept forever; the rest are an undo history
        $original = Join-Path $backupDir 'original-path.txt'
        if (-not (Test-Path -LiteralPath $original)) { [IO.File]::WriteAllText($original, $old) }
        [IO.File]::WriteAllText((Join-Path $backupDir ('path-{0:yyyyMMdd-HHmmss}.txt' -f (Get-Date))), $old)

        $new = Update-PhpPathValue -PathValue $old -BasePath $BasePath -PhpPath $PhpPath
        $key.SetValue('Path', $new, [Microsoft.Win32.RegistryValueKind]::ExpandString)
        $key.SetValue('PHPRC', $PhpPath, [Microsoft.Win32.RegistryValueKind]::String)
    }
    finally {
        $key.Close()
    }

    # Keep the 20 most recent undo backups
    Get-ChildItem -LiteralPath $backupDir -Filter 'path-*.txt' |
        Sort-Object Name -Descending | Select-Object -Skip 20 |
        Remove-Item -Force -ErrorAction SilentlyContinue

    Send-EnvironmentChange

    $default = Get-PhpDefaultDir
    if ($default -and $default -ne $PhpPath) {
        Write-Warning ("New terminals will still use $default\php.exe because it's on the System PATH, " +
            'which Windows checks before your user PATH. Remove it from the System PATH (needs admin).')
    }
    else {
        Write-Host "PHP $Version is now the default for new terminals" -ForegroundColor Green
        Write-Host '  Already-open terminals and editors keep their old PATH until restarted.' -ForegroundColor DarkGray
    }
}

function Restore-PhpUserPath {
    <#
    .SYNOPSIS
        Puts your user PATH back the way it was before the last -Persist.
    .PARAMETER Original
        Restore the PATH from before php-switch first changed it.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([switch]$Original)

    $backupDir = Join-Path $Global:PhpSwitchHome 'backups'
    $backup = if ($Original) {
        Get-Item -LiteralPath (Join-Path $backupDir 'original-path.txt') -ErrorAction SilentlyContinue
    }
    else {
        Get-ChildItem -LiteralPath $backupDir -Filter 'path-*.txt' -ErrorAction SilentlyContinue |
            Sort-Object Name | Select-Object -Last 1
    }

    if (-not $backup) {
        Write-Error "No PATH backup found in $backupDir. php-switch hasn't changed your user PATH."
        return
    }
    if (-not $PSCmdlet.ShouldProcess('User PATH', "Restore from $($backup.FullName)")) { return }

    $old = [IO.File]::ReadAllText($backup.FullName)
    $key = Open-UserEnvironmentKey
    try {
        $key.SetValue('Path', $old, [Microsoft.Win32.RegistryValueKind]::ExpandString)
        $key.DeleteValue('PHPRC', $false)
    }
    finally {
        $key.Close()
    }
    Send-EnvironmentChange
    Write-Host "Restored your user PATH from $($backup.Name). New terminals will use it." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
#  Install, update, uninstall
# ---------------------------------------------------------------------------

function Get-PhpSwitchProfileTarget {
    $docs = [Environment]::GetFolderPath('MyDocuments')
    [pscustomobject]@{ Name = 'Windows PowerShell'; Exe = 'powershell.exe'; ProfilePath = Join-Path $docs 'WindowsPowerShell\profile.ps1' }
    [pscustomobject]@{ Name = 'PowerShell 7';       Exe = 'pwsh.exe';       ProfilePath = Join-Path $docs 'PowerShell\profile.ps1' }
}

# Returns $true if the block was added, $false if it was already there.
function Add-PhpSwitchProfileBlock {
    param([string]$Path)
    $text = if (Test-Path -LiteralPath $Path) { [IO.File]::ReadAllText($Path) } else { '' }
    if ($text.Contains('# >>> php-switch >>>')) { return $false }

    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    $lead  = if ($text -and -not $text.EndsWith("`n")) { "`r`n" } else { '' }
    $block = ($Global:PhpSwitchProfileBlock -replace "`r?`n", "`r`n") + "`r`n"
    [IO.File]::AppendAllText($Path, $lead + $block)
    return $true
}

# Returns $true if a block was removed.
function Remove-PhpSwitchProfileBlock {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $text = [IO.File]::ReadAllText($Path)
    $new  = [regex]::Replace($text, '(?ms)^# >>> php-switch >>>.*?^# <<< php-switch <<<[^\n]*\n?', '')
    if ($new -eq $text) { return $false }
    [IO.File]::WriteAllText($Path, $new, (New-Object System.Text.UTF8Encoding $true))
    return $true
}

function Update-PhpSwitch {
    <#
    .SYNOPSIS
        Downloads the latest switch-php.ps1.
    #>
    [CmdletBinding()]
    param()

    $dest = Join-Path $Global:PhpSwitchHome 'switch-php.ps1'
    $tmp  = Join-Path ([IO.Path]::GetTempPath()) ('switch-php-{0}.ps1' -f [guid]::NewGuid())
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Global:PhpSwitchSourceUrl -OutFile $tmp -UseBasicParsing -ErrorAction Stop

        $tokens = $null; $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($tmp, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors -or -not (Select-String -LiteralPath $tmp -Pattern 'function Switch-PhpVersion' -SimpleMatch -Quiet)) {
            throw "the downloaded file isn't a valid switch-php.ps1"
        }

        New-Item -ItemType Directory -Path $Global:PhpSwitchHome -Force | Out-Null
        Copy-Item -LiteralPath $tmp -Destination $dest -Force -ErrorAction Stop
        Unblock-File -LiteralPath $dest -ErrorAction SilentlyContinue
        Write-Host 'switch-php updated. Open a new terminal to use the new version.' -ForegroundColor Green
    }
    catch {
        Write-Error "Update failed: $($_.Exception.Message)"
    }
    finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Uninstall-PhpSwitch {
    <#
    .SYNOPSIS
        Removes php-switch from your profiles and deletes the script.
    .PARAMETER RestorePath
        Also put your user PATH back the way it was before php-switch first changed it.
    #>
    [CmdletBinding()]
    param([switch]$RestorePath)

    $backupDir = Join-Path $Global:PhpSwitchHome 'backups'
    if ($RestorePath) {
        if (Test-Path -LiteralPath (Join-Path $backupDir 'original-path.txt')) {
            Restore-PhpUserPath -Original -Confirm:$false
        }
        else {
            Write-Host "php-switch never changed your user PATH, so there's nothing to restore."
        }
    }

    foreach ($target in Get-PhpSwitchProfileTarget) {
        if (Remove-PhpSwitchProfileBlock -Path $target.ProfilePath) {
            Write-Host "Removed from your $($target.Name) profile"
        }
    }

    [Environment]::SetEnvironmentVariable('PHP_BASE_PATH', $null, 'User')
    Remove-Item -LiteralPath (Join-Path $Global:PhpSwitchHome 'switch-php.ps1') -Force -ErrorAction SilentlyContinue

    if (Test-Path -LiteralPath $backupDir) {
        if (-not $RestorePath) {
            Write-Host 'Your user PATH was left as it is, so your current default PHP stays.'
        }
        Write-Host "PATH backups are kept in $backupDir"
    }
    elseif ((Test-Path -LiteralPath $Global:PhpSwitchHome) -and -not (Get-ChildItem -LiteralPath $Global:PhpSwitchHome -Force)) {
        Remove-Item -LiteralPath $Global:PhpSwitchHome -Force
    }

    Write-Host 'php-switch is uninstalled. Open a new terminal to finish.' -ForegroundColor Green
}

# ---------------------------------------------------------------------------
#  Alias and tab completion
# ---------------------------------------------------------------------------

Set-Alias -Name switch-php -Value Switch-PhpVersion

# switch-php <Tab> cycles through installed versions
Register-ArgumentCompleter -CommandName Switch-PhpVersion, switch-php -ParameterName Version -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $base = if ($fakeBoundParameters.BasePath) { $fakeBoundParameters.BasePath } else { $env:PHP_BASE_PATH }
    Get-PhpInstall -BasePath $base |
        ForEach-Object { "$($_.Version.Major).$($_.Version.Minor)"; "$($_.Version)" } |
        Select-Object -Unique |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}
