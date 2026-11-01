@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Roblox thumbnails fix

rem  ==========================================================================
rem   fix-roblox-thumbnails.bat
rem
rem   THE PROBLEM
rem   On many Russian ISPs the name tr.rbxcdn.com does not resolve: DNS returns
rem   a CNAME to trns1.rbxcdn.com, and that name has neither an A nor an AAAA
rem   record. Result: grey boxes instead of place placeholders, game icons,
rem   avatars and screenshots - in the Roblox app, on the website and in Studio.
rem   The API itself still works, so titles, ratings and player counts show up.
rem
rem   WHAT THIS DOES
rem   Pins tr.rbxcdn.com to working CDN addresses in the hosts file.
rem   Each address is probed over HTTPS before it is written.
rem   The script backs up hosts, flushes the DNS cache and prints the result.
rem
rem   USAGE
rem       fix-roblox-thumbnails.bat            install
rem       fix-roblox-thumbnails.bat /remove    delete the added lines
rem       fix-roblox-thumbnails.bat /rollback  restore hosts from the backup
rem       fix-roblox-thumbnails.bat /help      show help
rem
rem   Administrator rights are required - the script asks for UAC itself.
rem   Backups go to %USERPROFILE%\roblox-thumbnails-fix\
rem
rem   Upstream bug report: devforum.roblox.com/t/4757714  (CREATORBUG-27611)
rem  ==========================================================================

set "DOMAIN=tr.rbxcdn.com"
set "IPS=18.64.211.78 18.64.211.88 18.64.211.103 23.73.2.78"
set "WORKDIR=%USERPROFILE%\roblox-thumbnails-fix"
set "HOSTS=%SystemRoot%\System32\drivers\etc\hosts"

rem  Debug hook: point the script at another file to test the logic safely.
if defined RBX_HOSTS set "HOSTS=%RBX_HOSTS%"

set "NOPAUSE="
for %%A in (%*) do if /i "%%A"=="/nopause" set "NOPAUSE=1"

call :banner

if /i "%~1"=="/help"     goto help
if /i "%~1"=="-h"        goto help
if /i "%~1"=="--help"    goto help
if /i "%~1"=="/remove"   goto remove
if /i "%~1"=="--remove"  goto remove
if /i "%~1"=="/rollback" goto rollback

rem  ------------------------------------------------------------------ install
rem  Check for existing lines before asking for rights: if there is nothing
rem  to do, we should not raise a UAC prompt at all.

findstr /i /c:"%DOMAIN%" "%HOSTS%" >nul 2>&1
if not errorlevel 1 goto already

call :require_admin
if errorlevel 1 exit /b 0

if not exist "%WORKDIR%" mkdir "%WORKDIR%" >nul 2>&1

for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "TS=%%i"
if not defined TS set "TS=manual"
set "BACKUP=%WORKDIR%\hosts-%TS%.txt"

echo   [1/4] Backing up the current hosts file
copy /y "%HOSTS%" "%BACKUP%" >nul 2>&1
if not exist "%BACKUP%" (
    echo         failed, aborting
    goto fail
)
echo         %BACKUP%

echo   [2/4] Probing CDN addresses
set "PICKED="
where curl >nul 2>&1
if errorlevel 1 (
    echo         curl not found, using the built-in list unchecked
    set "PICKED=%IPS%"
) else (
    for %%I in (%IPS%) do (
        if exist "%TEMP%\rbxprobe.h" del "%TEMP%\rbxprobe.h" >nul 2>&1
        curl -s --max-time 8 -o NUL -D "%TEMP%\rbxprobe.h" --resolve "%DOMAIN%:443:%%I" "https://%DOMAIN%/" >nul 2>&1
        findstr /b /c:"HTTP/" "%TEMP%\rbxprobe.h" >nul 2>&1
        if not errorlevel 1 (
            echo         [ ok ] %%I
            set "PICKED=!PICKED! %%I"
        ) else (
            echo         [ .. ] %%I did not answer
        )
    )
    del "%TEMP%\rbxprobe.h" >nul 2>&1
    if "!PICKED!"=="" (
        echo         nothing answered, falling back to the built-in list
        set "PICKED=%IPS%"
    )
)

