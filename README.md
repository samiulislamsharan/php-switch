# php-switch: switch PHP versions on Windows

Download, switch between and remove PHP versions on Windows with one PowerShell command. It works with the PHP folders you already have (Laragon, `C:\php`, `D:\php`, ...) and can switch just the current terminal or change your default.

- `install-php 8.4` downloads the newest PHP 8.4 from windows.php.net, checks it and sets up `php.ini`
- `switch-php 8.4` switches this terminal; add `-Persist` to make it your default
- `remove-php 8.1` removes a version (to the Recycle Bin)

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
2. Finds your PHP versions (checks `laragon\bin\php`, `php` and `tools\php` on every local drive) and asks if it finds more than one place. If you have no PHP yet, it offers to download the newest version
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
| `install-php 8.4` | Download the newest PHP 8.4.x into your PHP folder |
| `install-php` | Pick a version to download from a list |
| `install-php -List` | Show what you can download (`-All` for older releases) |
| `remove-php 8.1` | Remove an installed version |
| `Set-PhpBasePath` | Find or change the folder that holds your PHP versions |
| `Restore-PhpUserPath` | Undo the last `-Persist` |
| `Update-PhpSwitch` | Download the latest switch-php |
| `Uninstall-PhpSwitch` | Remove switch-php |
| `Get-Help switch-php` | Full help |

The short names are aliases of `Switch-PhpVersion`, `Install-PhpVersion` and `Remove-PhpVersion`. `-Global` works the same as `-Persist`.

Your PHP folder should hold one subfolder per version, each with a `php.exe`:

```text
C:\laragon\bin\php\
├── php-8.1.27-Win32-vs16-x64\php.exe
├── php-8.3.14-Win32-vs16-x64\php.exe
└── php-8.4.1-Win32-vs17-x64\php.exe
```

## Downloading PHP (`install-php`)

```powershell
install-php 8.4               # newest 8.4.x
install-php 8.3.10            # that exact release
install-php 8.4 -Use          # install, then use it in this terminal
install-php 8.4 -Persist      # install and make it your default
install-php -List             # what you can download
install-php -List -All        # including older releases
```

What it does:

- **Downloads the official build** from windows.php.net (`downloads.php.net/~windows`). By default that's the 64-bit non-thread-safe build, which suits the command line, `php artisan serve`, Nginx and IIS. Add `-ThreadSafe` for Apache's mod_php, or `-Arch x86` for 32-bit.
- **Checks the SHA-256 checksum** against the one windows.php.net publishes. That's available for the newest release of each branch; older releases from the archive have no published checksum, and install-php warns you when it can't verify one.
- **Unpacks it into your PHP folder**, named like windows.php.net names it (for example `php-8.4.28-nts-Win32-vs17-x64`). With Laragon, that means new versions also show up in Laragon's PHP menu. If you haven't set a PHP folder yet, it uses `%LOCALAPPDATA%\Programs\php`, which doesn't need admin.
- **Creates `php.ini`** from `php.ini-development`, sets `extension_dir` to the full path of the `ext` folder, and turns on `curl`, `fileinfo`, `gd`, `intl`, `mbstring`, `openssl`, `pdo_mysql`, `pdo_sqlite`, `sqlite3` and `zip`. Pick your own list with `-Extensions curl,mbstring,openssl`, or skip this with `-NoIni`.
- **Checks that PHP starts.** PHP needs the Microsoft Visual C++ Redistributable. If it's missing or too old, install-php tells you where to get it ([latest supported downloads](https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist)).

`install-php -List` also marks versions you have installed, and branches where a newer patch release is out. To update, install the new patch, switch to it, then remove the old one.

## Removing PHP (`remove-php`)

```powershell
remove-php 8.1                # asks before removing; picks from a list if several 8.1.x are installed
remove-php                    # pick from a list
remove-php 8.1.27 -Permanent  # delete instead of using the Recycle Bin
```

- By default the folder goes to the **Recycle Bin**, so you can restore it.
- It **asks you to confirm** first. Add `-Confirm:$false` to skip the question.
- It won't remove your **default** version (the one new terminals use) unless you add `-Force`. Make another version the default first with `switch-php <version> -Persist`.
- It won't remove a version that's **still running**, for example `php artisan serve` or a queue worker. Stop it first.

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

Uninstalling removes the profile lines, the `PHP_BASE_PATH` setting and the script. It doesn't touch your PHP versions. PATH backups stay in `~\.php-switch\backups` in case you need them.

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
That version has no `php.ini`. Copy `php.ini-development` to `php.ini` in the same folder and turn on the extensions you need. Versions downloaded with `install-php` get one automatically.

**PHP didn't start after `install-php`**, or Windows says `VCRUNTIME140.dll` is missing
Install the latest Microsoft Visual C++ Redistributable for your architecture (usually x64) from [Microsoft's download page](https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist), then run `php -v` again.

**`install-php` can't reach downloads.php.net**
Check that you can open `https://downloads.php.net/~windows/releases/` in a browser. Behind a company proxy, download the zip yourself, unpack it into your PHP folder as `php-<version>-...`, and `switch-php` will find it.

**`remove-php` says the version is still running**
Stop `php artisan serve`, queue workers or anything else using that PHP (check Task Manager for `php.exe`), then try again.

**New terminals still use the old version**
Run `switch-php -List` and look at the "New terminals" line. The usual causes are a PHP on the System PATH, an editor that needs restarting, or Laragon rewriting PATH.

**The installer can't download anything**
Check that you can open `https://raw.githubusercontent.com` in a browser. Behind a company proxy, download the two `.ps1` files manually and use the "read the installer first" steps above.

**I used the old copy-paste version from the gist**
The installer tells you if it finds the old `switch-php` function in one of your profiles. Delete it; the installed version replaces it.
