@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Roblox thumbnails fix

rem  ==========================================================================
rem   fix-roblox-thumbnails.bat
rem
rem   THE PROBLEM
rem   On many Russian ISPs the name tr.rbxcdn.com does not resolve: DNS returns
rem   a CNAME to trns1.rbxcdn.com, and that name has neither an A nor an AAAA
rem   record. Result: grey boxes instead of place thumbnails, game icons,
rem   avatars and screenshots - in the Roblox app, on the website and in Studio.
rem   The API itself still works, so titles, ratings and player counts show up.
rem
rem   WHAT THIS DOES
rem   Pins tr.rbxcdn.com to working CDN addresses in the hosts file.
rem   Each address is probed over HTTPS before it is written.
rem   The script backs up hosts, flushes the DNS cache and reports the result.
rem
rem   THE VERDICT AT THE END IS COLOURED
rem       green  - done, the entries are written
rem       red    - failed, hosts was not touched
rem       cyan   - nothing to do, the entries are already there
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
set "VF=%TEMP%\rbxfix-verdict.txt"

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
    set "FAILNOTE=Could not back up the hosts file, so nothing was written."
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

if defined RBX_HOSTS goto installed

echo.
echo   Check: ping %DOMAIN%
ping -n 2 %DOMAIN% 2>nul | findstr /i /c:"[" /c:"TTL"

:installed
set "RC=0"
>"%VF%" echo.
>>"%VF%" echo   DONE. These lines are now in %HOSTS%:
>>"%VF%" echo.
for %%I in (!PICKED!) do >>"%VF%" echo         %%I %DOMAIN%
>>"%VF%" echo.
>>"%VF%" echo   Close Roblox completely and open it again - it caches failed
>>"%VF%" echo   lookups and will not retry on its own.
>>"%VF%" echo   Undo: %~nx0 /remove   or   %~nx0 /rollback
call :verdict Green
goto finish

:already
set "RC=0"
>"%VF%" echo.
>>"%VF%" echo   NOTHING TO CHANGE. The entries are already in %HOSTS%:
>>"%VF%" echo.
findstr /i /c:"%DOMAIN%" "%HOSTS%" >>"%VF%"
>>"%VF%" echo.
>>"%VF%" echo   If the images are still grey, restart Roblox.
>>"%VF%" echo   To rewrite them: %~nx0 /remove, then run this script again.
call :verdict Cyan
goto finish

rem  ------------------------------------------------------------------- remove
:remove
call :require_admin
if errorlevel 1 exit /b 0

findstr /i /c:"%DOMAIN%" "%HOSTS%" >nul 2>&1
if errorlevel 1 goto nothing_to_remove

if not exist "%WORKDIR%" mkdir "%WORKDIR%" >nul 2>&1
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "TS=%%i"
if not defined TS set "TS=manual"
copy /y "%HOSTS%" "%WORKDIR%\hosts-before-remove-%TS%.txt" >nul 2>&1

set "NEW=%TEMP%\hosts-noroblox.txt"
findstr /v /i /c:"%DOMAIN%" "%HOSTS%" > "%NEW%"
for %%A in ("%NEW%") do if %%~zA LSS 10 (
    echo   The result looks suspiciously empty, aborting.
    del "%NEW%" >nul 2>&1
    set "FAILNOTE=The filtered hosts file came out too short, so the file was left as is."
    goto fail
)
copy /y "%NEW%" "%HOSTS%" >nul 2>&1
if errorlevel 1 (
    del "%NEW%" >nul 2>&1
    set "FAILNOTE=Could not replace the hosts file."
    goto fail
)
del "%NEW%" >nul 2>&1
ipconfig /flushdns >nul 2>&1

set "RC=0"
>"%VF%" echo.
>>"%VF%" echo   DONE. Lines with %DOMAIN% were removed, the DNS cache was flushed.
>>"%VF%" echo   %HOSTS% keeps its other entries.
>>"%VF%" echo   A copy of the file from before this run is in %WORKDIR%
call :verdict Green
goto finish

:nothing_to_remove
set "RC=0"
>"%VF%" echo.
>>"%VF%" echo   NOTHING TO CHANGE. There are no %DOMAIN% lines in %HOSTS%.
call :verdict Cyan
goto finish

rem  ----------------------------------------------------------------- rollback
:rollback
call :require_admin
if errorlevel 1 exit /b 0

set "LATEST="
for /f "delims=" %%f in ('dir /b /a-d /o-d "%WORKDIR%\hosts-*.txt" 2^>nul') do (
    if not defined LATEST set "LATEST=%WORKDIR%\%%f"
)
if not defined LATEST (
    set "FAILNOTE=No backups found in %WORKDIR%"
    goto fail
)
copy /y "%LATEST%" "%HOSTS%" >nul 2>&1
if errorlevel 1 (
    set "FAILNOTE=Could not copy the backup back."
    goto fail
)
ipconfig /flushdns >nul 2>&1

set "RC=0"
>"%VF%" echo.
>>"%VF%" echo   DONE. %HOSTS% was restored from this backup:
>>"%VF%" echo         %LATEST%
>>"%VF%" echo   The DNS cache was flushed.
call :verdict Green
goto finish

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
set "RC=0"
goto finish

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
if errorlevel 1 (
    set "FAILNOTE=Elevation was declined, so nothing was changed."
    echo   Elevation was declined.
)
exit /b 1

rem  Prints the collected verdict lines in the given colour. One PowerShell
rem  call for the whole block; if PowerShell is unavailable they print plain.
:verdict
if not exist "%VF%" exit /b 0
powershell -NoProfile -Command "Get-Content -LiteralPath '%VF%' | ForEach-Object { Write-Host $_ -ForegroundColor %~1 }" 2>nul
if errorlevel 1 type "%VF%"
del "%VF%" >nul 2>&1
exit /b 0

:fail
set "RC=1"
>"%VF%" echo.
>>"%VF%" echo   FAILED. Nothing was changed, %HOSTS% is untouched.
if defined FAILNOTE >>"%VF%" echo.
if defined FAILNOTE >>"%VF%" echo   !FAILNOTE!
call :verdict Red

:finish
if not defined NOPAUSE pause
exit /b %RC%
