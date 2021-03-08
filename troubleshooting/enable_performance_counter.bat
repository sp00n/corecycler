:: This batch file tries to re-enable the Windows Perfomance Counters
:: Query the status of the PerfProc counter:
:: lodctr.exe /q:PerfProc
:: Check the registry key:
:: reg.exe query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\PerfProc\Performance /s
::
:: There are also a couple of howtos:
:: https://leansentry.zendesk.com/hc/en-us/articles/360038645792-How-to-Fix-performance-counter-issues
:: https://docs.microsoft.com/en-US/troubleshoot/windows-server/performance/manually-rebuild-performance-counters
:: 

@echo off
SETLOCAL EnableExtensions EnableDelayedExpansion

SET "foundPlaService=0"
SET "foundIPHelperService=0"
SET "foundWinmgmtService=0"
SET "logFileCount=0"
SET "logFilePath=C:\PerfLogs\Admin\"


echo Trying to re-enable resp. fix the Windows Performance Counters ^(PerfProc^)
echo -------------------------------------------------------------------------


:: We need administrator rights
net session >nul 2>&1

if %ErrorLevel% NEQ 0 (
    echo Fatal Error: This script requires administrator privileges!
    pause
    GOTO :EOF
)


echo Enabling the Performance Counter in the registry...
Reg add HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\PerfProc\Performance /v "Disable Performance Counters" /t REG_DWORD /d 0 /f >nul 2>&1

if %ErrorLevel% NEQ 0 (
    echo FATAL ERROR: Could not write the registry key!
    pause
    GOTO :EOF
) else (
    echo ... successfully added the registry key
)


echo.
echo Registering the Performance Counter...
%windir%\system32\lodctr /R >nul 2>&1

:: This may fail on the first execution
:: So just try again
if %ErrorLevel% NEQ 0 (
    %windir%\system32\lodctr /R >nul 2>&1
)

:: Second try still failed
if %ErrorLevel% NEQ 0 (
    echo FATAL ERROR: Could not register the Performance Counter for system32
    pause
    GOTO :EOF
) else (
    echo ... successfully registered for system32
)


%windir%\sysWOW64\lodctr /R >nul 2>&1

:: This may fail on the first execution aswell?
:: So just try again
if %ErrorLevel% NEQ 0 (
    %windir%\sysWOW64\lodctr /R >nul 2>&1
)

if %ErrorLevel% NEQ 0 (
    echo FATAL ERROR: Could not register the Performance Counter for sysWOW64
    pause
    GOTO :EOF
) else (
    echo ... successfully registered for sysWOW64
)

echo.
echo Resyncing the Performance Counter...
%windir%\system32\wbem\winmgmt.exe /resyncperf >nul 2>&1

if %ErrorLevel% NEQ 0 (
    echo FATAL ERROR: Could not resync the Performance Counter!
    pause
    GOTO :EOF
) else (
    echo ... successfully synced
)




:: Restart services
:: Quick check: sc query servicename

:: The Performance Logs and Alerts service
:: ErrorLevels for FINDSTR
:: 0: The search was completed successfully and at least one match was found
:: 1: The search was completed successfully, but no matches were found
:: 2: The search was not completed successfully (wrong syntax)
:: An invalid switch will only print an error message in error stream
call wmic /locale:ms_409 service where (name="pla") get state /value | findstr /I /C:"State=Running" >nul

:: The iphlpsvc is running, stop it and set a flag to re-enable it later
if %ErrorLevel% EQU 0 (
    SET "foundPlaService=1"
)


if "%foundPlaService%" == "1" (
    echo.
    echo Stopping and restarting the Performance Logs and Alerts service...
    net stop pla >nul 2>&1

    if %ErrorLevel% NEQ 0 (
        echo FATAL ERROR: Could not stop the Performance Logs and Alerts service!
        pause
        GOTO :EOF
    ) else (
        echo ... successfully stopped
    )


    net start pla >nul 2>&1

    if %ErrorLevel% NEQ 0 (
        echo FATAL ERROR: Could not start the Performance Logs and Alerts service!
        pause
        GOTO :EOF
    ) else (
        echo ... successfully restarted
    )
)


