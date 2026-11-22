@echo off
setlocal
cd /d "%~dp0"
set "KIND_CMD=kind"
if exist "%~dp0bin\kind.exe" set "KIND_CMD=%~dp0bin\kind.exe"

echo Deleting Kind 3-node cluster k8s-68130677...
"%KIND_CMD%" delete cluster --name k8s-68130677
echo Done. (To remove hosts entries as well, delete lines containing 68130677.com from hosts file)
endlocal