echo   [3/4] Writing to the hosts file
echo.>>"%HOSTS%"
>>"%HOSTS%" echo # Roblox thumbnails: tr.rbxcdn.com has no A record in DNS, pinned CDN IPs. Added !TS!.
for %%I in (!PICKED!) do (
    >>"%HOSTS%" echo %%I %DOMAIN%
    echo         %%I %DOMAIN%
)

echo   [4/4] Flushing the DNS cache
ipconfig /flushdns >nul 2>&1
echo         done

if defined RBX_HOSTS goto end

echo.
echo   Check: ping %DOMAIN%
ping -n 2 %DOMAIN% 2>nul | findstr /i /c:"[" /c:"TTL"
echo.
echo   Done. Fully close Roblox and open it again - it caches failed
echo   lookups and will not retry on its own.
echo   To undo: %~nx0 /remove   or   %~nx0 /rollback
goto end

:already
echo   The entries are already there, nothing to change:
echo.
findstr /i /c:"%DOMAIN%" "%HOSTS%"
echo.
echo   If the images are still grey, restart Roblox.
echo   To rewrite them: %~nx0 /remove, then run this script again.
goto end

rem  ------------------------------------------------------------------- remove
:remove
call :require_admin
if errorlevel 1 exit /b 0

if not exist "%WORKDIR%" mkdir "%WORKDIR%" >nul 2>&1
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "TS=%%i"
if not defined TS set "TS=manual"
copy /y "%HOSTS%" "%WORKDIR%\hosts-before-remove-%TS%.txt" >nul 2>&1

set "NEW=%TEMP%\hosts-noroblox.txt"
findstr /v /i /c:"%DOMAIN%" "%HOSTS%" > "%NEW%"
for %%A in ("%NEW%") do if %%~zA LSS 10 (
    echo   The result looks suspiciously empty, aborting.
    del "%NEW%" >nul 2>&1
    goto fail
)
copy /y "%NEW%" "%HOSTS%" >nul 2>&1
del "%NEW%" >nul 2>&1
ipconfig /flushdns >nul 2>&1
echo   Lines with %DOMAIN% removed, DNS cache flushed.
goto end

rem  ----------------------------------------------------------------- rollback
:rollback
call :require_admin
if errorlevel 1 exit /b 0

set "LATEST="
for /f "delims=" %%f in ('dir /b /a-d /o-d "%WORKDIR%\hosts-*.txt" 2^>nul') do (
    if not defined LATEST set "LATEST=%WORKDIR%\%%f"
)
if not defined LATEST (
    echo   No backups found in %WORKDIR%
    goto fail
)
echo   Restoring hosts from %LATEST%
copy /y "%LATEST%" "%HOSTS%" >nul 2>&1
if errorlevel 1 (
    echo   Restore failed.
    goto fail
)
ipconfig /flushdns >nul 2>&1
echo   Done, hosts is back to the state before the install.
goto end

rem  --------------------------------------------------------------------- help
:help
echo   Usage:
echo.
echo     %~nx0              add the entries to hosts
echo     %~nx0 /remove      delete the entries
echo     %~nx0 /rollback    restore hosts from the latest backup
echo     %~nx0 /help        this help
echo.
echo   Backups:  %WORKDIR%
echo   Hosts:    %HOSTS%
goto end

rem  ------------------------------------------------------------------ helpers
:banner
echo.
echo   ==============================================================
echo    Roblox thumbnails fix
echo.
echo    tr.rbxcdn.com does not resolve: DNS hands out a CNAME to
echo    trns1.rbxcdn.com, and that name has no A record. That is why
echo    Roblox shows grey boxes instead of icons and avatars.
echo.
echo    This script pins the name to working CDN addresses in hosts.
echo   ==============================================================
echo.
exit /b 0

:require_admin
if defined RBX_HOSTS exit /b 0
fltmc >nul 2>&1
if not errorlevel 1 exit /b 0
echo   Administrator rights are required, asking for UAC...
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs" >nul 2>&1
if errorlevel 1 echo   Elevation was declined.
exit /b 1

:fail
echo.
echo   That did not work. Nothing was changed, hosts is untouched.
set "RC=1"
goto finish

:end
set "RC=0"

:finish
if not defined NOPAUSE pause
exit /b %RC%