:: The IP Helper service depends on the Windows Management Instrumentation service, so we need to stop it first

:: ErrorLevels for FINDSTR
:: 0: The search was completed successfully and at least one match was found
:: 1: The search was completed successfully, but no matches were found
:: 2: The search was not completed successfully (wrong syntax)
:: An invalid switch will only print an error message in error stream
call wmic /locale:ms_409 service where (name="iphlpsvc") get state /value | findstr /I /C:"State=Running" >nul

:: The iphlpsvc is running, stop it and set a flag to re-enable it later
if %ErrorLevel% EQU 0 (
    SET "foundIPHelperService=1"
)


if "%foundIPHelperService%" == "1" (
    echo.
    echo Stopping the IP Helper service...
    net stop iphlpsvc >nul 2>&1

    if %ErrorLevel% NEQ 0 (
        echo FATAL ERROR: Could not stop the IP Helper service!
        pause
        GOTO :EOF
    ) else (
        echo ... successfully stopped
    )
)



:: And the Windows Management Instrumentation service

:: ErrorLevels for FINDSTR
:: 0: The search was completed successfully and at least one match was found
:: 1: The search was completed successfully, but no matches were found
:: 2: The search was not completed successfully (wrong syntax)
:: An invalid switch will only print an error message in error stream
call wmic /locale:ms_409 service where (name="winmgmt") get state /value | findstr /I /C:"State=Running" >nul

:: The iphlpsvc is running, stop it and set a flag to re-enable it later
if %ErrorLevel% EQU 0 (
    SET "foundWinmgmtService=1"
)


if "%foundWinmgmtService%" == "1" (
    echo.
    echo Stopping and restarting the Windows Management Instrumentation service...
    net stop winmgmt >nul 2>&1

    if %ErrorLevel% NEQ 0 (
        echo FATAL ERROR: Could not stop the Windows Management Instrumentation service!
        pause
        GOTO :EOF
    ) else (
        echo ... successfully stopped
    )


    net start winmgmt >nul 2>&1

    if %ErrorLevel% NEQ 0 (
        echo FATAL ERROR: Could not start the Windows Management Instrumentation service!
        pause
        GOTO :EOF
    ) else (
        echo ... successfully restarted
    )
)


:: Restart the IP Helper service
:: This needs to be done after the Windows Management Instrumentation service was restarted
if "%foundIPHelperService%" == "1" (
    echo.
    echo Starting the IP Helper service...
    net start iphlpsvc >nul 2>&1

    if %ErrorLevel% NEQ 0 (
        echo FATAL ERROR: Could not start the IP Helper service!
        pause
        GOTO :EOF
    ) else (
        echo ... successfully restarted
    )
)


:: Delete old log files
:DELLOGFILES
FOR %%i in (%logFilePath%*) DO SET /A "logFileCount+=1"



if "%logFileCount%" GTR "0" (
    echo.
    echo Found %logFileCount% log file^(s^) in %logFilePath%, which may prevent the Process Counter from working correctly.
    choice /N /C:YN /M "Do you want to delete these log files? [Y/N]"

    if !ErrorLevel! == 255 (
        echo There was some error, could not delete the log files
    ) else if !ErrorLevel! == 2 (
        echo Not deleting the log files
    ) else if !ErrorLevel! == 1 (
        echo Deleting old log files...
        REM del /Q C:\PerfLogs\Admin\*.*
        del /F /Q C:\PerfLogs\Admin\*.*

        REM Check the amount of files again
        SET /A "logFileCountAfter=0"
        FOR %%i in (!logFilePath!*) DO SET /a "logFileCountAfter+=1"
        SET /A numDeletedFiles=!logFileCount!-!logFileCountAfter!

        echo Deleted !numDeletedFiles! file^(s^)
    ) else if !ErrorLevel! == 0 (
        REM aborted the choice
        echo Not deleting the log files
    )
)


echo.
echo The Performance Counter should now be reset.
pause
ENDLOCAL