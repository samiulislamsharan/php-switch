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
#    install-php 8.4            download the newest 8.4.x from windows.php.net
#    install-php -List          show versions you can download
#    remove-php 8.1             remove an installed version (to the Recycle Bin)
#    Set-PhpBasePath            change the folder that holds your PHP versions
#    Restore-PhpUserPath        undo the last -Persist
#    Update-PhpSwitch           download the latest version of this script
#    Uninstall-PhpSwitch        remove php-switch
# ===========================================================================

$Global:PhpSwitchHome      = Join-Path $HOME '.php-switch'
$Global:PhpSwitchSourceUrl = 'https://raw.githubusercontent.com/samiulislamsharan/php-switch/main/switch-php.ps1'

# Official PHP for Windows builds
$Global:PhpSwitchDownloadBase = 'https://downloads.php.net/~windows/releases'

# Extensions install-php turns on in php.ini (what Laravel and Composer usually need)
$Global:PhpSwitchDefaultExtensions = @('curl', 'fileinfo', 'gd', 'intl', 'mbstring', 'openssl', 'pdo_mysql', 'pdo_sqlite', 'sqlite3', 'zip')

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
    $candidates += Get-PhpSwitchDefaultBasePath

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

# Where install-php puts PHP when no PHP folder is set yet (no admin needed)
function Get-PhpSwitchDefaultBasePath {
    Join-Path $env:LOCALAPPDATA 'Programs\php'
}

