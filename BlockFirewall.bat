@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: =========================================================
:: Block all executables in a folder (and subfolders) from
:: using the internet via Windows Defender Firewall rules.
::
:: Usage:
::   1) Place this .bat in the target folder and run as Admin
::      - or -
::      Run as Admin with a path:  BlockFolderNoNet.bat "C:\Path\To\Folder"
::   2) To remove rules created by this script:
::      BlockFolderNoNet.bat --remove "C:\Path\To\Folder"
::
:: Notes:
:: - Creates both OUTBOUND and INBOUND block rules.
:: - Matches by full program path (one rule per .exe).
:: - Safe to re-run; it refreshes rules.
:: =========================================================

:: ---------- Admin check ----------
>nul 2>&1 net session
if %errorlevel% neq 0 (
  echo [!] This script must be run as Administrator.
  echo     Right-click the .bat and choose "Run as administrator".
  pause
  exit /b 1
)

:: ---------- Parse args ----------
set "ACTION=add"
if /I "%~1"=="--remove" (
  set "ACTION=remove"
  shift
)

if "%~1"=="" (
  set "TARGET_DIR=%~dp0"
) else (
  set "TARGET_DIR=%~1"
)

:: Normalize/remove quotes
set "TARGET_DIR=%TARGET_DIR:"=%"

if not exist "%TARGET_DIR%" (
  echo [!] Folder not found: "%TARGET_DIR%"
  exit /b 1
)

:: ---------- Rule naming/tagging ----------
:: We use a rule prefix that is unique per target folder.
:: Create a simple hash from the path to keep names short.
set "RULE_TAG=NoNetFolder"
set "PATH_HASH="
for /f "usebackq tokens=1,* delims=:" %%a in (`cmd /c certutil -hashfile "%~f0" MD5 ^| find /i /v "hash" ^| find /i /v "certutil"`) do (
  rem Not actually hashing the folder (certutil needs a file), so fall back to a deterministic tag using the folder itself.
)
:: Build a basic sanitized suffix from the folder path (remove :\ and slashes)
set "SANITIZED_DIR=%TARGET_DIR:\=_%"
set "SANITIZED_DIR=%SANITIZED_DIR::=%"
set "SANITIZED_DIR=%SANITIZED_DIR:/=%"
set "RULE_PREFIX=%RULE_TAG%_%SANITIZED_DIR%_"

echo.
echo Target folder: "%TARGET_DIR%"
echo Action: %ACTION%
echo Rule prefix: "%RULE_PREFIX%"
echo.

:: ---------- Gather executables ----------
set "COUNT=0"
for /r "%TARGET_DIR%" %%F in (*.exe) do (
  set /a COUNT+=1 >nul
)

if %COUNT%==0 (
  echo [i] No *.exe files found under "%TARGET_DIR%".
  exit /b 0
)

:: ---------- Remove old rules (if any) or on --remove ----------
echo [i] Scanning/removing existing rules with this prefix...
for /f "tokens=*" %%R in ('netsh advfirewall firewall show rule name^=all ^| findstr /I /C:"Rule Name:" ^| findstr /I /C:"%RULE_PREFIX%"') do (
  for /f "tokens=2,* delims=:" %%A in ("%%R") do (
    set "RULENAME=%%~A"
    set "RULENAME=!RULENAME:~1!"
    if defined RULENAME (
      netsh advfirewall firewall delete rule name="!RULENAME!" >nul
    )
  )
)

if /I "%ACTION%"=="remove" (
  echo [✓] Removed rules for "%TARGET_DIR%".
  exit /b 0
)

:: ---------- Create fresh rules ----------
echo [i] Creating block rules for %COUNT% executables...
set "CREATED=0"
for /r "%TARGET_DIR%" %%F in (*.exe) do (
  set "EXE=%%~fF"
  set "BASENAME=%%~nxF"
  set "RULE_OUT=%RULE_PREFIX%!BASENAME!_OUT"
  set "RULE_IN=%RULE_PREFIX%!BASENAME!_IN"

  rem Outbound block
  netsh advfirewall firewall add rule name="%RULE_OUT%" dir=out action=block program="%EXE%" enable=yes profile=any >nul
  rem Inbound block
  netsh advfirewall firewall add rule name="%RULE_IN%" dir=in  action=block program="%EXE%" enable=yes profile=any >nul

  set /a CREATED+=1 >nul
)

echo [✓] Created %CREATED% program-specific firewall block rules (in+out) for:
echo     "%TARGET_DIR%"
echo.
echo To undo: run this script with --remove "%TARGET_DIR%"
echo.

endlocal
