<#
.DESCRIPTION
    This file is used to add a new Windows Event Log "Source", which is required to be able to use the Windows Event Log
    The name of this new Source is "CoreCycler"
    Adding this Source requires admin rights, which is why it's outsourced into this file, so that we don't need to call
    the main scrip width admin rights
.PARAMETER shouldBeAdmin
    [Mixed] If set (to anything), assume that we are already admin
.OUTPUTS
    [Void]
#>
param(
    $shouldBeAdmin
)


Set-StrictMode -Version 3.0



<#
.DESCRIPTION
    Exit the script and set an error code
.PARAMETER errorCode
    [Int] The error code to set
.OUTPUTS
    [Void]
#>
function Exit-WithErrorCode {
    param(
        [Parameter(Mandatory=$true)] [Int] $errorCode
    )

    $host.SetShouldExit($errorCode)
    exit $errorCode
}



<#
.DESCRIPTION
    Wait for user input before continuing
.OUTPUTS
    [Void]
#>
function Wait-ForUserInput {
    Write-Host
    Write-Host 'Press any key to continue...'
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}



<#
.DESCRIPTION
    Ask the user if we should also add the Custom View in the Event Log
.OUTPUTS
    [Bool]
#>
function Request-ToAddCustomView {
    $title    = 'Do you also want to add a Custom View in the Windows Event Log?'
    $question = 'This Custom View will make it easier to find the CoreCycler entries in the Event Log.' + [Environment]::NewLine + ' '
    $choices  = @(
        [System.Management.Automation.Host.ChoiceDescription]::new('&Yes', 'Add the Custom View in the Windows Event Log')
        [System.Management.Automation.Host.ChoiceDescription]::new('&No', 'Do not add the Custom View')
    )
    $decision = $Host.UI.PromptForChoice($title, $question, $choices, 0)

    if ($decision -eq 0) {
        return $true
    }
    else {
        return $false
    }

    return $false
}



<#
.DESCRIPTION
    Create the XML document for the Event Log Custom View
.OUTPUTS
    [Void]
#>
function Add-XmlFileForCustomView {
    $path     = $Env:ProgramData + '\Microsoft\Event Viewer\Views\'
    $fileName = 'CoreCyclerEventLogCustomView.xml'
    $filePath = Join-Path -Path $path -ChildPath $fileName

    Write-Host

    # File path doesn't exist
    if (!(Test-Path $path -PathType Container)) {
        Write-Host 'The path to put the config file for the Custom View into doesn''t exist!' -ForegroundColor Red
        Write-Host ('(' + $path + ')') -ForegroundColor Red
        Write-Host 'Not trying to create the file' -ForegroundColor Red
        return
    }

    # Skip if the file already exists
    if (Test-Path $filePath -PathType Leaf) {
        Write-Host 'The config file for the Custom View already exists!' -ForegroundColor Red
        Write-Host ('(' + $filePath + ')') -ForegroundColor Red
        Write-Host 'Not adding it again' -ForegroundColor Red
        return
    }


    $xmlText = @'
<ViewerConfig>
    <QueryConfig>
        <QueryParams>
            <Simple>
                <Channel>Application</Channel>
                <RelativeTimeInfo>0</RelativeTimeInfo>
                <Source>CoreCycler</Source>
                <BySource>False</BySource>
            </Simple>
        </QueryParams>
        <QueryNode>
            <Name>CoreCycler</Name>
            <QueryList>
                <Query Id="0" Path="Application">
                    <Select Path="Application">*[System[Provider[@Name='CoreCycler']]]</Select>
                </Query>
            </QueryList>
        </QueryNode>
    </QueryConfig>
</ViewerConfig>
'@


    $createdFile = New-Item -Path $path -Name $fileName -ItemType File -Force

    # The file wasn't created
    if (!(Test-Path $filePath -PathType Leaf)) {
        Write-Host 'Could not create the config file for the Custom View!' -ForegroundColor Red
        Write-Host ('(' + $filePath + ')') -ForegroundColor Red
        return
    }

    try {
        [System.IO.File]::WriteAllLines($createdFile, $xmlText)
        Write-Host 'Custom View added to the Windows Event Log!' -ForegroundColor Green
        Write-Host
    }
    catch {
        Write-Host 'Could not add the XML to the config file for the Custom View!' -ForegroundColor Red
        Write-Host ('(' + $filePath + ')') -ForegroundColor Red
        return
    }
}



<#
.DESCRIPTION
    The main functionality
.OUTPUTS
    [Void]
#>
function Start-Main {
    $areWeAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)


    if (!$areWeAdmin) {
        Write-Host 'We don''t have admin privileges, aborting!' -ForegroundColor Red

        # If the flag is set, don't wait for a keypress, as we're not in a new window
        if (!$shouldBeAdmin) {
            Wait-ForUserInput
        }

        # Set the exit code = error code
        Exit-WithErrorCode 1


        # Not sure if this will work with the rest of the main script
        <#
        Write-Host 'Trying to re-open in a new window with admin privileges'

        # Create a new process object that starts PowerShell
        $newProcess = New-Object System.Diagnostics.ProcessStartInfo "PowerShell"

        # Specify the current script path and name as a parameter with added scope and support for scripts with spaces in it's path
        #$newProcess.Arguments = "& '" + $Script:MyInvocation.MyCommand.Path + "'"
        $newProcess.Arguments = "& '" + $MyInvocation.MyCommand.Path + "'"

        # Indicate that the process should be elevated
        $newProcess.Verb = "runas"

        # Start the new process
        [System.Diagnostics.Process]::Start($newProcess)

        # Exit from the current, unelevated, process
        Exit
        #>
    }
    else {
        try {
            Write-Host 'Creating the Windows Event Log Source "CoreCycler"...'
            Write-Host

            if (-not [System.Diagnostics.EventLog]::SourceExists('CoreCycler')) {
                [System.Diagnostics.EventLog]::CreateEventSource('CoreCycler', 'Application')
                Write-Host 'Successfully created the Event Log Source!' -ForegroundColor Green
                Write-Host

                $addCustomView = Request-ToAddCustomView

                if ($addCustomView) {
                    Add-XmlFileForCustomView
                }
            }
            else {
                Write-Host 'The Source "CoreCycler" already existed, continuing'
            }
        }
        catch {
            Write-Host 'Some error has happened!' -ForegroundColor Red
            Write-Host $_ -ForegroundColor Red

            if (!$shouldBeAdmin) {
                Wait-ForUserInput
            }

            Exit-WithErrorCode 1
        }


        if (!$shouldBeAdmin) {
            Wait-ForUserInput
        }
    }
}


Start-Main