@echo off
rem Opens Rocco on this project. Rocco is installed once per RoDev folder, in _tools\rocco (WORKSTATION.md).
for %%I in ("%~dp0..\..") do set "PROJECT=%%~nxI"
set "ROCCO=%~dp0..\..\..\_tools\rocco\Rocco.bat"
if not exist "%ROCCO%" goto missing
call "%ROCCO%" -Project "%PROJECT%"
exit /b
:missing
echo Rocco is not installed in this RoDev folder. Set it up as in docs\workflow\WORKSTATION.md, step 4:
echo   git clone https://github.com/RowanByrne/rocco.git _tools\rocco
pause
