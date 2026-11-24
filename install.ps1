<#
    php-switch installer
    https://github.com/samiulislamsharan/php-switch

    Install or update (paste into PowerShell):
        irm https://raw.githubusercontent.com/samiulislamsharan/php-switch/main/install.ps1 | iex

    With options:
        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/samiulislamsharan/php-switch/main/install.ps1))) -BasePath 'C:\laragon\bin\php' -Yes

    What it does:
        1. Saves switch-php.ps1 to ~\.php-switch
        2. Finds the folder with your PHP versions (Laragon, C:\php, D:\php, ...)
        3. Loads switch-php from your Windows PowerShell and PowerShell 7 profiles
        4. Checks that PowerShell is allowed to run your profile
    Running it again updates switch-php and keeps your settings.
#>
param(
    # Folder that holds your php-x.y.z folders. Found automatically if left out.
    [string]$BasePath,

    # Don't ask any questions; use the defaults.
    [switch]$Yes
)

function Install-PhpSwitch {
    param([string]$BasePath, [switch]$Yes)

    $sourceUrl  = 'https://raw.githubusercontent.com/samiulislamsharan/php-switch/main/switch-php.ps1'
    $installDir = Join-Path $HOME '.php-switch'
    $scriptPath = Join-Path $installDir 'switch-php.ps1'

    function Write-Step([int]$Number, [string]$Text) {
        Write-Host ''
        Write-Host "[$Number/4] $Text" -ForegroundColor Cyan
    }
    function Write-Detail([string]$Text, [string]$Color = 'Gray') {
        Write-Host "      $Text" -ForegroundColor $Color
    }
    function Read-YesNo([string]$Question) {
        if ($Yes) { return $true }
        $answer = Read-Host "      $Question [Y/n]"
        return (-not $answer -or $answer -match '^\s*y(es)?\s*$')
    }
    function Invoke-PowerShell([string]$Exe, [string]$Command) {
        $ErrorActionPreference = 'Continue'
        $output = & $Exe -NoLogo -NoProfile -NonInteractive -Command $Command 2>$null
        ($output | Out-String).Trim()
    }

    Write-Host ''
    Write-Host 'php-switch installer' -ForegroundColor Cyan
    Write-Host 'Switch between PHP versions on Windows from PowerShell.'

    if ($env:OS -ne 'Windows_NT') {
        Write-Host 'php-switch only works on Windows.' -ForegroundColor Red
        return $false
    }

    # -- 1. Get the script ---------------------------------------------------
    Write-Step 1 'Downloading switch-php'
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('switch-php-{0}.ps1' -f [guid]::NewGuid())
    try {
        $localCopy = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'switch-php.ps1' }
        if ($localCopy -and (Test-Path -LiteralPath $localCopy)) {
            Copy-Item -LiteralPath $localCopy -Destination $tmp -ErrorAction Stop
            Write-Detail "Using the copy next to this installer: $localCopy"
        }
        else {
            # Windows PowerShell 5.1 may not have TLS 1.2 turned on
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            # The progress bar makes downloads very slow in Windows PowerShell 5.1
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $sourceUrl -OutFile $tmp -UseBasicParsing -ErrorAction Stop
        }

        $tokens = $null; $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($tmp, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors -or -not (Select-String -LiteralPath $tmp -Pattern 'function Switch-PhpVersion' -SimpleMatch -Quiet)) {
            throw "the downloaded file isn't a valid switch-php.ps1"
        }

        New-Item -ItemType Directory -Path $installDir -Force -ErrorAction Stop | Out-Null
        Copy-Item -LiteralPath $tmp -Destination $scriptPath -Force -ErrorAction Stop
        Unblock-File -LiteralPath $scriptPath -ErrorAction SilentlyContinue
    }
    catch {
        Write-Detail "Couldn't install switch-php: $($_.Exception.Message)" Red
        return $false
    }
    finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
    Write-Detail "Saved to $scriptPath" Green

    # Load it here so the steps below can use its functions. Loading the text
    # (not the file) works even while the execution policy still blocks scripts.
    . ([scriptblock]::Create([IO.File]::ReadAllText($scriptPath)))

    # -- 2. Find PHP ---------------------------------------------------------
    Write-Step 2 'Finding your PHP versions'
    $chosen = $null
    if ($BasePath) {
        $chosen = $BasePath
    }
    elseif ($env:PHP_BASE_PATH -and @(Get-PhpInstall -BasePath $env:PHP_BASE_PATH).Count) {
        $chosen = $env:PHP_BASE_PATH
        Write-Detail 'Keeping your current PHP folder.'
    }
    else {
        $found = @(Find-PhpBasePath)
        if ($found.Count -eq 1 -or ($found.Count -gt 1 -and $Yes)) {
            $chosen = $found[0].Path
        }
        elseif ($found.Count -gt 1) {
            $labels = $found | ForEach-Object { Format-PhpBasePath $_ }
            $choice = Read-PhpSwitchChoice -Title '      PHP versions were found in more than one folder:' -Labels $labels -Default 1
            if ($choice -ge 0) { $chosen = $found[$choice].Path }
        }
        else {
            Write-Detail "Couldn't find your PHP versions automatically." Yellow
        }

        while (-not $chosen -and -not $Yes) {
            $answer = "$(Read-Host '      Folder that holds your php-x.y.z folders (Enter to skip)')".Trim().Trim('"')
            if (-not $answer) { break }
            if (@(Get-PhpInstall -BasePath $answer).Count) { $chosen = $answer }
            else { Write-Detail "No php-<version> folders with php.exe inside $answer" Yellow }
        }
    }

    if ($chosen) {
        try {
            Set-PhpBasePath -Path $chosen -ErrorAction Stop
        }
        catch {
            Write-Detail $_.Exception.Message Red
            $chosen = $null
        }
    }
    if (-not $chosen) {
        Write-Detail 'Skipped. Run Set-PhpBasePath once your PHP versions are in place.' Yellow
    }

    # -- 3. Profiles ---------------------------------------------------------
    Write-Step 3 'Loading switch-php in every new PowerShell window'
    $editions = @(Get-PhpSwitchProfileTarget | Where-Object {
        Get-Command $_.Exe -CommandType Application -ErrorAction SilentlyContinue
    })
    foreach ($edition in $editions) {
        try {
            if (Add-PhpSwitchProfileBlock -Path $edition.ProfilePath) {
                Write-Detail "$($edition.Name): added to $($edition.ProfilePath)" Green
            }
            else {
                Write-Detail "$($edition.Name): already set up" Green
            }
        }
        catch {
            Write-Detail "$($edition.Name): couldn't update $($edition.ProfilePath): $($_.Exception.Message)" Red
        }
    }

    # People who used the old copy-paste version may still have it in a profile
    $docs = [Environment]::GetFolderPath('MyDocuments')
    foreach ($folder in 'WindowsPowerShell', 'PowerShell') {
        foreach ($file in 'profile.ps1', 'Microsoft.PowerShell_profile.ps1', 'Microsoft.VSCode_profile.ps1') {
            $path = Join-Path $docs "$folder\$file"
            if ((Test-Path -LiteralPath $path) -and
                (Select-String -LiteralPath $path -Pattern '^\s*function\s+switch-php\b' -Quiet)) {
                Write-Detail "Found an older switch-php function in $path - you can delete it, this one replaces it." Yellow
            }
        }
    }

    # -- 4. Execution policy -------------------------------------------------
    Write-Step 4 'Checking that PowerShell may run your profile'
    foreach ($edition in $editions) {
        $policy = Invoke-PowerShell $edition.Exe 'Get-ExecutionPolicy'
        if ($policy -eq 'Restricted' -and
            (Read-YesNo "$($edition.Name) blocks all scripts, including your profile. Allow scripts for your account (RemoteSigned)?")) {
            [void](Invoke-PowerShell $edition.Exe 'Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force')
            $policy = Invoke-PowerShell $edition.Exe 'Get-ExecutionPolicy'
        }

        switch ($policy) {
            'Restricted' { Write-Detail "$($edition.Name): scripts are blocked, so switch-php won't load there. To fix: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser" Yellow }
            'AllSigned'  { Write-Detail "$($edition.Name): only signed scripts may run (AllSigned), so switch-php won't load there." Yellow }
            ''           { Write-Detail "$($edition.Name): couldn't check the execution policy." Yellow }
            default      { Write-Detail "$($edition.Name): OK ($policy)" Green }
        }
    }

    # -- Done ----------------------------------------------------------------
    Write-Host ''
    Write-Host 'Done! Try it:' -ForegroundColor Green
    Write-Host '  switch-php                  pick a version from a list'
    Write-Host '  switch-php 8.3              use the newest 8.3.x in this terminal'
    Write-Host '  switch-php 8.3 -Persist     ...and in every new terminal'
    Write-Host '  switch-php -List            see what is installed and active'
    Write-Host '  Get-Help switch-php         more help'
    Write-Host ''
    Write-Host "If this window says switch-php isn't recognized, open a new one." -ForegroundColor DarkGray
    return $true
}

$phpSwitchInstalled = @(Install-PhpSwitch -BasePath $BasePath -Yes:$Yes)[-1]

# Load it into this window too (works when run with "irm ... | iex")
if ($phpSwitchInstalled -eq $true) {
    . ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $HOME '.php-switch\switch-php.ps1'))))
}
Remove-Item -Path Function:\Install-PhpSwitch -ErrorAction SilentlyContinue
Remove-Variable -Name phpSwitchInstalled -ErrorAction SilentlyContinue
