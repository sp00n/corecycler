@echo off
echo Starting the CoreCycler...
start cmd.exe /k powershell.exe -executionpolicy bypass -file script-corecycler.ps1
exit