@echo off
echo Starting the CoreCycler...
start "CoreCycler" cmd.exe /k powershell.exe -ExecutionPolicy Bypass -File "%~dp0script-corecycler.ps1"
exit