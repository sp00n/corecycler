<#
.AUTHOR
    sp00n
.LINK
    https://github.com/sp00n/corecycler
.LICENSE
    Creative Commons "CC BY-NC-SA"
    https://creativecommons.org/licenses/by-nc-sa/4.0/
    https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode
.DESCRIPTION
    This is the script that is being called by the Scheduled Task for Automatic Testing
    and tries to resume the testing process
#>
Set-StrictMode -Version 3.0



$logBuffer         = [System.Collections.ArrayList]::new()
$canUseLogFile     = $false
$logFileCoreCycler = $null

$taskName          = 'CoreCycler AutoMode Startup Task'
$taskPath          = '\CoreCycler\'

# This file is in \helpers, our main script is one level above
$scriptRoot        = Split-Path -Path $PSScriptRoot -Parent
$autoModeFile      = $scriptRoot + '\.automode'
$maxTimeLimit      = 12 * 60 * 60



<#
.DESCRIPTION
    Write a message to the screen and to the log file
.PARAMETER text
    [String] The text to output
.PARAMETER NoNewline
    [Switch] (optional) If set, will not end the line after the text
.OUTPUTS
    [Void]
#>
function Write-Text {
    param(
        [Parameter(Mandatory=$true)] $text,
        [Parameter(Mandatory=$false)] [Switch] $NoNewline
    )

    $paramsLog = @{
        'string'    = $text
        'NoNewline' = $NoNewline.IsPresent
    }

    $paramsText = @{
        'Object'    = $paramsLog['string']
        'NoNewline' = $paramsLog['NoNewline']
    }

    Write-Host @paramsText
    Write-LogEntry @paramsLog
}



<#
.DESCRIPTION
    Write a string to the log file
.PARAMETER string
    [String] The string to log
.PARAMETER NoNewline
    [Switch] (optional) If set, will no end the line after the text
.OUTPUTS
    [Void]
#>
function Write-LogEntry {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()] [String] $string,
        [Parameter(Mandatory=$false)] [Switch] $NoNewline
    )

    # If we cannot use the logfile (yet), store the messages in a buffer
    if (!$canUseLogFile) {
        [Void] $Script:logBuffer.Add($string)
        return
    }

    # The second parameter defines if to append ($true) or overwrite ($false)
    $stream = [System.IO.StreamWriter]::new($logFileCoreCycler, $true, ([System.Text.Utf8Encoding]::new()))

    if ($NoNewline.IsPresent) {
        $stream.Write($string)
    }
    else {
        $stream.WriteLine($string)
    }

    $stream.Close()
}



<#
.DESCRIPTION
    Remove the existing startup script
