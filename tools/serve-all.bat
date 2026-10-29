@echo off
rem Starts Lync for the Main place and every lane this PC opens (docs\game\PROJECT.md "Workstations").
rem   serve-all.bat dry   lists what it would start, without starting anything
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve-all.ps1" %*
if /i "%~1"=="dry" pause
