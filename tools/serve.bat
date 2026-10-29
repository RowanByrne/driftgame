@echo off
setlocal
rem Serves this checkout (repo\ or a lane) into its Studio place with Lync (docs\workflow\LANES.md).
rem A lane has .lane-port (written by add-lane.ps1) and serves a generated lane.project.json on that port.
cd /d "%~dp0.."
for %%i in ("%CD%") do set "NAME=%%~nxi"

set "PROJECT=default.project.json"
set "PORT="
if exist ".lane-port" (
	set "PROJECT=lane.project.json"
	powershell -NoProfile -Command "$j = Get-Content default.project.json -Raw | ConvertFrom-Json; $j.port = [int](Get-Content .lane-port -Raw).Trim(); [IO.File]::WriteAllText('lane.project.json', ($j | ConvertTo-Json -Depth 64))"
)
for /f "usebackq delims=" %%p in (`powershell -NoProfile -Command "(Get-Content '%PROJECT%' -Raw | ConvertFrom-Json).port"`) do set "PORT=%%p"
title Lync - %NAME% (port %PORT%)

rem Lync: the RoDev folder's _tools\lync first (repo\ sits two levels below it, a lane three), then PATH.
set "LYNC="
for %%d in ("..\..\_tools\lync\lync.exe" "..\..\..\_tools\lync\lync.exe") do if not defined LYNC if exist "%%~fd" set "LYNC=%%~fd"
if not defined LYNC for /f "delims=" %%i in ('where lync 2^>nul') do if not defined LYNC set "LYNC=%%i"
if not defined LYNC (
	echo Could not find Lync in the RoDev folder's _tools\lync\ or on PATH.
	echo See docs\workflow\WORKSTATION.md, or get it from https://github.com/Iron-Stag-Games/Lync/releases
	pause
	exit /b 1
)

"%LYNC%" serve "%PROJECT%"
pause
