# php-switch: switch PHP versions on Windows

Switch between PHP versions installed side by side (Laragon, `C:\php`, `D:\php`, ...) with one PowerShell command, either just for the current terminal or as your default.

```text
PS> switch-php
PHP versions in C:\laragon\bin\php:
   1) 8.4.1      php-8.4.1-Win32-vs17-x64
   2) 8.3.14     php-8.3.14-Win32-vs16-x64   (this terminal, default)
   3) 8.1.27     php-8.1.27-Win32-vs16-x64
Choose (1-3, Enter = cancel): 1
PHP 8.4.1 is now active in this terminal
  PHP 8.4.1 (cli) (built: ...) (NTS Visual C++ 2022 x64)
  php.ini: C:\laragon\bin\php\php-8.4.1-Win32-vs17-x64\php.ini
  Tip: add -Persist to use this version in new terminals too.
```

*(Example output, yours will show your own versions.)*

## Install

Paste this into PowerShell (Windows PowerShell 5.1 or PowerShell 7):

```powershell
irm https://raw.githubusercontent.com/samiulislamsharan/php-switch/main/install.ps1 | iex
```

The installer:

1. Saves `switch-php.ps1` to `~\.php-switch`
2. Finds your PHP versions (checks `laragon\bin\php`, `php` and `tools\php` on every local drive) and asks if it finds more than one place
3. Adds one line to your Windows PowerShell and PowerShell 7 profiles so `switch-php` is there in every new window
4. Checks that PowerShell is allowed to run your profile, and offers to fix it if not

It doesn't need admin, and **running it again updates switch-php** without touching your settings.

<details>
<summary>Install options, or read the installer before running it</summary>

Pass options by running the installer as a script block:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/samiulislamsharan/php-switch/main/install.ps1))) -BasePath 'C:\laragon\bin\php' -Yes
```

| Option | Meaning |
| --- | --- |
| `-BasePath <folder>` | Use this PHP folder instead of detecting it |
| `-Yes` | Don't ask questions; use the defaults |

To read it first, clone this repo (or download `install.ps1` and `switch-php.ps1` into one folder), then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

It uses the `switch-php.ps1` next to it instead of downloading one.

</details>

## Usage

| Command | What it does |
| --- | --- |
| `switch-php` | Pick a version from a list |
| `switch-php 8.3` | Use the newest installed 8.3.x in this terminal |
| `switch-php 8.3.14` | Use that exact version |
| `switch-php 8` | Use the newest installed 8.x |
| `switch-php 8.3 -Persist` | Same, **and** make it the default for new terminals |
| `switch-php 8.3 -Persist -WhatIf` | Show what would change, change nothing |
| `switch-php -List` | Show installed versions, and which one this terminal and new terminals use |
| `switch-php <Tab>` | Cycle through installed versions |
| `Set-PhpBasePath` | Find or change the folder that holds your PHP versions |
| `Restore-PhpUserPath` | Undo the last `-Persist` |
| `Update-PhpSwitch` | Download the latest switch-php |
| `Uninstall-PhpSwitch` | Remove switch-php |
| `Get-Help switch-php` | Full help |

`Switch-PhpVersion` is the full command name and `switch-php` is its alias. `-Global` works the same as `-Persist`.

Your PHP folder should hold one subfolder per version, each with a `php.exe`:

```text
C:\laragon\bin\php\
├── php-8.1.27-Win32-vs16-x64\php.exe
├── php-8.3.14-Win32-vs16-x64\php.exe
└── php-8.4.1-Win32-vs17-x64\php.exe
```

## Making a version the default (`-Persist`)

Without `-Persist`, only the current terminal changes. With it, switch-php also:

- Puts the chosen PHP first in your **user** PATH (no admin needed). It edits the registry directly, so entries like `%USERPROFILE%\bin` stay as they are and nothing gets cut off the way `setx` cuts PATH at 1024 characters
- Sets `PHPRC`, so PHP loads the `php.ini` that belongs to that version
- Backs up your PATH first, in `~\.php-switch\backups`
- Tells Windows the environment changed, so new terminals see it right away

**Good to know:**

- **Already-open terminals and editors keep their old PATH.** Restart VS Code itself, not just its terminal.
- **A PHP on the System PATH wins**, because Windows checks the System PATH before yours. switch-php warns you when this happens; removing it needs admin.
- **Laragon can overwrite it.** Its "Add Laragon to Path" option or its PHP menu may rewrite your PATH. Pick one tool to manage the default.

### Undo

```powershell
Restore-PhpUserPath             # PATH as it was before the last -Persist
Restore-PhpUserPath -Original   # PATH as it was before switch-php ever changed it
```

## Update and uninstall

```powershell
Update-PhpSwitch                    # get the latest version
Uninstall-PhpSwitch                 # remove it, keep your current default PHP
Uninstall-PhpSwitch -RestorePath    # remove it and put your PATH back as it was
```

Uninstalling removes the profile lines, the `PHP_BASE_PATH` setting and the script. PATH backups stay in `~\.php-switch\backups` in case you need them.

## Troubleshooting

**`switch-php` isn't recognized**
Open a new PowerShell window. If it's still missing, run the installer again; step 4 tells you if the execution policy is blocking your profile.

**"running scripts is disabled on this system"**
Allow local scripts for your account (no admin needed):

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Windows PowerShell and PowerShell 7 each have their own setting, so run it in the one that shows the error.

**"No php.ini loaded"**
That version has no `php.ini`. Copy `php.ini-development` to `php.ini` in the same folder and turn on the extensions you need.

**New terminals still use the old version**
Run `switch-php -List` and look at the "New terminals" line. The usual causes are a PHP on the System PATH, an editor that needs restarting, or Laragon rewriting PATH.

**The installer can't download anything**
Check that you can open `https://raw.githubusercontent.com` in a browser. Behind a company proxy, download the two `.ps1` files manually and use the "read the installer first" steps above.

**I used the old copy-paste version from the gist**
The installer tells you if it finds the old `switch-php` function in one of your profiles. Delete it; the installed version replaces it.
