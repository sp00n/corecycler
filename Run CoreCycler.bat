@echo off

REM Build the parameter string
SET "PARAMS="

IF "%~1"=="" GOTO RUN
SET "PARAMS=%PARAMS% -CoreFromAutoMode %1"


:RUN
echo Starting the CoreCycler...
start "CoreCycler" cmd.exe /k powershell.exe -ExecutionPolicy Bypass -File "%~dp0script-corecycler.ps1" %PARAMS%
exit