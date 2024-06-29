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
    Write-Output 'Press any key to continue...'
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}




$areWeAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)


if (!$areWeAdmin) {
    Write-Output 'We don''t have admin privileges, aborting!'

    # If the flag is set, don't wait for a keypress, as we're not in a new window
    if (!$shouldBeAdmin) {
        Wait-ForUserInput
    }

    # Set the exit code = error code
    Exit-WithErrorCode 1


    # Not sure if this will work with the rest of the main script
    <#
    Write-Output 'Trying to re-open in a new window with admin privileges'
    
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
        Write-Output 'Creating the Event Log Source "CoreCycler"'

        if (-not [System.Diagnostics.EventLog]::SourceExists('CoreCycler')) {
            [System.Diagnostics.EventLog]::CreateEventSource('CoreCycler', 'Application')
            Write-Output 'Successfully created the Source'
        }
        else {
            Write-Output 'The Source "CoreCycler" already existed, continuing'
        }
    }
    catch {
        Write-Output 'Some error has happened:'
        Write-Output $_

        if (!$shouldBeAdmin) {
            Wait-ForUserInput
        }

        Exit-WithErrorCode 1
    }


    if (!$shouldBeAdmin) {
        Wait-ForUserInput
    }
}