function Set-PhpBasePath {
    <#
    .SYNOPSIS
        Sets the folder that holds your php-x.y.z folders. Run without a path to detect it.
    .EXAMPLE
        Set-PhpBasePath
    .EXAMPLE
        Set-PhpBasePath 'C:\laragon\bin\php'
    .EXAMPLE
        Set-PhpBasePath 'D:\php' -Create     # new, empty folder for install-php
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Path,

        # Create the folder if it doesn't exist
        [switch]$Create
    )

    if (-not $Path) {
        $found = @(Find-PhpBasePath)
        if (-not $found.Count) {
            Write-Error ("Couldn't find any PHP versions. Point to your folder with Set-PhpBasePath 'C:\path\to\php', " +
                'or download PHP with install-php 8.4.')
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
        if (-not $Create) {
            Write-Error "Folder not found: $Path (add -Create to make it)"
            return
        }
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
    $Path = (Resolve-Path -LiteralPath $Path).ProviderPath
    if ($Path.Length -gt 3) { $Path = $Path.TrimEnd('\') }

    [Environment]::SetEnvironmentVariable('PHP_BASE_PATH', $Path, 'User')
    $env:PHP_BASE_PATH = $Path

    $installs = @(Get-PhpInstall -BasePath $Path)
    if ($installs.Count) {
        Write-Host ("PHP folder set to {0}  (PHP {1})" -f $Path, (($installs | ForEach-Object { "$($_.Version)" }) -join ', ')) -ForegroundColor Green
    }
    else {
        Write-Host "PHP folder set to $Path (no PHP versions in it yet - add one with install-php 8.4)" -ForegroundColor Green
    }
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
        Write-Host "Run Set-PhpBasePath to find them, Set-PhpBasePath 'C:\laragon\bin\php' to set the folder,"
        Write-Host 'or install-php 8.4 to download PHP.'
        return
    }

    $installs = @(Get-PhpInstall -BasePath $BasePath)
    if (-not $installs.Count) {
        Write-Error ("No PHP versions found in $BasePath. Download one with install-php 8.4, " +
            'or run Set-PhpBasePath to choose another folder.')
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
#  Downloading PHP (install-php) and removing it (remove-php)
# ---------------------------------------------------------------------------

function Enable-PhpSwitchTls {
    # Windows PowerShell 5.1 may not have TLS 1.2 turned on
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

# releases.json lists the newest release of each branch, with SHA-256 checksums.
# Cached for an hour so tab completion stays fast.
function Get-PhpReleaseFeed {
    $cache = $Global:PhpSwitchFeedCache
    if ($cache -and ((Get-Date) - $cache.Time).TotalMinutes -lt 60) { return $cache.Data }
    Enable-PhpSwitchTls
    $data = Invoke-RestMethod -Uri "$Global:PhpSwitchDownloadBase/releases.json" -UseBasicParsing -ErrorAction Stop
    $Global:PhpSwitchFeedCache = @{ Time = Get-Date; Data = $data }
    $data
}

# Older releases live in archives/ (no checksums published there).
function Get-PhpArchive {
    $cache = $Global:PhpSwitchArchiveCache
    if ($cache -and ((Get-Date) - $cache.Time).TotalMinutes -lt 60) { return $cache.Data }
    Enable-PhpSwitchTls
    $html = (Invoke-WebRequest -Uri "$Global:PhpSwitchDownloadBase/archives/" -UseBasicParsing -ErrorAction Stop).Content
    $seen = @{}
    $data = @(foreach ($m in [regex]::Matches($html, 'php-\d+\.\d+\.\d+(?:-nts)?-Win32-v[cs]\d+-x(?:64|86)\.zip')) {
        if ($seen.ContainsKey($m.Value)) { continue }
        $seen[$m.Value] = $true
        ConvertTo-PhpBuild -File $m.Value -Url "$Global:PhpSwitchDownloadBase/archives/$($m.Value)"
    })
    $Global:PhpSwitchArchiveCache = @{ Time = Get-Date; Data = $data }
    $data
}

function ConvertTo-PhpBuild {
    param([string]$File, [string]$Url, [string]$Sha256, [string]$Size)
    if ($File -match '^php-(?<ver>\d+\.\d+\.\d+)(?<nts>-nts)?-Win32-(?<vc>v[cs]\d+)-(?<arch>x64|x86)\.zip$') {
        [pscustomobject]@{
            Version    = [version]$Matches.ver
            ThreadSafe = -not $Matches.nts
            Arch       = $Matches.arch
            Compiler   = $Matches.vc
            File       = $File
            Folder     = $File -replace '\.zip$', ''
            Url        = $Url
            Sha256     = $Sha256
            Size       = $Size
        }
    }
}

function Get-PhpAvailable {
    <#
    .SYNOPSIS
        Lists PHP builds you can download from windows.php.net, newest first.
    .PARAMETER All
        Include older patch releases, not just the newest of each branch.
    #>
    [CmdletBinding()]
    param(
        [switch]$All,
        [switch]$ThreadSafe,
        [ValidateSet('x64', 'x86')]
        [string]$Arch = 'x64'
    )

    $builds = @()
    $feed = Get-PhpReleaseFeed
    foreach ($branch in $feed.PSObject.Properties) {
        foreach ($build in $branch.Value.PSObject.Properties) {
            if ($build.Name -notmatch '^(nts|ts)-' -or -not $build.Value.zip) { continue }
            $zip = $build.Value.zip
            $builds += ConvertTo-PhpBuild -File $zip.path -Url "$Global:PhpSwitchDownloadBase/$($zip.path)" -Sha256 $zip.sha256 -Size $zip.size
        }
    }

    if ($All) {
        $known = @{}
        foreach ($b in $builds) { if ($b) { $known[$b.File] = $true } }
        foreach ($b in Get-PhpArchive) { if (-not $known.ContainsKey($b.File)) { $builds += $b } }
    }

    $builds | Where-Object { $_ -and $_.Arch -eq $Arch -and $_.ThreadSafe -eq [bool]$ThreadSafe } |
        Sort-Object Version -Descending
}

# "8.4" -> newest 8.4.x; "8.3.10" -> that release, looked up in the archive if it's not the newest.
function Find-PhpBuild {
    param([string]$Version, [switch]$ThreadSafe, [string]$Arch)
    $isMatch = { $v = $_.Version.ToString(); $v -eq $Version -or $v.StartsWith("$Version.") }
    $build = Get-PhpAvailable -ThreadSafe:$ThreadSafe -Arch $Arch | Where-Object $isMatch | Select-Object -First 1
    if (-not $build -and $Version -match '^\d+\.\d+\.\d+$') {
        $build = Get-PhpAvailable -All -ThreadSafe:$ThreadSafe -Arch $Arch | Where-Object $isMatch | Select-Object -First 1
    }
    $build
}

function Format-PhpBuild {
    param($Build, $Installed)
    $line = '{0,-10} {1}' -f "$($Build.Version)", $Build.Folder
    if ($Installed | Where-Object { $_.Version -eq $Build.Version }) {
        $line += '   (installed)'
    }
    else {
        $sameBranch = $Installed | Where-Object {
            $_.Version.Major -eq $Build.Version.Major -and $_.Version.Minor -eq $Build.Version.Minor
        } | Select-Object -First 1
        if ($sameBranch) { $line += "   (you have $($sameBranch.Version) - newer release)" }
    }
    $line
}

function Show-PhpAvailable {
    param([switch]$All, [switch]$ThreadSafe, [string]$Arch, $Installed)
    $builds = @(Get-PhpAvailable -All:$All -ThreadSafe:$ThreadSafe -Arch $Arch)
    $kind = if ($ThreadSafe) { 'thread-safe' } else { 'non-thread-safe' }
    $what = if ($All) { 'all releases' } else { 'newest of each branch' }
    Write-Host ''
    Write-Host "  PHP for Windows from windows.php.net ($Arch, $kind, $what):"
    Write-Host ''
    foreach ($b in $builds) { Write-Host "    $(Format-PhpBuild $b $Installed)" }
    Write-Host ''
    Write-Host '  Install one with: install-php <version>' -ForegroundColor DarkGray
    if (-not $All) { Write-Host '  Older releases:   install-php -List -All' -ForegroundColor DarkGray }
    Write-Host ''
}

# Is the Microsoft Visual C++ runtime that PHP needs installed?
function Test-VcRuntime {
    param([string]$Arch = 'x64')
    try {
        $view = if ($Arch -eq 'x86') { 'Registry32' } else { 'Registry64' }
        $hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', $view)
        $key  = $hklm.OpenSubKey("SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\$Arch")
        $ok   = [bool]($key -and $key.GetValue('Installed') -eq 1)
        if ($key) { $key.Close() }
        $hklm.Close()
        $ok
    }
    catch { $true }   # can't tell, so don't block
}

# Downloads, verifies and unpacks a build into $Target. Returns $true on success.
function Save-PhpBuild {
    param($Build, [string]$Target)

    $zip     = Join-Path ([IO.Path]::GetTempPath()) ('{0}-{1}' -f [guid]::NewGuid().ToString('N'), $Build.File)
    $staging = '{0}.partial-{1}' -f $Target, [guid]::NewGuid().ToString('N').Substring(0, 8)
    try {
        $size = if ($Build.Size) { " ($($Build.Size))" } else { '' }
        Write-Host "Downloading $($Build.File)$size..."
        Enable-PhpSwitchTls
        $ProgressPreference = 'SilentlyContinue'   # the progress bar makes 5.1 downloads very slow
        Invoke-WebRequest -Uri $Build.Url -OutFile $zip -UseBasicParsing -ErrorAction Stop

        if ($Build.Sha256) {
            $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
            if ($hash -ne $Build.Sha256) { throw "the download is damaged (its SHA-256 checksum doesn't match). Please try again." }
            Write-Host '  Checksum OK' -ForegroundColor DarkGray
        }
        else {
            Write-Warning 'windows.php.net publishes no checksums for older releases, so this download could not be verified.'
        }

        Write-Host 'Unpacking...'
        New-Item -ItemType Directory -Path $staging -Force | Out-Null
        Expand-Archive -LiteralPath $zip -DestinationPath $staging -Force -ErrorAction Stop
        if (-not (Test-Path -LiteralPath (Join-Path $staging 'php.exe'))) { throw "php.exe wasn't in the download." }

        Move-Item -LiteralPath $staging -Destination $Target -ErrorAction Stop
        Write-Host "Installed PHP $($Build.Version) to $Target" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Couldn't install PHP $($Build.Version): $($_.Exception.Message)"
        return $false
    }
    finally {
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# Creates php.ini from php.ini-development with an absolute extension_dir and common extensions on.
function Initialize-PhpIni {
    param([string]$PhpPath, [string[]]$Extensions)

    $ini = Join-Path $PhpPath 'php.ini'
    if (Test-Path -LiteralPath $ini) { return }
    $template = Join-Path $PhpPath 'php.ini-development'
    if (-not (Test-Path -LiteralPath $template)) {
        Write-Warning "No php.ini-development in $PhpPath, so php.ini wasn't created."
        return
    }

    $text   = [IO.File]::ReadAllText($template)
    $extDir = Join-Path $PhpPath 'ext'

    # An absolute extension_dir works whichever folder php is started from
    $dirLine = 'extension_dir = "{0}"' -f $extDir
    $dirPattern = '(?m)^;\s*extension_dir\s*=\s*"ext"[^\r\n]*'
    if ($text -match $dirPattern) { $text = [regex]::Replace($text, $dirPattern, $dirLine.Replace('$', '$$')) }
    else { $text += "`r`n$dirLine`r`n" }

    $enabled = @()
    foreach ($name in $Extensions) {
        $dll = $name
        if (-not (Test-Path -LiteralPath (Join-Path $extDir "php_$dll.dll"))) {
            # PHP 7.4 calls gd "gd2"
            if (Test-Path -LiteralPath (Join-Path $extDir "php_${name}2.dll")) { $dll = "${name}2" } else { continue }
        }
        $escaped = [regex]::Escape($dll)
        $commented = '(?m)^;\s*extension\s*=\s*(php_)?' + $escaped + '(\.dll)?[ \t]*(?=\r?$)'
        if ($text -match $commented) {
            $text = [regex]::Replace($text, $commented, "extension=$dll")
        }
        elseif ($text -notmatch ('(?m)^extension\s*=\s*' + $escaped + '[ \t]*(?=\r?$)')) {
            $text += "`r`nextension=$dll"
        }
        $enabled += $dll
    }

    [IO.File]::WriteAllText($ini, $text)
    $list = if ($enabled.Count) { $enabled -join ', ' } else { 'none' }
    Write-Host "  Created php.ini (extensions on: $list)" -ForegroundColor DarkGray
}

# Runs php -v once to check the new build starts. Returns $true if it does.
function Test-PhpBuild {
    param([string]$PhpPath, [string]$Arch = 'x64')
    $vcHelp = 'https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist'
    if (-not (Test-VcRuntime -Arch $Arch)) {
        Write-Warning "PHP needs the Microsoft Visual C++ Redistributable ($Arch), which isn't installed. Get the latest one from $vcHelp"
        return $false
    }
    $php = Join-Path $PhpPath 'php.exe'
    $output = @(& $php -v 2>$null)
    $exitCode = $LASTEXITCODE
    $first = $output | Select-Object -First 1
    if ($exitCode -ne 0 -or -not $first) {
        Write-Warning ("PHP didn't start (exit code $exitCode). Your Microsoft Visual C++ Redistributable ($Arch) " +
            "may be too old for this build. Install the latest one from $vcHelp")
        return $false
    }
    Write-Host "  $first" -ForegroundColor DarkGray
    return $true
}

function Install-PhpVersion {
    <#
    .SYNOPSIS
        Downloads a PHP version from windows.php.net into your PHP folder.
    .DESCRIPTION
        "8.4" installs the newest 8.4.x; "8.3.10" installs that exact release.
        Run without a version to pick from a list. The checksum is verified when
        windows.php.net publishes one, and php.ini is created with common
        extensions turned on (curl, mbstring, openssl, pdo_mysql, zip, ...).
    .EXAMPLE
        install-php 8.4
    .EXAMPLE
        install-php 8.4 -Use          # install, then use it in this terminal
    .EXAMPLE
        install-php 8.4 -Persist      # install and make it the default
    .EXAMPLE
        install-php -List             # what can be downloaded
    .EXAMPLE
        install-php -List -All        # including older releases
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)]
        [string]$Version,

        # Use the new version in this terminal afterwards
        [switch]$Use,

        # Use it and make it the default for new terminals
        [Alias('Global')]
        [switch]$Persist,

        # Show downloadable versions instead of installing
        [switch]$List,

        # With -List: include older releases
        [switch]$All,

        # Thread-safe build, for Apache mod_php. The default (non-thread-safe) suits the CLI, Nginx and IIS.
        [switch]$ThreadSafe,

        [ValidateSet('x64', 'x86')]
        [string]$Arch = 'x64',

        # Extensions to turn on in php.ini
        [string[]]$Extensions = $Global:PhpSwitchDefaultExtensions,

        # Don't create php.ini
        [switch]$NoIni,

        # Install even if the same version is already there as a different build
        [switch]$Force,

        [string]$BasePath = $env:PHP_BASE_PATH
    )

    try {
        $null = Get-PhpReleaseFeed
    }
    catch {
        Write-Error "Couldn't reach downloads.php.net: $($_.Exception.Message)"
        return
    }

    $installed = @(Get-PhpInstall -BasePath $BasePath)

    if ($List -or (-not $Version -and -not [Environment]::UserInteractive)) {
        try { Show-PhpAvailable -All:$All -ThreadSafe:$ThreadSafe -Arch $Arch -Installed $installed }
        catch { Write-Error "Couldn't load the release list: $($_.Exception.Message)" }
        return
    }

    if ($Version) {
        $Version = $Version.Trim() -replace '^(php-?|v)', ''
        try {
            $build = Find-PhpBuild -Version $Version -ThreadSafe:$ThreadSafe -Arch $Arch
        }
        catch {
            Write-Error "Couldn't reach downloads.php.net: $($_.Exception.Message)"
            return
        }
        if (-not $build) {
            $branches = (Get-PhpAvailable -ThreadSafe:$ThreadSafe -Arch $Arch | ForEach-Object { "$($_.Version)" }) -join ', '
            Write-Error "PHP $Version isn't available for Windows ($Arch). Newest of each branch: $branches. Every release: install-php -List -All"
            return
        }
    }
    else {
        $latest = @(Get-PhpAvailable -ThreadSafe:$ThreadSafe -Arch $Arch)
        $labels = $latest | ForEach-Object { Format-PhpBuild $_ $installed }
        $choice = Read-PhpSwitchChoice -Title 'PHP versions you can download:' -Labels $labels
        if ($choice -lt 0) { return }
        $build = $latest[$choice]
    }

    if (-not $BasePath) {
        $BasePath = Get-PhpSwitchDefaultBasePath
        Write-Host "No PHP folder is set yet, so PHP goes in $BasePath" -ForegroundColor DarkGray
    }
    $target = Join-Path $BasePath $build.Folder

    if (Test-Path -LiteralPath (Join-Path $target 'php.exe')) {
        Write-Host "PHP $($build.Version) is already installed in $target" -ForegroundColor Green
    }
    else {
        if (Test-Path -LiteralPath $target) {
            Write-Error "$target already exists but has no php.exe in it. Delete or rename that folder, then try again."
            return
        }
        $same = $installed | Where-Object { $_.Version -eq $build.Version } | Select-Object -First 1
        if ($same -and -not $Force) {
            Write-Error "PHP $($build.Version) is already installed as $($same.Name). Add -Force to put $($build.Folder) next to it."
            return
        }
        if (-not $PSCmdlet.ShouldProcess($target, "Download and install PHP $($build.Version)")) { return }

        if (-not (Save-PhpBuild -Build $build -Target $target)) { return }
        if (-not $NoIni) { Initialize-PhpIni -PhpPath $target -Extensions $Extensions }
        [void](Test-PhpBuild -PhpPath $target -Arch $build.Arch)
    }

    # First install: remember where PHP lives
    if (-not $env:PHP_BASE_PATH) { Set-PhpBasePath -Path $BasePath }

    if ($Use -or $Persist) {
        Switch-PhpVersion -Version "$($build.Version)" -BasePath $BasePath -Persist:$Persist
    }
    else {
        Write-Host "  Use it with: switch-php $($build.Version)   (add -Persist to make it the default)" -ForegroundColor DarkGray
    }
}

function Remove-PhpVersion {
    <#
    .SYNOPSIS
        Removes an installed PHP version. It goes to the Recycle Bin unless you add -Permanent.
    .DESCRIPTION
        Asks for confirmation first; add -Confirm:$false to skip that.
    .EXAMPLE
        remove-php 8.1
    .EXAMPLE
        remove-php                       # pick from a list
    .EXAMPLE
        remove-php 8.1.27 -Permanent
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Position = 0)]
        [string]$Version,

        # Delete instead of moving to the Recycle Bin
        [switch]$Permanent,

        # Allow removing the version new terminals use by default
        [switch]$Force,

        [string]$BasePath = $env:PHP_BASE_PATH
    )

    $installs = @(Get-PhpInstall -BasePath $BasePath)
    if (-not $installs.Count) {
        $where = if ($BasePath) { $BasePath } else { 'your PHP folder (none set yet)' }
        Write-Error "No PHP versions found in $where."
        return
    }

    $found = $installs
    if ($Version) {
        $Version = $Version.Trim() -replace '^(php-?|v)', ''
        $found = @($installs | Where-Object { $v = $_.Version.ToString(); $v -eq $Version -or $v.StartsWith("$Version.") })
        if (-not $found.Count) {
            Write-Error "PHP $Version isn't installed. Installed: $(($installs | ForEach-Object { "$($_.Version)" }) -join ', ')"
            return
        }
    }

    if ($found.Count -eq 1) {
        $target = $found[0]
    }
    elseif ([Environment]::UserInteractive) {
        $title = if ($Version) { "More than one PHP $Version is installed. Which one?" } else { 'Which PHP version do you want to remove?' }
        $choice = Read-PhpSwitchChoice -Title $title -Labels ($found | ForEach-Object { Format-PhpInstall $_ })
        if ($choice -lt 0) { return }
        $target = $found[$choice]
    }
    else {
        Write-Error "More than one PHP $Version is installed ($(($found | ForEach-Object { "$($_.Version)" }) -join ', ')). Give the full version."
        return
    }

    if ($target.Default -and -not $Force) {
        Write-Error ("PHP $($target.Version) is the default for new terminals. Make another version the default first " +
            '(switch-php <version> -Persist), or add -Force.')
        return
    }

    $running = @(Get-Process -Name php, php-cgi -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -and $_.Path.StartsWith($target.Path + '\', [System.StringComparison]::OrdinalIgnoreCase)
    })
    if ($running.Count) {
        Write-Error ("PHP $($target.Version) is still running (process $(($running | ForEach-Object { $_.Id }) -join ', ')). " +
            'Stop it first - for example php artisan serve or a queue worker.')
        return
    }

    $action = if ($Permanent) { "Permanently delete PHP $($target.Version)" } else { "Move PHP $($target.Version) to the Recycle Bin" }
    if (-not $PSCmdlet.ShouldProcess($target.Path, $action)) { return }

    try {
        if ($Permanent) {
            Remove-Item -LiteralPath $target.Path -Recurse -Force -ErrorAction Stop
        }
        else {
            Add-Type -AssemblyName Microsoft.VisualBasic
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($target.Path,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
        }
    }
    catch {
        Write-Error "Couldn't remove $($target.Path): $($_.Exception.Message)"
        return
    }

    $how = if ($Permanent) { 'deleted' } else { 'moved to the Recycle Bin' }
    Write-Host "Removed PHP $($target.Version) ($how)" -ForegroundColor Green

    # Clean up this terminal if it was using it
    if (($env:PATH -split ';') -contains $target.Path) {
        $env:PATH = ($env:PATH -split ';' | Where-Object { $_ -and $_ -ne $target.Path }) -join ';'
        if ($env:PHPRC -eq $target.Path) { Remove-Item Env:PHPRC -ErrorAction SilentlyContinue }
        Write-Host '  This terminal was using it. Run switch-php to pick another version.' -ForegroundColor Yellow
    }
    if ($target.Default) {
        $next = Get-PhpDefaultDir
        $now  = if ($next) { "$next\php.exe" } else { 'no PHP at all' }
        Write-Warning "That was your default PHP. New terminals will now get $now. Set a new default with: switch-php <version> -Persist"
    }
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
        Enable-PhpSwitchTls
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

Set-Alias -Name switch-php  -Value Switch-PhpVersion
Set-Alias -Name install-php -Value Install-PhpVersion
Set-Alias -Name remove-php  -Value Remove-PhpVersion

# switch-php <Tab> and remove-php <Tab> cycle through installed versions
Register-ArgumentCompleter -CommandName Switch-PhpVersion, switch-php, Remove-PhpVersion, remove-php -ParameterName Version -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $base = if ($fakeBoundParameters.BasePath) { $fakeBoundParameters.BasePath } else { $env:PHP_BASE_PATH }
    Get-PhpInstall -BasePath $base |
        ForEach-Object { "$($_.Version.Major).$($_.Version.Minor)"; "$($_.Version)" } |
        Select-Object -Unique |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}

# install-php <Tab> cycles through downloadable versions
Register-ArgumentCompleter -CommandName Install-PhpVersion, install-php -ParameterName Version -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    try { $builds = @(Get-PhpAvailable -ErrorAction Stop) } catch { return }
    $builds |
        ForEach-Object { "$($_.Version.Major).$($_.Version.Minor)"; "$($_.Version)" } |
        Select-Object -Unique |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}