#>
function Remove-StartupTask {
    Write-Text('Removing the startup task "' + $taskPath + '\' + $taskName + '"')
    Write-Text('')
    Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false
}



<#
.DESCRIPTION
    Exit the script
#>
function Exit-Script {
    Write-Text('')
    Write-Text('The startup script has finished')
    Write-Text('Press any key to close the window...')
    Write-Text('')
    Write-Text('')
    Write-Text('')

    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit
}



<#
.DESCRIPTION
    This is a custom exception, just to get out of the try {} block without throwing an actual error
#>
class EndTryBlockException: System.Exception {
    EndTryBlockException([string] $x) :
        base('Try-Block Exit Exception. Message: ' + $x) {}
}



<#
.DESCRIPTION
    Another custom exception that does show an error message, but no extended information
#>
class AutoModeResumeFailedException: System.Exception {
    AutoModeResumeFailedException([string] $x) :
        base('Auto Mode resume failed.' + [Environment]::NewLine + $x) {}
}



# The main functionality
try {
    $startDate = Get-Date
    $formatDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $curTimeStamp = Get-Date -UFormat %s -Millisecond 0

    # Limit the maximum time between when the test was started and when the resume script was started
    $limitTimestamp = $curTimeStamp - $maxTimeLimit


    Write-Text('')
    Write-Text('┌────────────────────────────────────────────┐')
    Write-Text('│    CoreCycler Auto Mode Recovery Script    │')
    Write-Text('└────────────────────────────────────────────┘')
    Write-Text('')
    Write-Text($formatDate)
    Write-Text('Recovering from an unexpected exit (crash/reboot)')
    Write-Text('')


    # We need to be admin to use the Auto Test Mode
    $weAreAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (!$weAreAdmin) {
        throw [AutoModeResumeFailedException] 'We don''t have admininstrator privileges, aborting!'
    }



    if (!(Test-Path $autoModeFile -PathType Leaf)) {
        Write-Text('The .automode file does not exist!')
        Write-Text('The file is needed to be able to continue the testing process, aborting.')
        Write-Text('(Looking for: ' + $autoModeFile + ')')
        Write-Text('')

        Remove-StartupTask
        
        throw [EndTryBlockException] 'The .automode file does not exist, aborting!'
    }



    # Try to get the info from the .automode file
    Write-Text('Parsing the .automode file:')
    Write-Text($autoModeFile)
    Write-Text('')

    $reader = [System.IO.File]::OpenText($autoModeFile)
    $autoModeFileContentString = $reader.ReadToEnd().Trim()
    $reader.Close()
    $autoModeFileContent = @($autoModeFileContentString -Split '\r?\n')

    if (!$autoModeFileContent -or $autoModeFileContent.Count -lt 5) {
        throw [AutoModeResumeFailedException] 'Possible corruption detected, the .automode file doesn''t contain all required information!'
    }

    $fileTimestamp     = [UInt64] $autoModeFileContent[0]
    $coreTested        = [Int] $autoModeFileContent[1]
    $logFileCoreCycler = [String] $autoModeFileContent[2]
    $logFileStressTest = [String] $autoModeFileContent[3]
    $voltageInfo       = [String] $autoModeFileContent[4]

    Write-Text('Timestamp:           ' + $fileTimestamp)
    Write-Text('Tested Core:         ' + $coreTested)
    Write-Text('Logfile CoreCycler:  ' + $logFileCoreCycler)
    Write-Text('Logfile Stress Test: ' + $logFileStressTest)
    Write-Text('Voltage Settings:    ' + $voltageInfo)
    Write-Text('')


    # Try to use the log file
    if (!(Test-Path $logFileCoreCycler -PathType Leaf)) {
        Write-Text('The CoreCycler log file doesn''t exist, generating')
        Write-Text('')
        $null = New-Item $logFileCoreCycler -ItemType File -Force
    }


    # The log file exists now, dump all the previous messages to it
    $canUseLogFile = $true

    if ($logBuffer.Count -gt 0) {
        forEach ($logEntry in $logBuffer) {
            Write-LogEntry $logEntry
        }

        $logBuffer = $null
    }


    if ($fileTimestamp -lt $limitTimestamp) {
        $actualTimeDiff = $curTimeStamp - $fileTimestamp
        throw [AutoModeResumeFailedException] ('The resume timestamp is too long ago (too much time has passed: ' + [Math]::Round($actualTimeDiff / 60 / 60, 1) + ' hours, max: ' + [Math]::Round($limitTime / 60 / 60, 1) + ' hours)')
    }

    Write-Text('Re-starting CoreCycler...')
    Write-Text('')


    # Start the script now
    Write-Text('Command:')
    Write-Text('Start-Process -PassThru -FilePath ''cmd.exe'' -ArgumentList @(''/C'', (''"' + $scriptRoot + '\Run CoreCycler.bat"''), ' + $coreTested + ')')

    $process = Start-Process -PassThru -FilePath 'cmd.exe' -ArgumentList @('/C', ('"' + $scriptRoot + '\Run CoreCycler.bat"'), $coreTested)
}

# Don't throw an error
catch [EndTryBlockException] {
}

catch [AutoModeResumeFailedException] {
    Write-Text('')
    Write-Text('ERROR:')
    Write-Text($_.Exception.Message)
}

catch {
    Write-Text('')
    Write-Text('ERROR:')
    Write-Text($_)
}

finally {
    Exit-Script
}
