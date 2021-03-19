<#
.AUTHOR
    sp00n
.VERSION
    0.8.0.0 RC1
.DESCRIPTION
    Sets the affinity of the selected stress test program process to only one core and cycles through
    all the cores to test the stability of a Curve Optimizer setting
.LINK
    https://github.com/sp00n/corecycler
.LICENSE
    Creative Commons "CC BY-NC-SA"
    https://creativecommons.org/licenses/by-nc-sa/4.0/
    https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode
.NOTE
    Please excuse my amateurish code in this file, it's my first attempt at writing in PowerShell ._.
#>

# Global variables
$version                   = '0.8.0.0 RC1'
$curDateTime               = Get-Date -format yyyy-MM-dd_HH-mm-ss
$logFilePath               = 'logs'
$logFilePathAbsolute       = $PSScriptRoot + '\' + $logFilePath + '\'
$logFileName               = $null
$logFileFullPath           = $null
$settings                  = $null
$selectedStressTestProgram = $null
$windowProcess             = $null
$windowProcessId           = $null
$stressTestProcess         = $null
$stressTestProcessId       = $null
$processCounterPathId      = $null
$processCounterPathTime    = $null
$coresWithError            = $null
$coresWithErrorsCounter    = $null
$previousError             = $null
$stressTestConfigFileName  = $null
$stressTestConfigFilePath  = $null
$stressTestLogFileName     = $null
$stressTestLogFilePath     = $null


# Stress test program executables and paths
$stressTestPrograms = @{
    'prime95' = @{
        'displayName'        = 'Prime95'
        'processName'        = 'prime95'
        'processNameExt'     = 'exe'
        'processNameForLoad' = 'prime95'
        'processPath'        = 'test_programs\p95'
        'absolutePath'       = $null
        'fullPathToExe'      = $null
        'testModes'          = @(
            'SSE',
            'AVX',
            'AVX2',
            'CUSTOM'
        )
        'windowNames'        = @(
            '^Prime95 \- Self\-Test$',
            '^Prime95 \- Not running$',
            '^Prime95 \- Waiting for work$',
            '^Prime95$'
        )
    }

    'aida64' = @{
        'displayName'        = 'Aida64'
        'processName'        = 'aida64'
        'processNameExt'     = 'exe'
        'processNameForLoad' = 'aida_bench64.dll'   # This needs to be with file extension
        'processPath'        = 'test_programs\aida64'
        'absolutePath'       = $null
        'fullPathToExe'      = $null
        'testModes'          = @(
            'CACHE',
            'RAM'
        )
        'windowNames'        = @(
            '^System Stability Test \- AIDA64*'
        )
    }

    'ycruncher' = @{
        'displayName'        = "Y-Cruncher"
        'processName'        = '' # Depends on the selected modeYCruncher
        'processNameExt'     = 'exe'
        'processNameForLoad' = '' # Depends on the selected modeYCruncher
        'processPath'        = 'test_programs\y-cruncher\Binaries'
        'absolutePath'       = $null
        'fullPathToExe'      = $null
        'testModes'          = @(
            '00-x86',
            '04-P4P',
            '05-A64 ~ Kasumi',
            '08-NHM ~ Ushio',
            '11-SNB ~ Hina',
            '13-HSW ~ Airi',
            '14-BDW ~ Kurumi',
            '17-ZN1 ~ Yukina',
            '19-ZN2 ~ Kagari',
            
            # The following settings would be available, but they don't run on Ryzen CPUs
            '11-BD1 ~ Miyu',
            '17-SKX ~ Kotori',
            '18-CNL ~ Shinoa'
        )
        'windowNames'        = @(
            '' # Depends on the selected modeYCruncher
        )
    }
}

foreach ($testProgram in $stressTestPrograms.GetEnumerator()) {
    $stressTestPrograms[$testProgram.Name]['absolutePath']  = $PSScriptRoot + '\' + $testProgram.Value['processPath'] + '\'
    $stressTestPrograms[$testProgram.Name]['fullPathToExe'] = $testProgram.Value['absolutePath'] + $testProgram.Value['processName']
}


# Programs where both the main window and the stress test are the same process
$stressTestProgramsWithSameProcess = @(
    'prime95', 'ycruncher'
)



# Used to get around the localized counter names
$englishCounterNames = @(
    'Process',
    'ID Process',
    '% Processor Time'

    # Possible future use
    #'Processor Information',
    #'% Processor Performance',
    #'% Processor Utility'
)

# This stores the Name:ID pairs of the english counter names
$counterNameIds = @{}

# This holds the localized counter names
# Stores the strings returned by Get-PerformanceCounterLocalName
$counterNames = @{
    'Process'                 = ''
    'ID Process'              = ''
    '% Processor Time'        = ''
    'Processor Information'   = ''
    '% Processor Performance' = ''
    '% Processor Utility'     = ''
    'FullName'                = ''
    'SearchString'            = ''
    'ReplaceString'           = ''
}


# The number of physical and logical cores
# This also includes hyperthreading resp. SMT (Simultaneous Multi-Threading)
# We currently only test the first core for each hyperthreaded "package",
# so e.g. only 12 cores for a 24 threaded Ryzen 5900x
# If you disable hyperthreading / SMT, both values should be the same
$processor       = Get-WMIObject Win32_Processor
$numLogicalCores = $($processor | Measure-Object -Property NumberOfLogicalProcessors -sum).Sum
$numPhysCores    = $($processor | Measure-Object -Property NumberOfCores -sum).Sum


# Set the flag if Hyperthreading / SMT is enabled or not
$isHyperthreadingEnabled = ($numLogicalCores -gt $numPhysCores)


# Add code definitions so that we can close a window even if it's minimized to the tray
# The regular PowerShell way unfortunetely doesn't work in this case
$GetWindowDefinition = @'
    using System;
    using System.Text;
    using System.Collections.Generic;
    using System.Runtime.InteropServices;
    
    namespace Api {
        public class WinStruct {
            public string WinTitle {get; set; }
            public int MainWindowHandle { get; set; }
            public int ProcessId { get; set; }
        }
         
        public class ApiDef {
            private delegate bool CallBackPtr(int hwnd, int lParam);
            private static CallBackPtr callBackPtr = Callback;
            private static List<WinStruct> _WinStructList = new List<WinStruct>();

            [DllImport("User32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            private static extern bool EnumWindows(CallBackPtr lpEnumFunc, IntPtr lParam);

            [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
            static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
            
            [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
            static extern int GetWindowThreadProcessId(IntPtr hWnd, out int ProcessId);
            
            private static bool Callback(int hWnd, int lparam) {
                StringBuilder sb = new StringBuilder(256);
                int res = GetWindowText((IntPtr)hWnd, sb, 256);
                int pId;
                int tId = GetWindowThreadProcessId((IntPtr)hWnd, out pId);
                _WinStructList.Add(new WinStruct { MainWindowHandle = hWnd, WinTitle = sb.ToString(), ProcessId = pId });
                return true;
            }  

            public static List<WinStruct> GetWindows() {
                _WinStructList = new List<WinStruct>();
                EnumWindows(callBackPtr, IntPtr.Zero);
                return _WinStructList;
            }
        }
    }
'@

$CloseWindowDefinition = @'
    using System;
    using System.Runtime.InteropServices;
    
    public static class Win32 {
        public static uint WM_CLOSE = 0x10;

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = false)]
        public static extern IntPtr SendMessage(IntPtr hWnd, UInt32 Msg, IntPtr wParam, IntPtr lParam);
    }
'@



<##
 # Write a message to the screen and to the log file
 # .PARAM string $text The text to output
 # .RETURN void
 #>
function Write-Text {
    param(
        $text
    )
    
    Write-Host $text
    Add-Content $logFileFullPath ($text)
}


<##
 # Write an error message to the screen and to the log file
 # .PARAM array $errorArray An array with the text entries to output
 # .RETURN void
 #>
function Write-ErrorText {
    param(
        $errorArray
    )

    foreach ($entry in $errorArray) {
        $lines  = @()
        $lines += $entry.Exception.Message
        $lines += $entry.InvocationInfo.PositionMessage
        $lines += ('    + CategoryInfo          : ' + $entry.CategoryInfo.Category + ': (' + $entry.CategoryInfo.TargetName + ':' + $entry.CategoryInfo.TargetType + ') [' + $entry.CategoryInfo.Activity + '], ' + $entry.CategoryInfo.Reason)
        $lines += ('    + FullyQualifiedErrorId : ' + $entry.FullyQualifiedErrorId)
        $string = $lines | Out-String

        Write-Host $string -ForegroundColor Red
        Add-Content $logFilePath ($string)
    }
}


<##
 # Write a message to the screen with a specific color and to the log file
 # .PARAM string $text The text to output
 # .PARAM string $foregroundColor The foreground color
 # .PARAM string $backgroundColor (optional) The background color
 # .RETURN void
 #>
function Write-ColorText {
    param(
        $text,
        $foregroundColor,
        $backgroundColor
    )

    # -ForegroundColor <ConsoleColor>
    # -BackgroundColor <ConsoleColor>
    # Black, DarkBlue, DarkGreen, DarkCyan, DarkRed, DarkMagenta, DarkYellow, Gray, DarkGray, Blue, Green, Cyan, Red, Magenta, Yellow, White
    if ($backgroundColor) {
        Write-Host $text -ForegroundColor $foregroundColor -BackgroundColor $backgroundColor
    }
    else {
        Write-Host $text -ForegroundColor $foregroundColor
    }

    Add-Content $logFileFullPath ($text)
}


<##
 # Write a message to the screen and to the log file
 # Verbosity / Debug output
 # .PARAM string $text The text to output
 # .RETURN void
 #>
function Write-Verbose {
    param(
        $text
    )
    
    if ($settings.Logging.verbosityMode) {
        if ($settings.Logging.verbosityMode -gt 1) {
            Write-Host(''.PadLeft(11, ' ') + '      + ' + $text)
        }

        Add-Content $logFileFullPath (''.PadLeft(11, ' ') + '      + ' + $text)
    }

}


<##
 # Exit the script
 # .PARAM string $text (optional) The text to display
 # .RETURN void
 #>
function Exit-Script {
    param(
        $text
    )

    if ($text) {
        Write-Text($text)
    }

    Read-Host -Prompt 'Press Enter to exit'
    exit
}


<##
 # Throw a fatal error and exit the script
 # .PARAM string $text (optional) The text to display
 # .RETURN void
 #>
function Exit-WithFatalError {
    param(
        $text
    )

    if ($text) {
        Write-ColorText('FATAL ERROR: ' + $text) Red
    }

    Read-Host -Prompt 'Press Enter to exit'
    exit
}


<##
 # Get the localized counter name
 # Yes, they're localized. Way to go Microsoft!
 # .SOURCE https://www.powershellmagazine.com/2013/07/19/querying-performance-counters-from-powershell/
 # .PARAM Int $ID The id of the counter name. See the link above on how to get the IDs
 # .RETURN String The localized name
 #>
function Get-PerformanceCounterLocalName {
    param (
        [UInt32]
        $ID,
        $ComputerName = $env:COMPUTERNAME
    )

    $code = '[DllImport("pdh.dll", SetLastError=true, CharSet=CharSet.Unicode)] public static extern UInt32 PdhLookupPerfNameByIndex(string szMachineName, uint dwNameIndex, System.Text.StringBuilder szNameBuffer, ref uint pcchNameBufferSize);'

    $Buffer = New-Object System.Text.StringBuilder(1024)
    [UInt32]$BufferSize = $Buffer.Capacity

    $t = Add-Type -MemberDefinition $code -PassThru -Name PerfCounter -Namespace Utility
    $rv = $t::PdhLookupPerfNameByIndex($ComputerName, $ID, $Buffer, [Ref]$BufferSize)

    if ($rv -eq 0) {
        $Buffer.ToString().Substring(0, $BufferSize-1)
    }
    else {
        Throw 'Get-PerformanceCounterLocalName : Unable to retrieve localized name. Check computer name and performance counter ID.'
    }
}


<##
 # This is used to get the Performance Counter IDs, which will be used to get the localized names
 # .PARAM Array $englishCounterNames An arraay with the english names of the counters
 # .RETURN Hash A hash with Name:ID pairs of the counters
 #>
function Get-PerformanceCounterIDs {
    param (
        [Parameter(Mandatory=$true)]
        [Array]
        $englishCounterNames
    )

    $key          = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib\009'
    $allCounters  = (Get-ItemProperty -Path $key -Name Counter).Counter
    $numCounters  = $allCounters.Count
    $countersHash = @{}
    
    # The string contains two-line pairs
    # The first line is the ID
    # The second line is the name
    for ($i = 0; $i -lt $numCounters; $i += 2) {
        $counterId   = [Int]$allCounters[$i]
        $counterName = [String]$allCounters[$i+1]

        if ($englishCounterNames.Contains($counterName) -and !$countersHash.ContainsKey($counterName)) {
            $countersHash[$counterName] = $counterId
        }

    }

    return $countersHash
}


############################################################################## 
## 
## Invoke-WindowsApi.ps1 
##
## http://www.leeholmes.com/blog/2007/10/02/managing-ini-files-with-powershell/
##
## From PowerShell Cookbook (O’Reilly) 
## by Lee Holmes (http://www.leeholmes.com/guide) 
## 
## Invoke a native Windows API call that takes and returns simple data types. 
## 
## ie: 
## 
## ## Prepare the parameter types and parameters for the  
## CreateHardLink function 
## $parameterTypes = [string], [string], [IntPtr] 
## $parameters = [string] $filename, [string] $existingFilename, [IntPtr]::Zero 
##  
## ## Call the CreateHardLink method in the Kernel32 DLL 
## $result = Invoke-WindowsApi "kernel32" ([bool]) "CreateHardLink" ` 
##     $parameterTypes $parameters 
## 
############################################################################## 
# Unfortunately this introduces a memory leak when called multiple times in a row
############################################################################## 
function Invoke-WindowsApi {
    param(
        [string] $dllName, 
        [Type] $returnType, 
        [string] $methodName,
        [Type[]] $parameterTypes,
        [Object[]] $parameters
    )

    ## Begin to build the dynamic assembly
    $domain   = [AppDomain]::CurrentDomain
    $name     = New-Object Reflection.AssemblyName 'PInvokeAssembly'

    # TODO: This is potentially huge memory hog!
    # Only really noticable when using Aida64 though
    # Maybe this? https://stackoverflow.com/questions/2503645/reflect-emit-dynamic-type-memory-blowup
    $assembly = $domain.DefineDynamicAssembly($name, 'Run')
    
    $module   = $assembly.DefineDynamicModule('PInvokeModule')
    $type     = $module.DefineType('PInvokeType', "Public,BeforeFieldInit")

    ## Go through all of the parameters passed to us.  As we do this,
    ## we clone the user's inputs into another array that we will use for
    ## the P/Invoke call.  
    $inputParameters = @()
    $refParameters = @()

    for ($counter = 1; $counter -le $parameterTypes.Length; $counter++) {
       ## If an item is a PSReference, then the user 
       ## wants an [out] parameter.
       if ($parameterTypes[$counter - 1] -eq [Ref]) {
          ## Remember which parameters are used for [Out] parameters
          $refParameters += $counter

          ## On the cloned array, we replace the PSReference type with the 
          ## .Net reference type that represents the value of the PSReference, 
          ## and the value with the value held by the PSReference.
          $parameterTypes[$counter - 1] = $parameters[$counter - 1].Value.GetType().MakeByRefType()
          $inputParameters += $parameters[$counter - 1].Value
       }
       else {
          ## Otherwise, just add their actual parameter to the
          ## input array.
          $inputParameters += $parameters[$counter - 1]
       }
    }

    ## Define the actual P/Invoke method, adding the [Out]
    ## attribute for any parameters that were originally [Ref] 
    ## parameters.
    $method = $type.DefineMethod($methodName, 'Public,HideBySig,Static,PinvokeImpl', $returnType, $parameterTypes)
    
    foreach ($refParameter in $refParameters) {
       [void] $method.DefineParameter($refParameter, "Out", $null)
    }

    ## Apply the P/Invoke constructor
    $ctor = [Runtime.InteropServices.DllImportAttribute].GetConstructor([string])
    $attr = New-Object Reflection.Emit.CustomAttributeBuilder $ctor, $dllName
    $method.SetCustomAttribute($attr)

    ## Create the temporary type, and invoke the method.
    $realType = $type.CreateType()
    $realType.InvokeMember($methodName, 'Public,Static,InvokeMethod', $null, $null, $inputParameters)

    ## Finally, go through all of the reference parameters, and update the
    ## values of the PSReference objects that the user passed in.
    foreach ($refParameter in $refParameters) {
       $parameters[$refParameter - 1].Value = $inputParameters[$refParameter - 1]
    }


    # Cleanup
    # But it doesn't help
    # So this might be an issue with .NET / C# itself?
    # For example this? https://stackoverflow.com/questions/2503645/reflect-emit-dynamic-type-memory-blowup
    $dllName         = $null
    $returnType      = $null
    $methodName      = $null
    $parameters      = $null
    $domain          = $null
    $name            = $null
    $assembly        = $null
    $module          = $null
    $type            = $null
    $counter         = $null
    $inputParameters = $null
    $refParameters   = $null
    $method          = $null
    $ctor            = $null
    $attr            = $null
    $realType        = $null
    $parameterTypes  = $null
    $refParameter    = $null
    
    Remove-Variable -Force -Name 'dllName'
    Remove-Variable -Force -Name 'returnType'
    Remove-Variable -Force -Name 'methodName'
    Remove-Variable -Force -Name 'parameters'
    Remove-Variable -Force -Name 'domain'
    Remove-Variable -Force -Name 'name'
    Remove-Variable -Force -Name 'assembly'
    Remove-Variable -Force -Name 'module'
    Remove-Variable -Force -Name 'type'
    Remove-Variable -Force -Name 'counter'
    Remove-Variable -Force -Name 'inputParameters'
    Remove-Variable -Force -Name 'refParameters'
    Remove-Variable -Force -Name 'method'
    Remove-Variable -Force -Name 'ctor'
    Remove-Variable -Force -Name 'attr'
    Remove-Variable -Force -Name 'realType'
    Remove-Variable -Force -Name 'parameterTypes'
    Remove-Variable -Force -Name 'refParameter'
    
    [System.GC]::Collect()
}


<##
 # Suspends a process
 # Unfortunately this introduces a memory leak on multiple calls (resp. Invoke-WindowsApi does)
 # .PARAM [System.Diagnostics.Process] $process The process to suspend
 # .RETURN [Int] The number of suspended threads from this process. -1 if something failed
 #>
function Suspend-Process {
    param(
        [Parameter(Mandatory=$true)]
        [System.Diagnostics.Process]$process
    )

    if (!$process) {
        return -2
    }

    Write-Verbose('Suspending process:')
    Write-Verbose($process.Id.ToString() + ' - ' + $process.ProcessName.ToString())

    $numThreads = 0
    $suspendCounts = 0
    $invokedThreadsArray = @()
    $processedThreadsArray = @()
    $previousSuspendCountArray = @()

    $process.Threads | ForEach-Object {
        # See https://docs.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-openthread
        $currentThreadId = Invoke-WindowsApi "kernel32" ([IntPtr]) "OpenThread" @([int], [bool], [int]) @(0x0002, $false, $_.Id)
        
        if ($currentThreadId -eq [IntPtr]::Zero) {
            continue
        }

        $numThreads++

        $invokedThreadsArray += $currentThreadId

        #Write-Verbose('  - Suspending thread id: ' + $currentThreadId)

        # See https://docs.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-suspendthread
        # Do we also need Wow64SuspendThread?
        # https://docs.microsoft.com/en-us/windows/win32/api/wow64apiset/nf-wow64apiset-wow64suspendthread
        $previousSuspendCount = Invoke-WindowsApi "kernel32" ([int]) "SuspendThread" @([IntPtr]) @($currentThreadId)

        #Write-Verbose('    Suspended thread ' + $currentThreadId + '. The previous suspend count is now: ' + $previousSuspendCount + ' (it should be 0)')
        
        $processedThreadsArray     += $currentThreadId
        $previousSuspendCountArray += $previousSuspendCount

        if ($previousSuspendCount -gt 0) {
            #Write-Verbose('    The previous suspend count is larger than 0, this means the process was already suspended... (curious but not necessarily an error)')
        }

        # $previousSuspendCount should be 0 if the thread is suspended now
        # If it > 0, then there is more than one suspended "state" on the thread. All of these need to be resumed to fully resume the thread/process
        # If it is -1, the operation has failed
        if ($previousSuspendCount -ge 0) {
            $suspendCounts++
        }
    }


    Write-Verbose('Threads that were invoked:')
    Write-Verbose('    ' + ($invokedThreadsArray -Join ', '))
    Write-Verbose('Threads that were processed:')
    Write-Verbose('    ' + ($processedThreadsArray -Join ', '))
    Write-Verbose('Previous suspend counts (should be 0):')
    Write-Verbose('    ' + ($previousSuspendCountArray -Join ', '))


    if ($suspendCounts -eq $numThreads) {
        return $suspendCounts
    }
    else {
        return -1
    }
}


<##
 # Resumes a suspended process
 # Unfortunately this introduces a memory leak on multiple calls (resp. Invoke-WindowsApi does)
 # .PARAM System.Diagnostics.Process $process The process to resume
 # .RETURN [Int] The number of resumed threads from this process. -1 if something failed
 #>
function Resume-Process {
    param(
        [Parameter(Mandatory=$true)]
        [System.Diagnostics.Process]$process
    )

    if (!$process) {
        return -2
    }

    Write-Verbose('Resuming process:')
    Write-Verbose($process.Id.ToString() + ' - ' + $process.ProcessName.ToString())

    $numThreads = 0
    $resumeCounts = 0
    $invokedThreadsArray = @()
    $processedThreadsArray = @()
    $previousSuspendCountArray = @()

    $process.Threads | ForEach-Object {
        # See https://docs.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-openthread
        $currentThreadId = Invoke-WindowsApi "kernel32" ([IntPtr]) "OpenThread" @([int], [bool], [int]) @(0x0002, $false, $_.Id)
        
        if ($currentThreadId -eq [IntPtr]::Zero) {
            continue
        }

        $numThreads++

        $invokedThreadsArray += $currentThreadId

        #Write-Verbose('  - Resuming thread id: ' + $currentThreadId)

        # $previousSuspendCount should be 1 if the thread is resumed now
        # If it > 1, then there is more than one suspended "state" on the thread. All of these need to be resumed to fully resume the thread/process
        # If it is -1, the operation has failed
        do {
            # See https://docs.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-resumethread
            $previousSuspendCount = Invoke-WindowsApi "kernel32" ([int]) "ResumeThread" @([IntPtr]) @($currentThreadId)
            
            #Write-Verbose('    Resumed thread ' + $currentThreadId + '. The previous suspend count is now: ' + $previousSuspendCount + ' (it should be 1 or 0)')
            
            $processedThreadsArray     += $currentThreadId
            $previousSuspendCountArray += $previousSuspendCount

            if ($previousSuspendCount -gt 1) {
                #Write-Verbose('    The previous suspend count is larger than 1, this means the thread has multiple suspended states... (curious but not necessarily an error)')
            }
        } while ($previousSuspendCount -gt 1)

        if ($previousSuspendCount -eq 1) {
            $resumeCounts++
        }
    }


    Write-Verbose('Threads that were invoked:')
    Write-Verbose('    ' + ($invokedThreadsArray -Join ', '))
    Write-Verbose('Threads that were processed:')
    Write-Verbose('    ' + ($processedThreadsArray -Join ', '))
    Write-Verbose('Previous suspend counts (should be 1 or 0):')
    Write-Verbose('    ' + ($previousSuspendCountArray -Join ', '))


    if ($resumeCounts -eq $numThreads) {
        return $resumeCounts
    }
    else {
        return -1
    }
}


<##
 # Suspends a process via the DebugActiveProcess method
 # .PARAM [System.Diagnostics.Process] $process The process to suspend
 # .RETURN Bool
 #>
function Suspend-ProcessWithDebugMethod {
    param(
        [Parameter(Mandatory=$true)]
        [System.Diagnostics.Process]$process
    )

    if (!$process) {
        return $false
    }

    Invoke-WindowsApi "kernel32" ([bool]) "DebugActiveProcess" @([int]) @($process.Id)
}


<##
 # Resumes a suspended process
 # .PARAM System.Diagnostics.Process $process The process to resume
 # .RETURN Bool
 #>
function Resume-ProcessWithDebugMethod {
    param(
        [Parameter(Mandatory=$true)]
        [System.Diagnostics.Process]$process
    )

    if (!$process) {
        return $false
    }

    Invoke-WindowsApi "kernel32" ([bool]) "DebugActiveProcessStop" @([int]) @($process.Id)
}


<##
 # Gets the current CPU frequency of a specific core / CPU
 # .PARAM Int $cpuNumber The CPU to query
 # .RETURN Hashtable The current frequency and percent
 # .NOTE The calculated value does not 100% match the one from HWInfo64 or Ryzen Master, it's a bit lower
 #       I'm not sure why or if there's any way to fix this
 #       It's still higher than the one reported by Windows Task Manager though
 #>
function Get-CpuFrequency {
    param(
        [Parameter(Mandatory=$true)]
        [Int]
        $cpuNumber
    )

    # We need two snapshots to be able to calculate an average over the time passed
    # We could also use a Start-Sleep function call to increase the timespan, without one it seems to be around 10ms
    $snapshot1 = Get-WmiObject -Query ('SELECT * from Win32_PerfRawData_Counters_ProcessorInformation WHERE Name LIKE "0,' + $cpuNumber + '"')
    $snapshot2 = Get-WmiObject -Query ('SELECT * from Win32_PerfRawData_Counters_ProcessorInformation WHERE Name LIKE "0,' + $cpuNumber + '"')

    $ProcessorFrequency                   = $snapshot1.ProcessorFrequency

    $PercentProcessorPerformance1         = $snapshot1.PercentProcessorPerformance
    $PercentProcessorPerformance_Base1    = $snapshot1.PercentProcessorPerformance_Base

    $PercentProcessorPerformance2         = $snapshot2.PercentProcessorPerformance
    $PercentProcessorPerformance_Base2    = $snapshot2.PercentProcessorPerformance_Base

    $PercentProcessorPerformanceDiff      = $PercentProcessorPerformance2 - $PercentProcessorPerformance1
    $PercentProcessorPerformance_BaseDiff = $PercentProcessorPerformance_Base2 - $PercentProcessorPerformance_Base1
    $PercentProcessorPerformance          = $PercentProcessorPerformanceDiff / $PercentProcessorPerformance_BaseDiff
    $Frequency                            = $ProcessorFrequency * ($PercentProcessorPerformance / 100)

    $returnObj = @{
        'CurrentFrequency' = [Math]::Round($Frequency, 0)
        'Percent'          = [Math]::Round($PercentProcessorPerformance, 2)
    }

    return $returnObj
}


<##
 # Import the settings from a .ini file
 # .PARAM String $filePath The path to the file to parse
 # .RETURN Hashtable A hashtable holding the settings
 #>
function Import-Settings {
    param(
        [Parameter(Mandatory=$true)]
        $filePath
    )

    # Certain setting values are strings
    $settingsWithStrings = @('stressTestProgram', 'name', 'mode', 'FFTSize', 'coreTestOrder')

    # Lowercase for certain settings
    $settingsToLowercase = @('stressTestProgram', 'coreTestOrder')

    # Check if the file exists
    if (!(Test-Path $filePath -PathType leaf)) {
        Exit-WithFatalError('Could not find ' + $filePath + '!')
    }

    
    $ini = @{}
    
    switch -regex -file $filePath {
        # Comments
        '^#' {
            continue
        }

        # Sections
        '^\[(.+)\]$' {
            $section = $matches[1].ToString().Trim()
            $ini[$section] = @{}
        }

        # Settings
        '^(.+)\s?=\s?(.+)$' {
            $name, $value = $matches[1..2]
            $name = $name.ToString().Trim()
            $setting = $null

            # Special handling for coresToIgnore, which can be empty
            if ($name -eq 'coresToIgnore') {
                $setting = @()

                if ($value -ne $null -and ![string]::IsNullOrEmpty($value) -and ![String]::IsNullOrWhiteSpace($value)) {
                    # Split the string by comma and add to the coresToIgnore entry
                    $value -split ',\s*' | ForEach-Object {
                        if ($_.Length -gt 0) {
                            $setting += [Int]$_
                        }
                    }
                }

                $setting = $setting | Sort
            }

            # Regular settings cannot be empty
            elseif ($value -and ![string]::IsNullOrEmpty($value) -and ![String]::IsNullOrWhiteSpace($value)) {
                # Parse the runtime per core (seconds, minutes, hours)
                if ($name -eq 'runtimePerCore') {
                    # Parse the hours, minutes, seconds
                    if ($value.indexOf('h') -ge 0 -or $value.indexOf('m') -ge 0 -or $value.indexOf('s') -ge 0) {
                        $hasMatched = $value -match '((?<hours>\d+(\.\d+)*)h)*\s*((?<minutes>\d+(\.\d+)*)m)*\s*((?<seconds>\d+(\.\d+)*)s)*'
                        $seconds = [Double]$matches.hours * 60 * 60 + [Double]$matches.minutes * 60 + [Double]$matches.seconds
                        $setting = [Int]$seconds
                    }

                    # Treat the value as seconds
                    else {
                        $setting = [Int]$value
                    }
                }


                # String values
                elseif ($settingsWithStrings.Contains($name)) {
                    if ($settingsToLowercase.Contains($name)) {
                        $setting = ([String]$value).ToLower()
                    }
                    else {
                        $setting = [String]$value
                    }
                }


                # Integer values
                elseif ($value -and ![string]::IsNullOrEmpty($value) -and ![String]::IsNullOrWhiteSpace($value)) {
                    $setting = [Int]$value
                }
            }

            # No [section] found, error
            if (!$section -or [string]::IsNullOrEmpty($section) -or [String]::IsNullOrWhiteSpace($section)) {
                Write-ColorText('FATAL ERROR: Invalid config file "' + $filePath + '" detected!') Red
                Write-ColorText('Maybe your config file is still from an older version?') Red
                Exit-WithFatalError
            }

            $ini[$section][$name] = $setting
        }
    }

    return $ini
}


<##
 # Get the settings
 # .PARAM void
 # .RETURN void
 #>
function Get-Settings {
    Write-Verbose('Parsing the user settings')

    # Default config settings
    $defaultSettings = Import-Settings 'config.default.ini'

    # Set the temporary name and path for the logfile
    # We need it because of the Exit-WithFatalError calls below
    # We don't have all the information yet though, so the name and path will be overwritten after all the user settings have been parsed
    $Script:logFileName     = $defaultSettings.logfile + '_' + $curDateTime + '.log'
    $Script:logFileFullPath = $logFilePathAbsolute + $logFileName


    # If no config file exists, copy the config.default.ini to config.ini
    if (!(Test-Path 'config.ini' -PathType leaf)) {
        
        if (!(Test-Path 'config.default.ini' -PathType leaf)) {
            Exit-WithFatalError('Neither config.ini nor config.default.ini found!')
        }

        Copy-Item -Path 'config.default.ini' -Destination 'config.ini'
    }


    # Read the config file and overwrite the default settings
    $userSettings = Import-Settings 'config.ini'


    # Check if the config.ini contained valid setting
    # It may be corrupted if the computer immediately crashed due to unstable settings
    try {
        foreach ($entry in $userSettings.GetEnumerator()) {
        }
    }

    # Couldn't get the a valid content from the config.ini, replace it with the default
    catch {
        Write-ColorText('WARNING: config.ini corrupted, replacing with default values!') Yellow

        if (!(Test-Path 'config.default.ini' -PathType leaf)) {
            Exit-WithFatalError('Neither config.ini nor config.default.ini found!')
        }

        Copy-Item -Path 'config.default.ini' -Destination 'config.ini'
        $userSettings = Import-Settings 'config.ini'
    }


    # Merge the user settings with the default settings
    $settings = $defaultSettings
    
    foreach ($sectionEntry in $userSettings.GetEnumerator()) {
        foreach ($userSetting in $sectionEntry.Value.GetEnumerator()) {
            # No empty values
            if ($userSetting.Value -ne $null -and ![string]::IsNullOrEmpty($userSetting.Value) -and ![String]::IsNullOrWhiteSpace($userSetting.Value)) {
                $settings[$sectionEntry.Name][$userSetting.Name] = $userSetting.Value
            }
            else {
                Write-Verbose('Setting is empty!')
                Write-Verbose('[' + $sectionEntry.Name + '][' + $userSetting.Name + ']: ' + $userSetting.Value)
            }
        }
    }


    <#
    foreach ($sectionEntry in $settings.GetEnumerator()) {
        ''
        '--------------------'
        $sectionEntry.Name
        '--------------------'
        
        foreach ($setting in $sectionEntry.Value.GetEnumerator()) {
            $setting.Name + ': ' + $setting.Value
        }
    }

    Read-Host -Prompt 'Press Enter to exit'
    exit
    #>


    # Limit the number of threads to 1 - 2
    $settings.General.numberOfThreads = [Math]::Max(1, [Math]::Min(2, $settings.General.numberOfThreads))
    $settings.General.numberOfThreads = $(if ($isHyperthreadingEnabled) { $settings.General.numberOfThreads } else { 1 })


    # Default the stress test program to prime95
    if (!$settings.General.stressTestProgram -or !$stressTestPrograms.Contains($settings.General.stressTestProgram)) {
        $settings.General.stressTestProgram = 'prime95'
    }


    # Set the general "mode" setting
    if ($settings.General.stressTestProgram -eq 'prime95') {
        $settings.mode = $settings.Prime95.mode
    }
    elseif ($settings.General.stressTestProgram -eq 'aida64') {
        $settings.mode = $settings.Aida64.mode
    }
    elseif ($settings.General.stressTestProgram -eq 'ycruncher') {
        $settings.mode = $settings.YCruncher.mode
    }


    # The selected mode for Y-Cruncher = the binary to execute
    # Override the variables
    $Script:stressTestPrograms['ycruncher']['processName']        = $settings.YCruncher.mode
    $Script:stressTestPrograms['ycruncher']['processNameForLoad'] = $settings.YCruncher.mode
    $Script:stressTestPrograms['ycruncher']['fullPathToExe']      = $stressTestPrograms['ycruncher']['absolutePath'] + $settings.YCruncher.mode
    $Script:stressTestPrograms['ycruncher']['windowNames']        = @('^.*' + $settings.YCruncher.mode + '\.exe$')


    # Sanity check the selected test mode
    if (!$stressTestPrograms[$settings.General.stressTestProgram]['testModes'].Contains($settings.mode)) {
        Exit-WithFatalError('The selected test mode "' + $settings.mode + '" is not available for ' + $stressTestPrograms[$settings.General.stressTestProgram]['displayName'] + '!')
    }


    # Store in the global variable
    $Script:settings = $settings


    # Set the final full path and name of the log file
    $Script:logFileName         = $settings.Logging.name + '_' + $curDateTime + '_' + $settings.General.stressTestProgram.ToUpper() + '_' + $settings.mode + '.log'
    $Script:logFileFullPath     = $logFilePathAbsolute + $logFileName
}


<##
 # Get the formatted runtime per core string
 # .PARAM int $seconds The runtime in seconds
 # .RETURN string The formatted runtime string
 #>
function Get-FormattedRuntimePerCoreString {
    param (
        $seconds
    )

    $runtimePerCoreStringArray = @()
    $timeSpan = [TimeSpan]::FromSeconds($seconds)

    if ( $timeSpan.Hours -ge 1 ) {
        $thisString = [String]$timeSpan.Hours + ' hour'

        if ( $timeSpan.Hours -gt 1 ) {
            $thisString += 's'
        }

        $runtimePerCoreStringArray += $thisString
    }

    if ( $timeSpan.Minutes -ge 1 ) {
        $thisString = [String]$timeSpan.Minutes + ' minute'

        if ( $timeSpan.Minutes -gt 1 ) {
            $thisString += 's'
        }

        $runtimePerCoreStringArray += $thisString
    }


    if ( $timeSpan.Seconds -ge 1 ) {
        $thisString = [String]$timeSpan.Seconds + ' second'

        if ( $timeSpan.Seconds -gt 1 ) {
            $thisString += 's'
        }

        $runtimePerCoreStringArray += $thisString
    }

    return ($runtimePerCoreStringArray -join ', ')
}


<##
 # Get the correct TortureWeak setting for the selected CPU settings
 # .PARAM void
 # .RETURN Int
 #>
function Get-TortureWeakValue {
    <#
    Calculation of the TortureWeak ini setting
    ------------------------------------------
    From Prime95\source\gwnum\cpuid.h:
    #define CPU_SSE            0x0100     /*     256   SSE instructions supported */
    #define CPU_SSE2           0x0200     /*     512   SSE2 instructions supported */
    #define CPU_SSE3           0x0400     /*    1024   SSE3 instructions supported */
    #define CPU_SSSE3          0x0800     /*    2048   Supplemental SSE3 instructions supported */
    #define CPU_SSE41          0x1000     /*    4096   SSE4.1 instructions supported */
    #define CPU_SSE42          0x2000     /*    8192   SSE4.2 instructions supported */
    #define CPU_AVX            0x4000     /*   16384   AVX instructions supported */
    #define CPU_FMA3           0x8000     /*   32768   Intel fused multiply-add instructions supported */
    #define CPU_FMA4           0x10000    /*   65536   AMD fused multiply-add instructions supported */
    #define CPU_AVX2           0x20000    /*  131072   AVX2 instructions supported */
    #define CPU_PREFETCHW      0x40000    /*  262144   PREFETCHW (the Intel version) instruction supported */
    #define CPU_PREFETCHWT1    0x80000    /*  524288   PREFETCHWT1 instruction supported */
    #define CPU_AVX512F        0x100000   /* 1048576   AVX512F instructions supported */
    #define CPU_AVX512PF       0x200000   /* 2097152   AVX512PF instructions supported */

    From Prime95\source\prime95\Prime95Doc.cpp:
    m_weak = dlg.m_avx512 * CPU_AVX512F + dlg.m_fma3 * CPU_FMA3 + dlg.m_avx * CPU_AVX + dlg.m_sse2 * CPU_SSE2;
    
    - Only CPU_AVX512F, CPU_FMA3, CPU_AVX & CPU_SSE2 is used for the calculation
    - If one of these is set to disabled, add the number to the total value
    - AVX512 is never available on Ryzen

    All enabled (except AVX512):
    1048576 --> CPU_AVX512F
    
    AVX2 disabled:
    1081344
    -1048576  --> CPU_AVX512F
    -32768    --> CPU_FMA3

    AVX disabled:
    1097728
    -1048576  --> CPU_AVX512F
    -32768    --> CPU_FMA3
    -16384    --> CPU_AVX
    #>

    # Convert '0' to true to 1 and 1 to false to 0
    $FMA3 = [Int]![Int]$prime95CPUSettings[$settings.mode].CpuSupportsFMA3
    $AVX  = [Int]![Int]$prime95CPUSettings[$settings.mode].CpuSupportsAVX

    # Add the various flag values if a feature is disabled
    $tortureWeakValue = 1048576 + ($FMA3 * 32768) + ($AVX * 16384)

    return $tortureWeakValue
}


<##
 # Get the main window handler for the selected stress test program process
 # Even if minimized to the tray
 # .PARAM void
 # .RETURN void
 #>
function Get-StressTestWindowHandler {
    $stressTestProcess   = $null
    $stressTestProcessId = $null
    
    Write-Verbose('Trying to get the stress test program window handler');
    Write-Verbose('Looking for these window names:')
    Write-Verbose(($stressTestPrograms[$settings.General.stressTestProgram]['windowNames'] -Join ', '))

    $windowObj = [Api.Apidef]::GetWindows() | Where-Object {
        $_.WinTitle -match ($stressTestPrograms[$settings.General.stressTestProgram]['windowNames'] -Join '|')
    }

    # No windows found, wait for a bit and repeat
    if ($windowObj.Length -eq 0) {
        Write-Verbose('No window found for these names!')
        Start-Sleep -Milliseconds 300

        $windowObj = [Api.Apidef]::GetWindows() | Where-Object {
            $_.WinTitle -match ($stressTestPrograms[$settings.General.stressTestProgram]['windowNames'] -Join '|')
        }
    }


    # Still nothing found, throw an error
    if ($windowObj.Length -eq 0) {
        Write-ColorText('FATAL ERROR: Could not find a window instance for the stress test program!') Red
        Write-ColorText('Was looking for these window names:') Red
        Write-ColorText(($stressTestPrograms[$settings.General.stressTestProgram]['windowNames'] -Join ', ')) Yellow

        # I could dump all of the window names here, but I'd rather not due to privacy reasons
        
        # Check the process
        $process = Get-Process $stressTestPrograms[$settings.General.stressTestProgram]['processName']

        if ($process.Length -gt 0) {
            Write-ColorText('However, found a process with the process name "' + $stressTestPrograms[$settings.General.stressTestProgram]['processName'] + '":') Red

            $process | ForEach-Object {
                Write-ColorText(' - ProcessName:  ' + $_.ProcessName) Yellow
                Write-ColorText('   Process Path: ' + $_.Path) Yellow
                Write-ColorText('   Process Id:   ' + $_.Id) Yellow
            }
        }

        Exit-WithFatalError
    }


    Write-Verbose('Found the following window(s) with these names:')

    $windowObj | ForEach-Object {
        $path = (Get-Process -Id $_.ProcessId).Path
        Write-Verbose(' - WinTitle:     ' + $_.WinTitle)
        Write-Verbose('   ProcessId:    ' + $_.ProcessId)
        Write-Verbose('   Process Path: ' + $path)
    }

    # There might be another window open with the same name as the stress test program (e.g. an Explorer window)
    # Select the correct one
    Write-Verbose('Filtering the windows for ".*' + $stressTestPrograms[$settings.General.stressTestProgram]['processName'] + '.' + $stressTestPrograms[$settings.General.stressTestProgram]['processNameExt'] + '$":')

    $filteredWindowObj = $windowObj | Where-Object {
        (Get-Process -Id $_.ProcessId).Path -match ('.*' + $stressTestPrograms[$settings.General.stressTestProgram]['processName'] + '\.' + $stressTestPrograms[$settings.General.stressTestProgram]['processNameExt'] + '$')
    }

    $filteredWindowObj | ForEach-Object {
        $path = (Get-Process -Id $_.ProcessId).Path
        Write-Verbose(' - WinTitle:     ' + $_.WinTitle)
        Write-Verbose('   ProcessId:    ' + $_.ProcessId)
        Write-Verbose('   Process Path: ' + $path)
    }


    # Multiple processes found with the same name AND process name
    # Abort and let the user close these programs
    if ($filteredWindowObj -is [Array]) {
        Write-ColorText('FATAL ERROR: Could not find the correct stress test window!') Red
        Write-ColorText('There exist multiple windows with the same name as the stress test program:') Red
        
        $filteredWindowObj | ForEach-Object {
            $path = (Get-Process -Id $_.ProcessId).Path
            Write-ColorText(' - Windows Title: ' + $_.WinTitle) Yellow
            Write-ColorText('   Process Path:  ' + $path) Yellow
            Write-ColorText('   Process Id:    ' + $_.ProcessId) Yellow
        }

        Write-ColorText('Please close these windows and try again.') Red
        Exit-WithFatalError
    }


    # Also, the process performing the stress test can actually be different to the main window of the stress test program
    # If so, search for it as well
    if ($stressTestPrograms[$settings.General.stressTestProgram]['processName'] -ne $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad']) {
        Write-Verbose('The process performing the stress test is NOT the same as the main window!')
        Write-Verbose('Searching for the stress test process id...')
        
        try {
            Write-Verbose('Searching for "' + $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad'] + '"...')
            $stressTestProcess   = Get-Process $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad'] -ErrorAction Stop
            $stressTestProcessId = $stressTestProcess.Id

            Write-Verbose('Found with ID: ' + $stressTestProcessId)
        }
        catch {
            Exit-WithFatalError('Could not determine the stress test program process ID! (looking for ' + $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad'] + ')')
        }
    }

    # The stress test and the main window are the same process
    else {
        $stressTestProcess   = $windowProcess # This one already exists outside the function
        $stressTestProcessId = $filteredWindowObj.ProcessId
    }


    # Override the global script variables
    $Script:windowProcessMainWindowHandler = $filteredWindowObj.MainWindowHandle
    $Script:windowProcessId                = $filteredWindowObj.ProcessId
    $Script:stressTestProcess              = $stressTestProcess
    $Script:stressTestProcessId            = $stressTestProcessId

    Write-Verbose('Stress test window handler:    ' + $windowProcessMainWindowHandler)
    Write-Verbose('Stress test window process ID: ' + $windowProcessId)
    Write-Verbose('Stress test process ID:        ' + $stressTestProcessId)
}


<##
 # Create the Prime95 config files (local.txt & prime.txt)
 # This depends on the $settings.mode variable
 # .PARAM void
 # .RETURN void
 #>
function Initialize-Prime95 {
    # Check if the prime95.exe exists
    Write-Verbose('Checking if prime95.exe exists at:')
    Write-Verbose($stressTestPrograms['prime95']['fullPathToExe'] + '.' + $stressTestPrograms['prime95']['processNameExt'])

    if (!(Test-Path ($stressTestPrograms['prime95']['fullPathToExe'] + '.' + $stressTestPrograms['prime95']['processNameExt']) -PathType leaf)) {
        Write-ColorText('FATAL ERROR: Could not find Prime95!') Red
        Write-ColorText('Make sure to download and extract Prime95 into the following directory:') Red
        Write-ColorText($stressTestPrograms['prime95']['absolutePath']) Yellow
        Write-Text ''
        Write-ColorText('You can download Prime95 from:') Red
        Write-ColorText('https://www.mersenne.org/download/') Cyan
        Exit-WithFatalError
    }

    $configType  = $settings.mode
    $configFile1 = $stressTestPrograms['prime95']['absolutePath'] + 'local.txt'
    $configFile2 = $stressTestPrograms['prime95']['absolutePath'] + 'prime.txt'


    if ($configType -ne 'CUSTOM' -and $configType -ne 'SSE' -and $configType -ne 'AVX' -and $configType -ne 'AVX2') {
        Exit-WithFatalError('Invalid mode type provided!')
    }

    # The Prime95 results.txt file name and path for this run
    $Script:stressTestLogFileName = 'Prime95_' + $curDateTime + '_' + $configType + '_' + $settings.Prime95.FFTSize + '_FFT_' + $minFFTSize + 'K-' + $maxFFTSize + 'K.txt'
    $Script:stressTestLogFilePath = $logFilePathAbsolute + $stressTestLogFileName

    # Create the local.txt and overwrite if necessary
    $null = New-Item $configFile1 -ItemType File -Force

    Set-Content $configFile1 'RollingAverageIsFromV27=1'
    
    # Limit the load to the selected number of threads
    Add-Content $configFile1 ('NumCPUs=1')
    Add-Content $configFile1 ('CoresPerTest=1')
    Add-Content $configFile1 ('CpuNumHyperthreads=' + $settings.General.numberOfThreads)
    Add-Content $configFile1 ('WorkerThreads='      + $settings.General.numberOfThreads)
    Add-Content $configFile1 ('CpuSupportsSSE='     + $prime95CPUSettings[$configType].CpuSupportsSSE)
    Add-Content $configFile1 ('CpuSupportsSSE2='    + $prime95CPUSettings[$configType].CpuSupportsSSE2)
    Add-Content $configFile1 ('CpuSupportsAVX='     + $prime95CPUSettings[$configType].CpuSupportsAVX)
    Add-Content $configFile1 ('CpuSupportsAVX2='    + $prime95CPUSettings[$configType].CpuSupportsAVX2)
    Add-Content $configFile1 ('CpuSupportsFMA3='    + $prime95CPUSettings[$configType].CpuSupportsFMA3)
    

    
    # Create the prime.txt and overwrite if necessary
    $null = New-Item $configFile2 -ItemType File -Force

    # There's an 80 character limit for the ini settings, so we're using an ugly workaround to put the log file into the /logs/ directory:
    # - set the working dir to the logs directory
    # - then set the paths to the prime.txt and local.txt relative to that logs directory
    Set-Content $configFile2 ('WorkingDir='  + $PSScriptRoot)
    
    # Set the custom results.txt file name
    Add-Content $configFile2 ('prime.ini='   + $stressTestPrograms['prime95']['processPath'] + '\prime.txt')
    Add-Content $configFile2 ('local.ini='   + $stressTestPrograms['prime95']['processPath'] + '\local.txt')
    Add-Content $configFile2 ('results.txt=' + $logFilePath + '\' + $stressTestLogFileName)
    
    # Custom settings
    if ($configType -eq 'CUSTOM') {
        Add-Content $configFile2 ('TortureMem='    + $settings.Custom.TortureMem)
        Add-Content $configFile2 ('TortureTime='   + $settings.Custom.TortureTime)
    }
    
    # Default settings
    else {
        # No memory testing ("In-Place")
        # 1 minute per FFT size
        Add-Content $configFile2 'TortureMem=0'
        Add-Content $configFile2 'TortureTime=1'
    }

    # Set the FFT sizes
    Add-Content $configFile2 ('MinTortureFFT=' + $minFFTSize)
    Add-Content $configFile2 ('MaxTortureFFT=' + $maxFFTSize)
    

    # Get the correct TortureWeak setting
    Add-Content $configFile2 ('TortureWeak=' + $(Get-TortureWeakValue))
    
    Add-Content $configFile2 'V24OptionsConverted=1'
    Add-Content $configFile2 'V30OptionsConverted=1'
    Add-Content $configFile2 'WorkPreference=0'
    Add-Content $configFile2 'WGUID_version=2'
    Add-Content $configFile2 'StressTester=1'
    Add-Content $configFile2 'UsePrimenet=0'
    Add-Content $configFile2 'ExitOnX=1'
    Add-Content $configFile2 'ResultsFileTimestampInterval=60'
    Add-Content $configFile2 '[PrimeNet]'
    Add-Content $configFile2 'Debug=0'
}


<##
 # Open Prime95 and set global script variables
 # .PARAM void
 # .RETURN void
 #>
function Start-Prime95 {
    Write-Verbose('Starting Prime95')

    # Minimized to the tray
    $Script:windowProcess = Start-Process -filepath $stressTestPrograms['prime95']['fullPathToExe'] -ArgumentList '-t' -PassThru -WindowStyle Hidden
    
    # Minimized to the task bar
    #$Script:windowProcess = Start-Process -filepath $stressTestPrograms['prime95']['fullPathToExe'] -ArgumentList '-t' -PassThru -WindowStyle Minimized

    # This might be necessary to correctly read the process. Or not
    Start-Sleep -Milliseconds 500
    
    if (!$Script:windowProcess) {
        Exit-WithFatalError('Could not start process ' + $stressTestPrograms['prime95']['processName'] + '!')
    }

    # Get the main window handler
    # This also works for windows minimized to the tray
    Get-StressTestWindowHandler
    
    # This is to find the exact counter path, as you might have multiple processes with the same name
    try {
        # Start a background job to get around the cached Get-Counter value
        $Script:processCounterPathId = Start-Job -ScriptBlock { 
            $counterPathName = $args[0].'FullName'
            $processId = $args[1]
            ((Get-Counter $counterPathName -ErrorAction SilentlyContinue).CounterSamples | ? {$_.RawValue -eq $processId}).Path
        } -ArgumentList $counterNames, $stressTestProcessId | Wait-Job | Receive-Job

        if (!$processCounterPathId) {
            Exit-WithFatalError('Could not find the counter path for the Prime95 instance!')
        }

        $Script:processCounterPathTime = $processCounterPathId -replace $counterNames['SearchString'], $counterNames['ReplaceString']

        Write-Verbose('The Performance Process Counter Path for the ID:')
        Write-Verbose($processCounterPathId)
        Write-Verbose('The Performance Process Counter Path for the Time:')
        Write-Verbose($processCounterPathTime)
    }
    catch {
        #'Could not get the process path'
    }
}


<##
 # Close Prime95
 # .PARAM void
 # .RETURN void
 #>
function Close-Prime95 {
    Write-Verbose('Trying to close Prime95')

    # If there is no windowProcessMainWindowHandler id
    # Try to get it
    if (!$windowProcessMainWindowHandler) {
        Get-StressTestWindowHandler
    }
    
    # If we now have a windowProcessMainWindowHandler, try to close the window
    if ($windowProcessMainWindowHandler) {
        $windowProcess = Get-Process -Id $windowProcessId -ErrorAction SilentlyContinue
        $Error.Clear()

        # The process may be suspended
        if ($windowProcess) {
            $resumed = Resume-ProcessWithDebugMethod $windowProcess
        }

        Write-Verbose('Trying to gracefully close Prime95')
        
        # This returns false if no window is found with this handle
        if (![Win32]::SendMessage($windowProcessMainWindowHandler, [Win32]::WM_CLOSE, 0, 0) | Out-Null) {
            #'Process Window not found!'
        }

        # We've send the close request, let's wait up to 2 seconds
        elseif ($windowProcess -and !$windowProcess.HasExited) {
            #'Waiting for the exit'
            $null = $windowProcess.WaitForExit(3000)
        }
    }
    
    
    # If the window is still here at this point, just kill the process
    $windowProcess = Get-Process $processName -ErrorAction SilentlyContinue
    $Error.Clear()

    if ($windowProcess) {
        Write-Verbose('Could not gracefully close Prime95, killing the process')
        
        #'The process is still there, killing it'
        # Unfortunately this will leave any tray icons behind
        Stop-Process $windowProcess.Id -Force -ErrorAction SilentlyContinue
    }
    else {
        Write-Verbose('Prime95 closed')
    }
}


<##
 # Initialize Aida64
 # .PARAM void
 # .RETURN void
 #>
function Initialize-Aida64 {
    # Check if the aida64.exe exists
    Write-Verbose('Checking if aida64.exe exists at:')
    Write-Verbose($stressTestPrograms['aida64']['fullPathToExe'] + '.' + $stressTestPrograms['aida64']['processNameExt'])

    if (!(Test-Path ($stressTestPrograms['aida64']['fullPathToExe'] + '.' + $stressTestPrograms['aida64']['processNameExt']) -PathType leaf)) {
        Write-ColorText('FATAL ERROR: Could not find Aida64!') Red
        Write-ColorText('Make sure to download and extract the PORTABLE ENGINEER(!) version of Aida64 into the following directory:') Red
        Write-ColorText($stressTestPrograms['aida64']['absolutePath']) Yellow
        Write-Text ''
        Write-ColorText('You can download the PORTABLE ENGINEER(!) version of Aida64 from:') Red
        Write-ColorText('https://www.aida64.com/downloads') Cyan
        Exit-WithFatalError
    }


    $configType = $settings.mode

    # TODO: Do we want to offer a way to start Aida64 with admin rights?
    $hasAdminRights = $false


    # Rename the aida64.exe.manifest to aida64.exe.manifest.bak so that we can start as a regular user
    # By default AIDA64 requires admin rights for additional sensory information, which we don't need here
    $pathManifest = $stressTestPrograms['aida64']['processPath'] + '\aida64.exe.manifest'
    $pathBackup   = $stressTestPrograms['aida64']['processPath'] + '\aida64.exe.manifest.bak'
    
    if ((Test-Path $pathManifest -PathType leaf)) {
        Write-Verbose('Trying to rename the aida64.exe.manifest file so that we can start AIDA64 as a regular user')
        
        if (!(Move-Item -Path $pathManifest -Destination $pathBackup -PassThru)) {
            Exit-WithFatalError('Could not rename the aida64.exe.manifest file!')
        }

        Write-Verbose('Successfully renamed to aida64.exe.manifest.bak')
    }

    # The Aida64 log file name and path for this run
    $Script:stressTestLogFileName = 'Aida64_' + $curDateTime + '_' + $settings.mode + '.csv'
    $Script:stressTestLogFilePath = $logFilePathAbsolute + $stressTestLogFileName

    # The aida64.ini
    $configFile = $stressTestPrograms['aida64']['absolutePath'] + 'aida64.ini'


    if ($configType -ne 'CACHE' -and $configType -ne 'RAM') {
        Exit-WithFatalError('Invalid mode type provided!')
    }

    # Create the local.txt and overwrite if necessary
    $null = New-Item $configFile -ItemType File -Force

    Set-Content $configFile ('[Generic]')
    
    
    Add-Content $configFile ('')
    Add-Content $configFile ('NoGUI=0')
    Add-Content $configFile ('LoadWithWindows=0')
    Add-Content $configFile ('SplashScreen=0')
    Add-Content $configFile ('MinimizeToTray=1')
    Add-Content $configFile ('Language=en')
    Add-Content $configFile ('ReportHeader=0')
    Add-Content $configFile ('ReportFooter=0')
    Add-Content $configFile ('ReportMenu=0')
    Add-Content $configFile ('ReportDebugInfo=1')
    Add-Content $configFile ('ReportDebugInfoCSV=0')
    Add-Content $configFile ('ReportHostInFPC=0')
    Add-Content $configFile ('HWMonLogToHTM=0')
    Add-Content $configFile ('HWMonLogToCSV=1')
    Add-Content $configFile ('HWMonLogProcesses=0')
    Add-Content $configFile ('HWMonPersistentLog=1')
    Add-Content $configFile ('HWMonLogFileOpenFreq=24')
    Add-Content $configFile ('HWMonHTMLogFile=')

    # HWMonCSVLogFile=H:\_Overclock\CoreCycler\logs\Aida64_DATE_TIME_ETC.csv
    Add-Content $configFile ('HWMonCSVLogFile=' + $stressTestLogFilePath)

    # Which items to include in the log file
    # Unfortunately most of these require admin privileges
    $csvEntriesArr = @()
    
    # Date & Time
    # Works without admin rights
    $csvEntriesArr += 'SDATE STIME'
                        
    # The general CPU core clock
    # Requires admin rights to display the true core clock. If no admin rights, will display the default base clock
    $csvEntriesArr += 'SCPUCLK'

    # The CPU clock for each physical core
    # Requires admin rights
    if ($hasAdminRights) {
        $csvEntriesArr += $(for ($i = 1; $i -le $numLogicalCores; $i++) { 'SCC-1-' + $i })
    }

    # The overall CPU utilization
    # Works without admin rights
    $csvEntriesArr += 'SCPUUTI'

    # The CPU utilization for each logical core
    # Works without admin rights
    $csvEntriesArr += $(for ($i = 1; $i -le $numPhysCores; $i++) { 'SCPU' + $i + 'UTI' })

    # Temperature sensors
    # Here we might have a problem with different sensors on different motherboards
    # TMOBO TCPU TCPUDIO TCHIP TPCHDIO TMOS TTEMP1 TTEMP2

    # Motherboard, CPU, CPU Diode
    # Requires admin rights
    if ($hasAdminRights) {
        $csvEntriesArr += 'TMOBO TCPU TCPUDIO'
    }

    # Voltage sensors
    # Here we might have a problem with different sensors on different motherboards
    # VCPU VCPUVID VCPUNB VCPUVDD VCPUVDDNB
    # Vcore, VID, VDD
    # Requires admin rights
    if ($hasAdminRights) {
        $csvEntriesArr += 'VCPU VCPUVID VCPUVDD'
    }

    # Watt measurements
    # PCPUPKG PCPUVDD PCPUVDDNB
    # CPU Package, CPU VDD
    # Requires admin rights
    if ($hasAdminRights) {
        $csvEntriesArr += 'PCPUPKG PCPUVDD'
    }

    Add-Content $configFile ('HWMonLogItems=' + ($csvEntriesArr -Join ' '))

    <#
    HWMonLogItems=
    SDATE STIME
    SCPUCLK
    SCC-1-1 SCC-1-2 SCC-1-3 SCC-1-4 SCC-1-5 SCC-1-6 SCC-1-7 SCC-1-8 SCC-1-9 SCC-1-10 SCC-1-11 SCC-1-12
    SCPUUTI
    SCPU1UTI SCPU2UTI SCPU3UTI SCPU4UTI SCPU5UTI SCPU6UTI SCPU7UTI SCPU8UTI SCPU9UTI SCPU10UTI SCPU11UTI SCPU12UTI SCPU13UTI SCPU14UTI SCPU15UTI SCPU16UTI SCPU17UTI SCPU18UTI SCPU19UTI SCPU20UTI SCPU21UTI SCPU22UTI SCPU23UTI SCPU24UTI
    TMOBO TCPU TCPUDIO TCHIP TPCHDIO TMOS TTEMP1 TTEMP2
    VCPU VCPUVID VCPUNB VCPUVDD VCPUVDDNB
    CCPUVDD CCPUVDDNB
    PCPUPKG PCPUVDD PCPUVDDNB
    #>
}


<##
 # Open Aida64
 # .PARAM void
 # .RETURN void
 #>
function Start-Aida64 {
    Write-Verbose('Starting Aida64')

    # Cache or RAM
    $thisMode = $settings.Aida64.mode

    # Minimized to the tray
    #$Script:windowProcess = Start-Process -filepath $stressTestPrograms['aida64']['fullPathToExe'] -ArgumentList ('/HIDETRAYMENU /SST ' + $thisMode) -PassThru -WindowStyle Hidden
    
    # Minimized to the task bar
    $Script:windowProcess = Start-Process -filepath $stressTestPrograms['aida64']['fullPathToExe'] -ArgumentList ('/HIDETRAYMENU /SST ' + $thisMode) -PassThru -WindowStyle Minimized
    #$Script:windowProcess = Start-Process -filepath $stressTestPrograms['aida64']['fullPathToExe'] -ArgumentList ('/HIDETRAYMENU /SST ' + $thisMode) -PassThru

    #aida64.exe /SILENT /SST RAM
    #aida64.exe /HIDETRAYMENU /SST RAM

    # Aida64 takes some additional time to load
    # Check for the stress test process, if it's loaded, we're ready to go
    Write-Text('Waiting for Aida64 to load...')

    for ($i = 1; $i -le 30; $i++) {
        Start-Sleep -Milliseconds 500

        $stressTestProcess = Get-Process $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad'] -ErrorAction SilentlyContinue
        $Error.Clear()

        if ($stressTestProcess) {
            break
        }
    }
    
    
    if (!$Script:windowProcess) {
        Exit-WithFatalError('Could not start process ' + $stressTestPrograms['aida64']['processName'] + '!')
    }

    # Get the main window handler
    # This also works for windows minimized to the tray
    Get-StressTestWindowHandler

    # This is to find the exact counter path, as you might have multiple processes with the same name
    try {
        # Start a background job to get around the cached Get-Counter value
        $Script:processCounterPathId = Start-Job -ScriptBlock { 
            $counterPathName = $args[0].'FullName'
            $processId = $args[1]
            ((Get-Counter $counterPathName -ErrorAction SilentlyContinue).CounterSamples | ? {$_.RawValue -eq $processId}).Path
        } -ArgumentList $counterNames, $stressTestProcessId | Wait-Job | Receive-Job

        if (!$processCounterPathId) {
            Exit-WithFatalError('Could not find the counter path for the Aida64 instance!')
        }

        $Script:processCounterPathTime = $processCounterPathId -replace $counterNames['SearchString'], $counterNames['ReplaceString']

        Write-Verbose('The Performance Process Counter Path for the ID:')
        Write-Verbose($processCounterPathId)
        Write-Verbose('The Performance Process Counter Path for the Time:')
        Write-Verbose($processCounterPathTime)
    }
    catch {
        #'Could not get the process path'
    }
}


<##
 # Close Aida64
 # .PARAM void
 # .RETURN void
 #>
function Close-Aida64 {
    Write-Verbose('Trying to close Aida64')

    # If there is no windowProcessMainWindowHandler id
    # Try to get it
    if (!$windowProcessMainWindowHandler) {
        Get-StressTestWindowHandler
    }

    # The stress test window cannot be closed gracefully, as it has no main window
    # So just kill it
    if ($stressTestProcessId) {
        $stressTestProcess = Get-Process -Id $stressTestProcessId -ErrorAction SilentlyContinue
        $Error.Clear()

        # The process may be suspended
        if ($stressTestProcess) {
            $resumed = Resume-ProcessWithDebugMethod $stressTestProcess
        }
        
        if ($stressTestProcess) {
            Write-Verbose('Killing the stress test program process')
            Stop-Process $stressTestProcess.Id -Force -ErrorAction SilentlyContinue
        }
    }

    # If we now have a windowProcessMainWindowHandler, first try to close the main window gracefully
    if ($windowProcessMainWindowHandler) {
        Write-Verbose('Trying to gracefully close Aida64')
        Write-Verbose('windowProcessId: ' + $windowProcessId)
        
        $windowProcess = Get-Process -Id $windowProcessId -ErrorAction SilentlyContinue
        $Error.Clear()

        # The process may be suspended
        if ($windowProcess) {
            $resumed = Resume-ProcessWithDebugMethod $stressTestProcess
        }

        # This returns false if no window is found with this handle
        if (![Win32]::SendMessage($windowProcessMainWindowHandler, [Win32]::WM_CLOSE, 0, 0) | Out-Null) {
            #'Process Window not found!'
        }

        # We've send the close request, let's wait up to 3 seconds
        elseif ($windowProcess -and !$windowProcess.HasExited) {
            #'Waiting for the exit'
            Write-Verbose('Sent the close message, waiting for the program to exit')
            $null = $windowProcess.WaitForExit(3000)
        }
    }
    
    Write-Verbose('Checking if the main window process still exists:')
    Write-Verbose('Get-Process ' + $stressTestPrograms['aida64']['processName'])
    
    # If the window is still here at this point, just kill the process
    $windowProcess = Get-Process $stressTestPrograms['aida64']['processName'] -ErrorAction SilentlyContinue
    $Error.Clear()

    if ($windowProcess) {
        Write-Verbose('Could not gracefully close Aida64, killing the process')
        
        # Unfortunately this will leave any tray icons behind
        Stop-Process $windowProcess.Id -Force -ErrorAction SilentlyContinue
    }
    else {
        Write-Verbose('Aida64 closed')
    }
}


<##
 # Create the Y-Cruncher config files (local.txt & prime.txt)
 # This depends on the $settings.mode variable
 # .PARAM void
 # .RETURN void
 #>
function Initialize-YCruncher {
    # Check if the selected binary exists
    Write-Verbose('Checking if ' + $stressTestPrograms['ycruncher']['processName'] + '.' + $stressTestPrograms['ycruncher']['processNameExt'] + ' exists at:')
    Write-Verbose($stressTestPrograms['ycruncher']['fullPathToExe'] + '.' + $stressTestPrograms['ycruncher']['processNameExt'])

    if (!(Test-Path ($stressTestPrograms['ycruncher']['fullPathToExe'] + '.' + $stressTestPrograms['ycruncher']['processNameExt']) -PathType leaf)) {
        Write-ColorText('FATAL ERROR: Could not find Y-Cruncher!') Red
        Write-ColorText('Make sure to download and extract Y-Cruncher into the following directory:') Red
        Write-ColorText($stressTestPrograms['ycruncher']['absolutePath']) Yellow
        Write-Text ''
        Write-ColorText('You can download Y-Cruncher from:') Red
        Write-ColorText('http://www.numberworld.org/y-cruncher/#Download') Cyan
        Exit-WithFatalError
    }

    $configType = $settings.mode
    #$configName = '1-Thread_60s_Tests-BKT-BBP-SFT-FFT-N32-N64-HNT-VST.cfg'
    $configName = 'stressTest.cfg'
    $configFile = $stressTestPrograms['ycruncher']['absolutePath'] + $configName

    $Script:stressTestConfigFileName = $configName
    $Script:stressTestConfigFilePath = $configFile

    # TODO: More config types
    #if ($configType -ne 'CUSTOM' -and $configType -ne 'SSE' -and $configType -ne 'AVX' -and $configType -ne 'AVX2') {
    #    Exit-WithFatalError('Invalid mode type provided!')
    #}

    # The log file name and path for this run
    # TODO: Y-Cruncher doesn't seem to create any type of log :(
    #$Script:stressTestLogFileName = 'Y-Cruncher_' + $curDateTime + '.txt'
    #$Script:stressTestLogFilePath = $logFilePathAbsolute + $stressTestLogFileName


    # Create the config file and overwrite if necessary
    $null = New-Item $configFile -ItemType File -Force

    $coresLine  = '        LogicalCores : [2]'
    $memoryLine = '        TotalMemory : 13418572'

    if ($settings.General.numberOfThreads -gt 1) {
        $coresLine  = '        LogicalCores : [2 3]'
        $memoryLine = '        TotalMemory : 26567600'        
    }


    $configEntries = @(
        '{'
        '    Action : "StressTest"'
        '    StressTest : {'
        '        AllocateLocally : "true"'
        $coresLine
        $memoryLine
        '        SecondsPerTest : 60'
        '        SecondsTotal : 0'
        '        StopOnError : "true"'
        '        Tests : ['
        '            "BKT"'
        '            "BBP"'
        '            "SFT"'
        '            "FFT"'
        '            "N32"'
        '            "N64"'
        '            "HNT"'
        '            "VST"'
        '        ]'
        '    }'
        '}'
    )


    Set-Content $configFile ''

    foreach ($entry in $configEntries) {
        Add-Content $configFile $entry
    }
}


<##
 # Open Y-Cruncher and set global script variables
 # .PARAM void
 # .RETURN void
 #>
function Start-YCruncher {
    Write-Verbose('Starting Y-Cruncher')

    $thisMode = $settings.YCruncher.mode

    # Minimized to the tray
    #$Script:windowProcess = Start-Process -filepath $stressTestPrograms['ycruncher']['fullPathToExe'] -ArgumentList ('config ' + $stressTestConfigFilePath) -PassThru -WindowStyle Hidden
    
    # Minimized to the task bar
    $Script:windowProcess = Start-Process -filepath $stressTestPrograms['ycruncher']['fullPathToExe'] -ArgumentList ('config ' + $stressTestConfigFilePath) -PassThru -WindowStyle Minimized
    #$Script:windowProcess = Start-Process -filepath $stressTestPrograms['ycruncher']['fullPathToExe'] -ArgumentList ('config ' + $stressTestConfigFilePath) -PassThru

    # This might be necessary to correctly read the process. Or not
    Start-Sleep -Milliseconds 500
    
    if (!$Script:windowProcess) {
        Exit-WithFatalError('Could not start process ' + $stressTestPrograms['ycruncher']['processName'] + '!')
    }

    # Get the main window handler
    # This also works for windows minimized to the tray
    Get-StressTestWindowHandler
    
    # This is to find the exact counter path, as you might have multiple processes with the same name
    try {
        # Start a background job to get around the cached Get-Counter value
        $Script:processCounterPathId = Start-Job -ScriptBlock { 
            $counterPathName = $args[0].'FullName'
            $processId = $args[1]
            ((Get-Counter $counterPathName -ErrorAction SilentlyContinue).CounterSamples | ? {$_.RawValue -eq $processId}).Path
        } -ArgumentList $counterNames, $stressTestProcessId | Wait-Job | Receive-Job

        if (!$processCounterPathId) {
            Exit-WithFatalError('Could not find the counter path for the Y-Cruncher instance!')
        }

        $Script:processCounterPathTime = $processCounterPathId -replace $counterNames['SearchString'], $counterNames['ReplaceString']

        Write-Verbose('The Performance Process Counter Path for the ID:')
        Write-Verbose($processCounterPathId)
        Write-Verbose('The Performance Process Counter Path for the Time:')
        Write-Verbose($processCounterPathTime)
    }
    catch {
        #'Could not get the process path'
    }
}


<##
 # Close Y-Cruncher
 # .PARAM void
 # .RETURN void
 #>
function Close-YCruncher {
    Write-Verbose('Trying to close Y-Cruncher')

    # If there is no windowProcessMainWindowHandler id
    # Try to get it
    if (!$windowProcessMainWindowHandler) {
        Get-StressTestWindowHandler
    }
    
    # If we now have a windowProcessMainWindowHandler, try to close the window
    if ($windowProcessMainWindowHandler) {
        $windowProcess = Get-Process -Id $windowProcessId -ErrorAction SilentlyContinue
        $Error.Clear()

        # The process may be suspended
        if ($windowProcess) {
            $resumed = Resume-ProcessWithDebugMethod $windowProcess
        }

        Write-Verbose('Trying to gracefully close Y-Cruncher')
        
        # This returns false if no window is found with this handle
        if (![Win32]::SendMessage($windowProcessMainWindowHandler, [Win32]::WM_CLOSE, 0, 0) | Out-Null) {
            #'Process Window not found!'
        }

        # We've send the close request, let's wait up to 2 seconds
        elseif ($windowProcess -and !$windowProcess.HasExited) {
            #'Waiting for the exit'
            $null = $windowProcess.WaitForExit(3000)
        }
    }
    
    
    # If the window is still here at this point, just kill the process
    $windowProcess = Get-Process $processName -ErrorAction SilentlyContinue
    $Error.Clear()

    if ($windowProcess) {
        Write-Verbose('Could not gracefully close Y-Cruncher, killing the process')
        
        #'The process is still there, killing it'
        # Unfortunately this will leave any tray icons behind
        Stop-Process $windowProcess.Id -Force -ErrorAction SilentlyContinue
    }
    else {
        Write-Verbose('Y-Cruncher closed')
    }
}


<##
 # Initialize the selected stress test program
 # .PARAM void
 # .RETURN void
 #>
function Initialize-StressTestProgram {
    Write-Verbose('Initalizing the stress test program')

    if ($settings.General.stressTestProgram -eq 'prime95') {
        Initialize-Prime95 $settings.mode
    }
    elseif ($settings.General.stressTestProgram -eq 'aida64') {
        Initialize-Aida64
    }
    elseif ($settings.General.stressTestProgram -eq 'ycruncher') {
        Initialize-YCruncher
    }
    else {
        Exit-WithFatalError('No stress test program selected!')
    }
}


<##
 # Start the selected stress test program
 # .PARAM void
 # .RETURN void
 #>
function Start-StressTestProgram {
    Write-Verbose('Starting the stress test program')

    if ($settings.General.stressTestProgram -eq 'prime95') {
        Start-Prime95
    }
    elseif ($settings.General.stressTestProgram -eq 'aida64') {
        Start-Aida64
    }
    elseif ($settings.General.stressTestProgram -eq 'ycruncher') {
        Start-YCruncher
    }
    else {
        Exit-WithFatalError('No stress test program selected!')
    }
}


<##
 # Close the selected stress test program
 # .PARAM void
 # .RETURN void
 #>
function Close-StressTestProgram {
    Write-Verbose('Trying to close the stress test program')

    if ($settings.General.stressTestProgram -eq 'prime95') {
        Close-Prime95
    }
    elseif ($settings.General.stressTestProgram -eq 'aida64') {
        Close-Aida64
    }
    elseif ($settings.General.stressTestProgram -eq 'ycruncher') {
        Close-YCruncher
    }
    else {
        Exit-WithFatalError('No stress test program selected!')
    }
}


<##
 # Check the CPU power usage and restart Prime95 if necessary
 # Throws an error if the CPU usage is too low
 # .PARAM int $coreNumber The current core being tested
 # .RETURN void
 #>
function Test-ProcessUsage {
    param (
        $coreNumber
    )

    # Clear any previous errors
    $Error.Clear()

    $timestamp = Get-Date -format HH:mm:ss
    
    # The minimum CPU usage for the stress test program, below which it should be treated as an error
    # We need to account for the number of threads
    # Min. 1.0%
    # 100/32=   3,125% for 1 thread out of 32 threads
    # 100/32*2= 6,250% for 2 threads out of 32 threads
    # 100/24=   4,167% for 1 thread out of 24 threads
    # 100/24*2= 8,334% for 2 threads out of 24 threads
    # 100/12=   8,334% for 1 thread out of 12 threads
    # 100/12*2= 16,67% for 2 threads out of 12 threads
    $minProcessUsage = [Math]::Max(1.0, $expectedUsage - [Math]::Round(100 / $numLogicalCores, 2))
    
    
    # Set to a string if there was an error
    $stressTestError = $false

    # Get the content of the results.txt file
    $resultFileHandle = $false

    if ($settings.General.stressTestProgram -eq 'prime95') {
        $resultFileHandle = Get-Item -Path $stressTestLogFilePath -ErrorAction SilentlyContinue
        $Error.Clear()
    }

    # Does the process still exist?
    $stressTestProcess = Get-Process $processName -ErrorAction SilentlyContinue
    $Error.Clear()
    

    # 1. The process doesn't exist anymore, immediate error
    if (!$stressTestProcess) {
        $stressTestError = 'The ' + $selectedStressTestProgram + ' process doesn''t exist anymore.'
    }

    
    # 2. If using Prime95, parse the results.txt file and look for an error message
    if (!$stressTestError -and $settings.General.stressTestProgram -eq 'prime95') {

        # Look for a line with an "error" string in the last 3 lines
        $primeResults = $resultFileHandle | Get-Content -Tail 3 | Where-Object {$_ -like '*error*'}
        
        # Found the "error" string in the results.txt
        if ($primeResults.Length -gt 0) {
            # Get the line number of the last error message in the results.txt
            $p95Errors = Select-String $stressTestLogFilePath -Pattern ERROR
            $lastError = $p95Errors | Select-Object -Last 1 -Property LineNumber, Line

            # If it's the same line number and message than the previous error, ignore it, it's a false positive
            if ($lastError.LineNumber -eq $previousError.LineNumber -and $lastError.Line -eq $previousError.Line) {
                Write-Verbose($timestamp)
                Write-Verbose('Found an error, but it''s a false positive, because the line number and error message')
                Write-Verbose('matches the previous error message.')

                Write-Verbose('This error:')
                Write-Verbose((Write-Output($lastError | Format-Table | Out-String)).Trim())

                Write-Verbose('Previous error:')
                Write-Verbose((Write-Output($previousError | Format-Table | Out-String)).Trim())
            }

            # This is a true error now
            else {
                # Store the error message for future use
                $Script:previousError = $lastError

                Write-Verbose($timestamp)
                Write-Verbose('Found an error:')
                Write-Verbose((Write-Output($lastError | Format-Table | Out-String)).Trim())

                $stressTestError = $primeResults
            }
        }
    }


    # 3. Check if the process is still using enough CPU process power
    if (!$stressTestError) {
        # Get the CPU percentage
        $processCPUPercentage = [Math]::Round(((Get-Counter $processCounterPathTime -ErrorAction SilentlyContinue).CounterSamples.CookedValue) / $numLogicalCores, 2)
        $Error.Clear()
        
        Write-Verbose($timestamp + ' - ...checking CPU usage: ' + $processCPUPercentage + '%')

        # It doesn't use enough CPU power
        if ($processCPUPercentage -le $minProcessUsage) {

            # For Prime95
            if ($settings.General.stressTestProgram -eq 'prime95') {
                # Try to read the error from Prime95's results.txt
                # Look for a line with an "error" string in the last 3 lines
                $primeResults = $resultFileHandle | Get-Content -Tail 3 | Where-Object {$_ -like '*error*'}

                # Found the "error" string in the results.txt
                if ($primeResults.Length -gt 0) {
                    $stressTestError = $primeResults
                }
            }



            # Error string still not found
            # This might have been a false alarm, wait a bit and try again
            if (!$stressTestError) {
                $waitTime = 2000

                Write-Verbose($timestamp + ' - ...the CPU usage was too low, waiting ' + $waitTime + 'ms for another check...')

                Start-Sleep -Milliseconds $waitTime

                # The second check
                # Do the whole process path procedure again
                $thisProcessId = $stressTestProcess.Id[0]

                Write-Verbose('Process Id: ' + $thisProcessId)

                # Start a background job to get around the cached Get-Counter value
                $thisProcessCounterPathId = Start-Job -ScriptBlock { 
                    $counterPathName = $args[0].'FullName'
                    $processId = $args[1]
                    ((Get-Counter $counterPathName -ErrorAction SilentlyContinue).CounterSamples | ? {$_.RawValue -eq $processId}).Path
                } -ArgumentList $counterNames, $thisProcessId | Wait-Job | Receive-Job

                $thisProcessCounterPathTime = $thisProcessCounterPathId -replace $counterNames['SearchString'], $counterNames['ReplaceString']
                $thisProcessCPUPercentage   = [Math]::Round(((Get-Counter $thisProcessCounterPathTime -ErrorAction SilentlyContinue).CounterSamples.CookedValue) / $numLogicalCores, 2)
                $Error.Clear()

                Write-Verbose($timestamp + ' - ...checking CPU usage again: ' + $thisProcessCPUPercentage + '%')

                # Still below the minimum usage
                if ($processCPUPercentage -le $minProcessUsage) {
                    Write-Verbose('           ...still not enough usage, throw an error')

                    # We don't care about an error string here anymore
                    $stressTestError = 'The ' + $selectedStressTestProgram + ' process doesn''t use enough CPU power anymore (only ' + $processCPUPercentage + '% instead of the expected ' + $expectedUsage + '%)'
                }
                else {
                    Write-Verbose('           ...the process seems to have recovered, continuing with stress testing')
                }
            }
        }
    }


    if ($stressTestError) {
        Write-Verbose('There has been an error with the stress test program!')

        # Store the core number in the array
        $Script:coresWithError += $coreNumber

        # Count the number of errors per core
        $Script:coresWithErrorsCounter[$coreNumber]++ 

        # If Hyperthreading / SMT is enabled and the number of threads larger than 1
        if ($isHyperthreadingEnabled -and ($settings.General.numberOfThreads -gt 1)) {
            $cpuNumbersArray = @($coreNumber, ($coreNumber + 1))
            $cpuNumberString = (($cpuNumbersArray | sort) -join ' or ')
        }

        # Only one core is being tested
        else {
            # If Hyperthreading / SMT is enabled, the tested CPU number is 0, 2, 4, etc
            # Otherwise, it's the same value
            $cpuNumberString = $coreNumber * (1 + [Int]$isHyperthreadingEnabled)
        }


        # Put out an error message
        $timestamp = Get-Date -format HH:mm:ss
        Write-ColorText('ERROR: ' + $timestamp) Magenta
        Write-ColorText('ERROR: ' + $selectedStressTestProgram + ' seems to have stopped with an error!') Magenta
        Write-ColorText('ERROR: At Core ' + $coreNumber + ' (CPU ' + $cpuNumberString + ')') Magenta
        Write-ColorText('ERROR MESSAGE: ' + $stressTestError) Magenta


        # Try to get more detailed error information
        # Prime95
        if ($settings.General.stressTestProgram -eq 'prime95') {
            Write-Verbose('The stress test program is Prime95, trying to look for an error message in the results.txt')

            # DEBUG
            # Also add the 5 last rows of the results.txt file
            #Write-Text('LAST 5 ROWS OF RESULTS.TXT:')
            #Write-Text(Get-Item -Path $stressTestLogFilePath | Get-Content -Tail 5)
            
            # Try to determine the last run FFT size
            # If the results.txt doesn't exist, assume that it was on the very first iteration
            # Note: Unfortunately Prime95 randomizes the FFT sizes for anything above Large FFT sizes
            #       So we cannot make an educated guess for these settings
            #if ($maxFFTSize -le $FFTMinMaxValues[$settings.mode]['Large'].Max) {
            
            # This check is taken from the Prime95 source code:
            # if (fftlen > max_small_fftlen * 2) num_large_lengths++;
            # The max smallest FFT size is 240, so starting with 480 the order should get randomized
            # Large FFTs are not randomized, Huge FFTs and All FFTs are
            # TODO: this doesn't seem right
            #if ($minFFTSize -le ($FFTMinMaxValues[$settings.mode]['Small']['Min'] * 2)) {

            #if ($settings.Prime95.FFTSize -eq 'Smallest' -or $settings.Prime95.FFTSize -eq 'Small' -or $settings.Prime95.FFTSize -eq 'Large') {

            # Temporary(?) solution
            if ($maxFFTSize -le $FFTMinMaxValues['SSE']['Large']['Max']) {
                Write-Verbose('The maximum FFT size is within the range where we can still make an educated guess about the failed FFT size')

                # No results file exists yet
                if (!$resultFileHandle) {
                    Write-Verbose('No results.txt exists yet, assuming the error happened on the first FFT size')
                    $lastRunFFT = $minFFTSize
                }
                
                # Get the last couple of rows and find the last passed FFT size
                else {
                    Write-Verbose('Trying to find the last passed FFT sizes')

                    $lastFiveRows     = $resultFileHandle | Get-Content -Tail 5
                    $lastPassedFFTArr = @($lastFiveRows | Where-Object {$_ -like '*passed*'})
                    $hasMatched       = $lastPassedFFTArr[$lastPassedFFTArr.Length-1] -match 'Self\-test (\d+)K passed'
                    $lastPassedFFT    = if ($matches -is [Hashtable] -or $matches -is [Array]) { [Int]$matches[1] }   # $matches is a fixed(?) variable name for -match
                    
                    # No passed FFT was found, assume it's the first FFT size
                    if (!$lastPassedFFT) {
                        $lastRunFFT = $minFFTSize
                        Write-Verbose('No passed FFT was found, assume it was the first FFT size: ' + $lastRunFFT)
                    }

                    # If the last passed FFT size is the max selected FFT size, start at the beginning
                    elseif ($lastPassedFFT -eq $maxFFTSize) {
                        $lastRunFFT = $minFFTSize
                        Write-Verbose('The last passed FFT size is the max selected FFT size, use the min FFT size: ' + $lastRunFFT)
                    }

                    # If the last passed FFT size is not the max size, check if the value doesn't show up at all in the FFT array
                    # In this case, we also assume that it successfully completed the max value and errored at the min FFT size
                    # Example: Smallest FFT max = 21, but the actual last size tested is 20K
                    elseif (!$FFTSizes[$cpuTestMode].Contains($lastPassedFFT)) {
                        $lastRunFFT = $minFFTSize
                        Write-Verbose('The last passed FFT size does not show up in the FFTSizes array, assume it''s the first FFT size: ' + $lastRunFFT)
                    }

                    # If it's not the max value and it does show up in the FFT array, select the next value
                    else {
                        $lastRunFFT = $FFTSizes[$cpuTestMode][$FFTSizes[$cpuTestMode].indexOf($lastPassedFFT)+1]
                        Write-Verbose('Last passed FFT size found: ' + $lastRunFFT)
                    }
                }

                # Educated guess
                if ($lastRunFFT) {
                    Write-ColorText('ERROR: The error likely happened at FFT size ' + $lastRunFFT + 'K') Magenta
                }
                else {
                    Write-ColorText('ERROR: No additional FFT size information found in the results.txt') Magenta
                }

                Write-Verbose('The last 5 entries in the results.txt:')
                Write-Verbose($lastFiveRows -Join ', ')

                Write-Text('')
            }

            # Only Smallest, Small and Large FFT presets follow the order, so no real FFT size fail detection is possible due to randomization of the order by Prime95
            else {
                $lastFiveRows     = $resultFileHandle | Get-Content -Tail 5
                $lastPassedFFTArr = @($lastFiveRows | Where-Object {$_ -like '*passed*'})
                $hasMatched       = $lastPassedFFTArr[$lastPassedFFTArr.Length-1] -match 'Self\-test (\d+)K passed'
                $lastPassedFFT    = if ($matches -is [Hashtable] -or $matches -is [Array]) { [Int]$matches[1] }   # $matches is a fixed(?) variable name for -match
                
                if ($lastPassedFFT) {
                    Write-ColorText('ERROR: The last *passed* FFT size before the error was: ' + $lastPassedFFT + 'K') Magenta 
                    Write-ColorText('ERROR: Unfortunately FFT size fail detection only works for Smallest, Small or Large FFT sizes.') Magenta 
                }
                else {
                    Write-ColorText('ERROR: No additional FFT size information found in the results.txt') Magenta
                }

                Write-Verbose('The max FFT size was outside of the range where it still follows a numerical order')
                Write-Verbose('The selected max FFT size:         ' + $maxFFTSize)
                Write-Verbose('The limit for the numerical order: ' + $FFTMinMaxValues['SSE']['Large']['Max'])


                Write-Verbose('The last 5 entries in the results.txt:')
                Write-Verbose($lastFiveRows -Join ', ')

                Write-Text('')
            }
        }


        # Aida64
        elseif ($settings.General.stressTestProgram -eq 'aida64') {
            Write-Verbose('The stress test program is Aida64, no detailed error detection available')
        }


        # Y-Cruncher
        elseif ($settings.General.stressTestProgram -eq 'ycruncher') {
            Write-Verbose('The stress test program is Y-Cruncher, no detailed error detection available')
        }


        # Try to close the stress test program process if it is still running
        Write-Verbose('Trying to close the stress test program to re-start it')
        Close-StressTestProgram
        

        # If the stopOnError flag is set, stop at this point
        if ($settings.General.stopOnError) {
            Write-Text('')
            Write-ColorText('Stopping the testing process because the "stopOnError" flag was set.') Yellow

            if ($settings.General.stressTestProgram -eq 'prime95') {
                # Display the results.txt file name for Prime95 for this run
                Write-Text('')
                Write-ColorText('Prime95''s results log file can be found at:') Cyan
                Write-ColorText($stressTestLogFilePath) Cyan
            }

            # And the name of the log file for this run
            Write-Text('')
            Write-ColorText('The path of the CoreCycler log file for this run is:') Cyan
            Write-ColorText($logfileFullPath) Cyan
            Write-Text('')
            
            Exit-Script
        }
        

        # Try to restart the stress test program and continue with the next core
        # Don't try to restart at this point if $settings.General.restartTestProgramForEachCore is set to 1
        # This will be taken care of in another routine
        if (!$settings.General.restartTestProgramForEachCore) {
            Write-Verbose('restartTestProgramForEachCore is not set, restarting the test program right away')

            $timestamp = Get-Date -format HH:mm:ss
            Write-Text($timestamp + ' - Trying to restart ' + $selectedStressTestProgram)

            # Start the stress test program again
            Start-StressTestProgram
        }
        
        
        # Throw an error to let the caller know there was an error
        #throw ($selectedStressTestProgram + ' seems to have stopped with an error at Core ' + $coreNumber + ' (CPU ' + $cpuNumberString + ')')
        # Use a fixed value to be able to differentiate between a "real" error and this info
        # System.ApplicationException
        # System.Activities.WorkflowApplicationAbortedException
        throw '999'
    }
}



<##
 # The main functionality
 #>


# Get the default and the user settings
Get-Settings


# Error Checks

# PowerShell version too low
# This is a neat flag
#requires -version 3.0


# Check if .NET is installed
$hasDotNet3_5 = [Int](Get-ItemProperty 'HKLM:\Software\Microsoft\NET Framework Setup\NDP\v3.5' -ErrorAction SilentlyContinue).Install
$hasDotNet4_0 = [Int](Get-ItemProperty 'HKLM:\Software\Microsoft\NET Framework Setup\NDP\v4.0\Client' -ErrorAction SilentlyContinue).Install
$hasDotNet4_x = [Int](Get-ItemProperty 'HKLM:\Software\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue).Install

if (!$hasDotNet3_5 -and !$hasDotNet4_0 -and !$hasDotNet4_x) {
    Write-Host
    Write-Host 'FATAL ERROR: .NET could not be found or the version is too old!' -ForegroundColor Red
    Write-Host 'At least version 3.5 of .NET is required!' -ForegroundColor Red
    Write-Host
    Write-Host 'You can download .NET 3.5 here:' -ForegroundColor Yellow
    Write-Host 'https://docs.microsoft.com/en-us/dotnet/framework/install/dotnet-35-windows-10' -ForegroundColor Cyan
    
    Exit-WithFatalError
}

# Clear the error variable, it may have been populated by the above calls
$Error.clear()


# Try top get the localized counter names
try {
    Write-Verbose('Trying to get the localized performance counter names')

    $counterNameIds = Get-PerformanceCounterIDs $englishCounterNames
    $counterNameIds.GetEnumerator().ForEach({ 
        Write-Verbose(('ID of "' + $_.Name + '":').PadRight(43, ' ') + $_.Value)
    })

    $counterNames['Process'] = Get-PerformanceCounterLocalName $counterNameIds['Process']
    Write-Verbose('The localized name for "Process":          ' + $counterNames['Process'])

    $counterNames['ID Process'] = Get-PerformanceCounterLocalName $counterNameIds['ID Process']
    Write-Verbose('The localized name for "ID Process":       ' + $counterNames['ID Process'])

    $counterNames['% Processor Time'] = Get-PerformanceCounterLocalName $counterNameIds['% Processor Time']
    Write-Verbose('The localized name for "% Processor Time": ' + $counterNames['% Processor Time'])


    $counterNames['FullName']      = '\' + $counterNames['Process'] + '(*)\' + $counterNames['ID Process']
    $counterNames['SearchString']  = '\\' + $counterNames['ID Process'] + '$'
    $counterNames['ReplaceString'] = '\' + $counterNames['% Processor Time']

    Write-Verbose('FullName:                                  ' + $counterNames['FullName'])
    Write-Verbose('SearchString:                              ' + $counterNames['SearchString'])
    Write-Verbose('ReplaceString:                             ' + $counterNames['ReplaceString'])

    # Examples
    # English             German               Spanish                      French
    # -------             ------               -------                      ------
    # Process             Prozess              Proseco                      Processus
    # ID Process          Prozesskennung       Id. de proseco               ID de processus
    # % Processor Time    Prozessorzeit (%)    % de tiempo de procesador    % temps processeur
    
    
    # These are additional counters that may or may not be used in the future   
    #$counterNames['Processor Information' ]  = Get-PerformanceCounterLocalName $counterNameIds['Processor Information']
    #$counterNames['% Processor Performance'] = Get-PerformanceCounterLocalName $counterNameIds['% Processor Performance']
    #$counterNames['% Processor Utility']     = Get-PerformanceCounterLocalName $counterNameIds['% Processor Utility']
}
catch {
    Write-Host 'FATAL ERROR: Could not get the localized Performance Process Counter name!' -ForegroundColor Red
    Write-Host
    Write-Host 'You may need to re-enable the Performance Process Counter (PerfProc).' -ForegroundColor Red
    Write-Host 'Please see the "Troubleshooting / FAQ" section in the readme.txt.' -ForegroundColor Red
    Write-Host

    $Error

    Exit-Script
}


# Try to access the localized Performance Process Counters
# It may be disabled

# This is the original english call:
# Get-Counter "\Process(*)\ID Process" -ErrorAction Stop
# We're starting a background job so that the Get-Counter call is not cached, which causes problems later on
$counter = Start-Job -ScriptBlock { 
    $data = @($input)
    (Get-Counter $data.'FullName' -ErrorAction SilentlyContinue).CounterSamples
} -InputObject $counterNames | Wait-Job | Receive-Job


if (!$counter) {
    Write-Host
    Write-Host 'FATAL ERROR: Could not access the Windows Performance Process Counter!' -ForegroundColor Red
    Write-Host
    Write-Host 'You may need to re-enable the Performance Process Counter (PerfProc).' -ForegroundColor Red
    Write-Host 'Please see the "Troubleshooting / FAQ" section in the readme.txt.' -ForegroundColor Red
    Write-Host
    Write-Host 'The localized counter name that was tried to access was:' -ForegroundColor Yellow
    Write-Host ('"' + $counterNames['FullName'] + '"') -ForegroundColor Yellow

    Exit-WithFatalError
}


# Make the external code definitions available to PowerShell
Add-Type -TypeDefinition $GetWindowDefinition
Add-Type -TypeDefinition $CloseWindowDefinition


# The name of the selected stress test program
$selectedStressTestProgram = $stressTestPrograms[$settings.General.stressTestProgram]['displayName']

# Set the correct process name
# Eventually this could be something different than just Prime95
if ($stressTestPrograms.Contains($settings.General.stressTestProgram)) {
    $processName = $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad']
}

# Default is Prime95
else {
    $processName = $stressTestPrograms['prime95']['processNameForLoad']
}


# Check if the stress test process is already running
$stressTestProcess = Get-Process $processName -ErrorAction SilentlyContinue

# Some programs share the same process for stress testing and for displaying the main window, and some not
if ($stressTestProgramsWithSameProcess.Contains($settings.General.stressTestProgram)) {
    $windowProcess = $stressTestProcess
}
else {
    $windowProcess = Get-Process $stressTestPrograms[$settings.General.stressTestProgram]['processName'] -ErrorAction SilentlyContinue
}

$Error.Clear()


# The expected CPU usage for the running stress test process
# The selected number of threads should be at 100%, so e.g. for 1 thread out of 24 threads this is 100/24*1= 4.17%
# Used to determine if the stress test is still running or has thrown an error
$expectedUsage = [Math]::Round(100 / $numLogicalCores * $settings.General.numberOfThreads, 2)


# Store all the cores that have thrown an error in the stress test
# These cores will be skipped on the next iteration
[Int[]] $coresWithError = @()


# Count the number of errors for each cores if the skipCoreOnError setting is 0
$coresWithErrorsCounter = @{}

for ($i = 0; $i -lt $numPhysCores; $i++) {
    $coresWithErrorsCounter[$i] = 0
}


# Check the CPU usage each x seconds
# Note: 15 seconds may fail if there was an error and Prime95 was restarted -> false positive
#       20 seconds may work fine, but it's probably best to wait for longer on the first check
$cpuUsageCheckInterval = 10


# Calculate the amount of interval checks for the CPU power check
$cpuCheckIterations = [Math]::Floor($settings.General.runtimePerCore / $cpuUsageCheckInterval)
$runtimeRemaining   = $settings.General.runtimePerCore - ($cpuCheckIterations * $cpuUsageCheckInterval)


# The Prime95 CPU settings for the various test modes
if ($settings.General.stressTestProgram -eq 'prime95') {
    $prime95CPUSettings = @{
        SSE = @{
            CpuSupportsSSE  = 1
            CpuSupportsSSE2 = 1
            CpuSupportsAVX  = 0
            CpuSupportsAVX2 = 0
            CpuSupportsFMA3 = 0
        }

        AVX = @{
            CpuSupportsSSE  = 1
            CpuSupportsSSE2 = 1
            CpuSupportsAVX  = 1
            CpuSupportsAVX2 = 0
            CpuSupportsFMA3 = 0
        }

        AVX2 = @{
            CpuSupportsSSE  = 1
            CpuSupportsSSE2 = 1
            CpuSupportsAVX  = 1
            CpuSupportsAVX2 = 1
            CpuSupportsFMA3 = 1
        }

        CUSTOM = @{
            CpuSupportsSSE  = 1
            CpuSupportsSSE2 = 1
            CpuSupportsAVX  = $settings.Custom.CpuSupportsAVX
            CpuSupportsAVX2 = $settings.Custom.CpuSupportsAVX2
            CpuSupportsFMA3 = $settings.Custom.CpuSupportsFMA3
        }
    }


    # The various FFT sizes for Prime95
    # Used to determine where an error likely happened
    # Note: These are different depending on the selected mode (SSE, AVX, AVX2)!
    # SSE:  4, 5, 6, 8, 10, 12, 14, 16,     20,     24,     28,     32,         40, 48, 56,     64, 72, 80, 84, 96,      112,      128,      144, 160,      192,      224, 240, 256,      288, 320, 336, 384, 400, 448, 480, 512, 560, 576, 640, 672, 720, 768, 800,      896, 960, 1024, 1120, 1152, 1200, 1280, 1344, 1440, 1536, 1600, 1680, 1728, 1792, 1920, 2048, 2240, 2304, 2400, 2560, 2688, 2800, 2880, 3072, 3200, 3360, 3456, 3584, 3840,       4096, 4480, 4608, 4800, 5120, 5376, 5600, 5760, 6144, 6400, 6720, 6912, 7168, 7680, 8000,       8192, 8960, 9216, 9600, 10240, 10752, 11200, 11520, 12288, 12800, 13440, 13824, 14336, 15360, 16000,        16384, 17920, 18432, 19200, 20480, 21504, 22400, 23040, 24576, 25600, 26880, 27648, 28672, 30720, 32000, 32768
    # AVX:  4, 5, 6, 8, 10, 12, 15, 16, 18, 20, 21, 24, 25, 28,     32, 35, 36, 40, 48, 50, 60, 64, 72, 80, 84, 96, 100, 112, 120, 128, 140, 144, 160, 168, 192, 200, 224, 240, 256,      288, 320, 336, 384, 400, 448, 480, 512, 560, 576, 640, 672, 720, 768, 800, 864, 896, 960, 1024,       1152,       1280, 1344, 1440, 1536, 1600, 1680, 1728, 1792, 1920, 2048,       2304, 2400, 2560, 2688,       2880, 3072, 3200, 3360, 3456, 3584, 3840, 4032, 4096, 4480, 4608, 4800, 5120, 5376,       5760, 6144, 6400, 6720, 6912, 7168, 7680, 8000,       8192, 8960, 9216, 9600, 10240, 10752,        11520, 12288, 12800, 13440, 13824, 14336, 15360, 16000, 16128, 16384, 17920, 18432, 19200, 20480, 21504, 22400, 23040, 24576, 25600, 26880,        28672, 30720, 32000, 32768
    # AVX2: 4, 5, 6, 8, 10, 12, 15, 16, 18, 20, 21, 24, 25, 28, 30, 32, 35, 36, 40, 48, 50, 60, 64, 72, 80, 84, 96, 100, 112, 120, 128,      144, 160, 168, 192, 200, 224, 240, 256, 280, 288, 320, 336, 384, 400, 448, 480, 512, 560,      640, 672,      768, 800,      896, 960, 1024, 1120, 1152,       1280, 1344, 1440, 1536, 1600, 1680,       1792, 1920, 2048, 2240, 2304, 2400, 2560, 2688, 2800, 2880, 3072, 3200, 3360,       3584, 3840,       4096, 4480, 4608, 4800, 5120, 5376, 5600, 5760, 6144, 6400, 6720,       7168, 7680, 8000, 8064, 8192, 8960, 9216, 9600, 10240, 10752, 11200, 11520, 12288, 12800, 13440, 13824, 14336, 15360, 16000, 16128, 16384, 17920, 18432, 19200, 20480, 21504, 22400, 23040, 24576, 25600, 26880,        28672, 30720, 32000, 32768, 35840, 38400, 40960, 44800, 51200 [...TODO]
    $FFTSizes = @{
        SSE = @(
            # Smallest FFT
            4, 5, 6, 8, 10, 12, 14, 16, 20,
            
            # Not used in Prime95 presets
            24, 28, 32,
            
            # Small FFT
            40, 48, 56, 64, 72, 80, 84, 96, 112, 128, 144, 160, 192, 224, 240,

            # Not used in Prime95 presets
            256, 288, 320, 336, 384, 400,

            # Large FFT
            448, 480, 512, 560, 576, 640, 672, 720, 768, 800, 896, 960, 1024, 1120, 1152, 1200, 1280, 1344, 1440, 1536, 1600, 1680, 1728, 1792, 1920,
            2048, 2240, 2304, 2400, 2560, 2688, 2800, 2880, 3072, 3200, 3360, 3456, 3584, 3840, 4096, 4480, 4608, 4800, 5120, 5376, 5600, 5760, 6144,
            6400, 6720, 6912, 7168, 7680, 8000, 8192

            # Not used in Prime95 presets
            # Now custom labeled "Huge"
            # 32768 seems to be the maximum FFT size possible for SSE
            # Note: Unfortunately Prime95 seems to randomize the order for Huge and All FFT sizes
            8960, 9216, 9600, 10240, 10752, 11200, 11520, 12288, 12800, 13440, 13824, 14336, 15360, 16000, 16384, 17920, 18432, 19200, 20480, 21504,
            22400, 23040, 24576, 25600, 26880, 27648, 28672, 30720, 32000, 32768
        )

        AVX = @(
            # Smallest FFT
            4, 5, 6, 8, 10, 12, 15, 16, 18, 20, 21,

            # Not used in Prime95 presets
            24, 25, 28, 32, 35,

            # Small FFT
            36, 40, 48, 50, 60, 64, 72, 80, 84, 96, 100, 112, 120, 128, 140, 144, 160, 168, 192, 200, 224, 240,

            # Not used in Prime95 presets
            256, 288, 320, 336, 384, 400,

            # Large FFT
            448, 480, 512, 560, 576, 640, 672, 720, 768, 800, 864, 896, 960, 1024, 1152, 1280, 1344, 1440, 1536, 1600, 1680, 1728, 1792, 1920,
            2048, 2304, 2400, 2560, 2688, 2880, 3072, 3200, 3360, 3456, 3584, 3840, 4032, 4096, 4480, 4608, 4800, 5120, 5376, 5760, 6144,
            6400, 6720, 6912, 7168, 7680, 8000, 8192

            # Not used in Prime95 presets
            # Now custom labeled "Huge"
            # 32768 seems to be the maximum FFT size possible for AVX
            # Note: Unfortunately Prime95 seems to randomize the order for Huge and All FFT sizes
            8960, 9216, 9600, 10240, 10752, 11520, 12288, 12800, 13440, 13824, 14336, 15360, 16000, 16128, 16384, 17920, 18432, 19200, 20480, 21504,
            22400, 23040, 24576, 25600, 26880, 28672, 30720, 32000, 32768
        )


        AVX2 = @(
            # Smallest FFT
            4, 5, 6, 8, 10, 12, 15, 16, 18, 20, 21,

            # Not used in Prime95 presets
            24, 25, 28, 30, 32, 35,

            # Small FFT
            36, 40, 48, 50, 60, 64, 72, 80, 84, 96, 100, 112, 120, 128, 144, 160, 168, 192, 200, 224, 240,

            # Not used in Prime95 presets
            256, 280, 288, 320, 336, 384, 400,

            # Large FFT
            448, 480, 512, 560, 640, 672, 768, 800, 896, 960, 1024, 1120, 1152, 1280, 1344, 1440, 1536, 1600, 1680, 1792, 1920,
            2048, 2240, 2304, 2400, 2560, 2688, 2800, 2880, 3072, 3200, 3360, 3584, 3840, 4096, 4480, 4608, 4800, 5120, 5376, 5600, 5760, 6144,
            6400, 6720, 7168, 7680, 8000, 8064, 8192

            # Not used in Prime95 presets
            # Now custom labeled "Huge"
            # 51200 seems to be the maximum FFT size possible for AVX2
            # Note: Unfortunately Prime95 seems to randomize the order for Huge and All FFT sizes
            8960, 9216, 9600, 10240, 10752, 11200, 11520, 12288, 12800, 13440, 13824, 14336, 15360, 16000, 16128, 16384, 17920, 18432, 19200, 20480,
            21504, 22400, 23040, 24576, 25600, 26880, 28672, 30720, 32000, 32768, 35840, 38400, 40960, 44800, 51200

            # An example of the randomization:
            # 11200, 8960, 9216, 9600, 10240, 10752, 11520, 11200, 11520, 12288, 11200, 8192, 11520, 12288, 12800, 13440, 13824, 8960, 14336, 15360,
            # 16000, 16128, 16384, 9216, 17920, 18432, 19200, 20480, 21504, 9600, 22400, 23040, 24576, 25600, 26880, 10240, 28672, 30720, 32000, 32768,
            # 35840, 10752, 38400, 40960, 44800, 51200
        )
    }


    # The min and max values for the various presets
    # Note that the actually tested sizes differ from the originally provided min and max values
    # depending on the selected test mode (SSE, AVX, AVX2)
    $FFTMinMaxValues = @{
        SSE = @{
            Smallest = @{ Min =    4; Max =    20; }  # Originally   4 ...   21
            Small    = @{ Min =   40; Max =   240; }  # Originally  36 ...  248
            Large    = @{ Min =  448; Max =  8192; }  # Originally 426 ... 8192
            Huge     = @{ Min = 8960; Max = 32768; }  # New addition
            All      = @{ Min =    4; Max = 32768; }
        }

        AVX = @{
            Smallest = @{ Min =    4; Max =    21; }  # Originally   4 ...   21
            Small    = @{ Min =   36; Max =   240; }  # Originally  36 ...  248
            Large    = @{ Min =  448; Max =  8192; }  # Originally 426 ... 8192
            Huge     = @{ Min = 8960; Max = 32768; }  # New addition
            All      = @{ Min =    4; Max = 32768; }
        }

        AVX2 = @{
            Smallest = @{ Min =    4; Max =    21; }  # Originally   4 ...   21
            Small    = @{ Min =   36; Max =   240; }  # Originally  36 ...  248
            Large    = @{ Min =  448; Max =  8192; }  # Originally 426 ... 8192
            Huge     = @{ Min = 8960; Max = 51200; }  # New addition
            All      = @{ Min =    4; Max = 51200; }
        }
    }


    # Get the correct min and max values for the selected FFT settings
    if ($settings.mode -eq 'CUSTOM') {
        $minFFTSize = [Int]$settings.Custom.MinTortureFFT
        $maxFFTSize = [Int]$settings.Custom.MaxTortureFFT
    }
    else {
        $minFFTSize = $FFTMinMaxValues[$settings.mode][$settings.Prime95.FFTSize].Min
        $maxFFTSize = $FFTMinMaxValues[$settings.mode][$settings.Prime95.FFTSize].Max
    }


    # Get the test mode, even if $settings.mode is set to CUSTOM
    $cpuTestMode = $settings.mode

    # If we're in CUSTOM mode, try to determine which setting preset it is
    if ($settings.mode -eq 'CUSTOM') {
        $cpuTestMode = 'SSE'

        if ($settings.Custom.CpuSupportsAVX -eq 1) {
            if ($settings.Custom.CpuSupportsAVX2 -eq 1 -and $settings.Custom.CpuSupportsFMA3 -eq 1) {
                $cpuTestMode = 'AVX2'
            }
            else {
                $cpuTestMode = 'AVX'
            }
        }
    }


    # The Prime95 results.txt file name for this run
    #$primeResultsName = 'Prime95_' + $curDateTime + '_' + $settings.mode + '_FFT_' + $minFFTSize + 'K-' + $maxFFTSize + 'K.txt'
    #$primeResultsPath = $logFilePathAbsolute + $primeResultsName
    
    # Unfortunately prime.log only logs communications with the PrimeNet server
    #$primeLogName = 'Prime95_output_' + $curDateTime + '_' + $settings.mode + '_FFT_' + $minFFTSize + 'K-' + $maxFFTSize + 'K.txt'
    #$primeLogPath = $logFilePathAbsolute + $primeLogName
}



# Close all existing instances of the stress test program and start a new one with our config
if ($stressTestProcess -or $windowProcess) {
    Write-Verbose('There already exists an instance of ' + $selectedStressTestProgram + ', trying to close it')

    if ($windowProcess) {
        Write-Verbose('Window Process ID: ' + $windowProcess.Id + ' - ProcessName: ' + $windowProcess.ProcessName)
    }
    if ($stressTestProcess) {
        Write-Verbose('Stress Test ID: ' + $stressTestProcess.Id + ' - ProcessName: ' + $stressTestProcess.ProcessName)
    }

    Close-StressTestProgram
}

# Create the required config files for the stress test program
Initialize-StressTestProgram


# Start the stress test program
Start-StressTestProgram


# Get the core test mode if it's set to default
$coreTestOrderMode = $settings.General.coreTestOrder

if ($settings.General.coreTestOrder -eq 'default') {
    if ($numPhysCores -gt 8) {
        $coreTestOrderMode = 'alternate'
    }
    else {
        $coreTestOrderMode = 'sequential'
    }
}


# All the cores in the system
$allCores = @(0..($numPhysCores-1))
$coresToTest = $allCores

# Subtract ignored cores
$coresToTest = $allCores | ? {$_ -notin $settings.General.coresToIgnore}


# Get the current datetime
$timestamp = Get-Date -format 'yyyy-MM-dd HH:mm:ss'


# Start messages
$headline     = ' CoreCycler v' + $version + ' started at ' + $timestamp + ' '
$padding      = 80 - $headline.Length
$paddingLeft  = [Math]::Ceiling($padding / 2)
$paddingRight = [Math]::Floor($padding / 2)

# Start messages
Write-ColorText('--------------------------------------------------------------------------------') Green
Write-ColorText(''.PadLeft($paddingLeft, '-') + $headline + ''.PadRight($paddingRight, '-')) Green
Write-ColorText('--------------------------------------------------------------------------------') Green

# Verbosity
if ($settings.Logging.verbosityMode -eq 1) {
    Write-ColorText('Verbose mode is ENABLED: .. Writing to log file') Cyan
}
elseif ($settings.Logging.verbosityMode -eq 2) {
    Write-ColorText('Verbose mode is ENABLED: .. Displaying in terminal') Cyan
}

# Display some initial information
Write-ColorText('Stress test program: ...... ' + $selectedStressTestProgram.ToUpper()) Cyan
Write-ColorText('Selected test mode: ....... ' + $settings.mode) Cyan
Write-ColorText('Logical/Physical cores: ... ' + $numLogicalCores + ' logical / ' + $numPhysCores + ' physical cores') Cyan
Write-ColorText('Hyperthreading / SMT is: .. ' + ($(if ($isHyperthreadingEnabled) { 'ON' } else { 'OFF' }))) Cyan
Write-ColorText('Selected number of threads: ' + $settings.General.numberOfThreads) Cyan
Write-ColorText('Runtime per core: ......... ' + (Get-FormattedRuntimePerCoreString $settings.General.runtimePerCore)) Cyan
Write-ColorText('Suspend periodically: ..... ' + ($(if ($settings.General.suspendPeriodically) { 'ENABLED' } else { 'DISABLED' }))) Cyan
Write-ColorText('Test order of cores: ...... ' + $settings.General.coreTestOrder.ToUpper() + ' (' + $coreTestOrderMode.ToUpper() + ')') Cyan
Write-ColorText('Number of iterations: ..... ' + $settings.General.maxIterations) Cyan

# Print a message if we're ignoring certain cores
if ($settings.General.coresToIgnore.Length -gt 0) {
    $coresToIgnoreString = (($settings.General.coresToIgnore | sort) -join ', ')
    Write-ColorText('Ignored cores: ............ ' + $coresToIgnoreString) Cyan
    Write-ColorText('--------------------------------------------------------------------------------') Cyan
}

if ($settings.mode -eq 'CUSTOM') {
    Write-ColorText('') Cyan
    Write-ColorText('Custom settings:') Cyan
    Write-ColorText('----------------') Cyan
    Write-ColorText('CpuSupportsAVX  = ' + $settings.Custom.CpuSupportsAVX) Cyan
    Write-ColorText('CpuSupportsAVX2 = ' + $settings.Custom.CpuSupportsAVX2) Cyan
    Write-ColorText('CpuSupportsFMA3 = ' + $settings.Custom.CpuSupportsFMA3) Cyan
    Write-ColorText('MinTortureFFT   = ' + $settings.Custom.MinTortureFFT) Cyan
    Write-ColorText('MaxTortureFFT   = ' + $settings.Custom.MaxTortureFFT) Cyan
    Write-ColorText('TortureMem      = ' + $settings.Custom.TortureMem) Cyan
    Write-ColorText('TortureTime     = ' + $settings.Custom.TortureTime) Cyan
}
else {
    if ($settings.General.stressTestProgram -eq 'prime95') {
        Write-ColorText('Selected FFT size: ........ ' + $settings.Prime95.FFTSize + ' (' + $minFFTSize + 'K - ' + $maxFFTSize + 'K)') Cyan
    }
}

Write-ColorText('--------------------------------------------------------------------------------') Cyan




# Display the log file location(s)
Write-ColorText('The log files for this run are stored in:') Cyan
Write-ColorText($logFilePathAbsolute) Cyan
Write-ColorText((' - CoreCycler:').PadRight(17, ' ') + $logFileName) Cyan

if ($stressTestLogFileName) {
    Write-ColorText((' - ' + $stressTestPrograms[$settings.General.stressTestProgram]['displayName'] + ':').PadRight(17, ' ') + $stressTestLogFileName) Cyan
}

Write-ColorText('--------------------------------------------------------------------------------') Cyan
Write-Text('')


# Try to get the affinity of the stress test program process. If not found, abort
try {
    $null = $stressTestProcess.ProcessorAffinity

    Write-Verbose('The current affinity of the process: ' + $stressTestProcess.ProcessorAffinity)
}
catch {
    Exit-WithFatalError('Process ' + $processName + ' not found!')
}



# Repeat the whole check $settings.General.maxIterations times
for ($iteration = 1; $iteration -le $settings.General.maxIterations; $iteration++) {
    $timestamp = Get-Date -format HH:mm:ss

    # Check if all of the cores have thrown an error, and if so, abort
    # Only if the skipCoreOnError setting is set
    if ($settings.General.skipCoreOnError -and $coresWithError.Length -eq ($numPhysCores - $settings.General.coresToIgnore.Length)) {
        # Also close the stress test program process to not let it run unnecessarily
        Close-StressTestProgram
        
        Write-Text($timestamp + ' - All Cores have thrown an error, aborting!')
        Exit-Script
    }


    Write-ColorText('') Yellow
    Write-ColorText($timestamp + ' - Iteration ' + $iteration) Yellow
    Write-ColorText('----------------------------------') Yellow


    $previousCoreNumber = $null
    $availableCores     = $coresToTest
    $halfCores          = $numPhysCores / 2
    
    # Iterate over each core
    # Named for loop
    :coreLoop for ($coreNumber = 0; $coreNumber -lt $numPhysCores; $coreNumber++) {
        $startDateThisCore  = (Get-Date)
        $endDateThisCore    = $startDateThisCore + (New-TimeSpan -Seconds $settings.General.runtimePerCore)
        $timestamp          = $startDateThisCore.ToString("HH:mm:ss")
        $affinity           = [Int64]0
        $actualCoreNumber   = $coreNumber
        $cpuNumbersArray    = @()


        # Get the current CPU core(s)
        # If the core test order mode is random or alternate, we need to get the actual core to tests
        if ($coreTestOrderMode -eq 'alternate') {
            Write-Verbose('Alternating test order selected, getting the core to test...')
            Write-Verbose('Previous core: ' + $previousCoreNumber)

            if ($previousCoreNumber -ne $null) {
                if ($previousCoreNumber -lt $halfCores) {
                    $actualCoreNumber = $previousCoreNumber + $halfCores
                }
                else {
                    $actualCoreNumber = $previousCoreNumber - $halfCores + 1
                }
            }

            $previousCoreNumber = $actualCoreNumber
        }
        elseif ($coreTestOrderMode -eq 'random') {
            Write-Verbose('Random test order selected, getting the core to test...')
            Write-Verbose('Still available cores: ' + ($availableCores -Join ', '))
            
            $actualCoreNumber = $availableCores | Get-Random
            $availableCores = $availableCores | ? {$_ -ne $actualCoreNumber}
        }


        # If the number of threads is more than 1
        if ($settings.General.numberOfThreads -gt 1) {
            for ($currentThread = 0; $currentThread -lt $settings.General.numberOfThreads; $currentThread++) {
                # We don't care about Hyperthreading / SMT here, it needs to be enabled for 2 threads
                $thisCPUNumber    = ($actualCoreNumber * 2) + $currentThread
                $cpuNumbersArray += $thisCPUNumber
                $affinity        += [Math]::Pow(2, $thisCPUNumber)
            }
        }

        # Only one thread
        else {
            # If Hyperthreading / SMT is enabled, the tested CPU number is 0, 2, 4, etc
            # Otherwise, it's the same value
            $cpuNumber        = $actualCoreNumber * (1 + [Int]$isHyperthreadingEnabled)
            $cpuNumbersArray += $cpuNumber
            $affinity         = [Math]::Pow(2, $cpuNumber)
        }

        Write-Verbose('The selected core to test: ' + $actualCoreNumber)

        $cpuNumberString = (($cpuNumbersArray | sort) -join ' and ')


        # Skip if this core is in the ignored cores array
        if ($settings.General.coresToIgnore -contains $actualCoreNumber) {
            # Ignore it silently
            Write-Verbose('Core ' + $actualCoreNumber + ' (CPU ' + $cpuNumberString + ') is being ignored, skipping')
            continue
        }

        # Skip if this core is stored in the error core array
        if ($settings.General.skipCoreOnError -and $coresWithError -contains $actualCoreNumber) {
            Write-Text($timestamp + ' - Core ' + $actualCoreNumber + ' (CPU ' + $cpuNumberString + ') has previously thrown an error, skipping')
            continue
        }


        # Apparently Aida64 doesn't like having the affinity set to 1
        # Possible workaround: Set it to 2 instead
        # This also poses a problem when testing two threads on core 0, so we're skipping this core for the time being
        if ($settings.General.stressTestProgram -eq 'aida64' -and $affinity -eq 1) {
            Write-ColorText('           Notice!') Black Yellow

            # If Hyperthreading / SMT is enabled
            if ($isHyperthreadingEnabled) {
                Write-ColorText('           Apparently Aida64 doesn''t like running the stress test on the first thread of Core 0.') Black Yellow
                Write-ColorText('           Setting it to thread 2 of Core 0 instead (Core 0 CPU 1).') Black Yellow
                
                $affinity = 2
                $cpuNumber = 1
                $cpuNumberString = 1
            }

            # For disabled Hyperthreading / SMT, there's not much we can do. So skipping it
            else {
                Write-ColorText('           Apparently Aida64 doesn''t like running the stress test on Core 0 only.') Black Yellow
                Write-ColorText('           Normally we''d fall back to thread 2 on Core 0, but since Hyperthreading / SMT is disabled, we cannot do this.') Black Yellow
                Write-ColorText('           Therefore we''re skipping this core.') Black Yellow

                Write-Verbose('Skipping this core due to Aida64 not running correctly on Core 0 CPU 0 and Hyperthreading / SMT is disabled')
                continue
            }
        }

        # Aida64 running on CPU 0 and CPU 1 (2 threads)
        elseif ($settings.General.stressTestProgram -eq 'aida64' -and $affinity -eq 3) {
            Write-ColorText('           Notice!') Black Yellow
            Write-ColorText('           Apparently Aida64 doesn''t like running the stress test on the first thread of Core 0.') Black Yellow
            Write-ColorText('           So you might see an error due to decreased CPU usage.') Black Yellow
            #$affinity = 
        }
        

        # If $settings.General.restartTestProgramForEachCore is set, restart the stress test program for each core
        if ($settings.General.restartTestProgramForEachCore -and ($iteration -gt 1 -or $actualCoreNumber -gt $coresToTest[0])) {
            Write-Verbose('restartTestProgramForEachCore is set, restarting the test program...')

            Close-StressTestProgram

            # If the delayBetweenCores setting is set, wait for the defined amount
            if ($settings.General.delayBetweenCores -gt 0) {
                Write-Text('           Idling for ' + $settings.General.delayBetweenCores + ' seconds before continuing to the next core...')

                # Also adjust the expected end time for this delay
                $endDateThisCore += New-TimeSpan -Seconds $settings.General.delayBetweenCores

                Start-Sleep -Seconds $settings.General.delayBetweenCores
            }

            Start-StressTestProgram
        }
        
       
        # This core has not thrown an error yet, run the test
        $timestamp = (Get-Date).ToString("HH:mm:ss")
        Write-Text($timestamp + ' - Set to Core ' + $actualCoreNumber + ' (CPU ' + $cpuNumberString + ')')
        
        # Set the affinity to a specific core
        try {
            Write-Verbose('Setting the affinity to ' + $affinity)

            $stressTestProcess.ProcessorAffinity = [System.IntPtr][Int64]$affinity
        }
        catch {
            # Apparently setting the affinity can fail on the first try, so make another attempt
            Write-Verbose('Setting the affinity has failed, trying again...')
            Start-Sleep -Milliseconds 300

            try {
                $stressTestProcess.ProcessorAffinity = [System.IntPtr][Int64]$affinity
            }
            catch {
                Close-StressTestProgram
                Exit-WithFatalError('Could not set the affinity to Core ' + $actualCoreNumber + ' (CPU ' + $cpuNumberString + ')!')                
            }
        }

        Write-Verbose('Successfully set the affinity to ' + $affinity)

        # If this core is stored in the error core array and the skipCoreOnError setting is not set, display the amount of errors
        if (!$settings.General.skipCoreOnError -and $coresWithError -contains $actualCoreNumber) {
            $text  = '           Note: This core has previously thrown ' + $coresWithErrorsCounter[$actualCoreNumber] + ' error'
            $text += $(if ($coresWithErrorsCounter[$actualCoreNumber] -gt 1) {'s'})
            
            Write-Text($text)
        }

        Write-Text('           Running for ' + (Get-FormattedRuntimePerCoreString $settings.General.runtimePerCore) + '...')


        # Make a check each x seconds for the CPU power usage
        for ($checkNumber = 0; $checkNumber -lt $cpuCheckIterations; $checkNumber++) {
            $nowDateTime = (Get-Date)
            $difference  = New-TimeSpan -Start $nowDateTime -End $endDateThisCore


            # Make this the last iteration if the remaining time is close enough
            if ($difference.TotalSeconds -le $cpuUsageCheckInterval) {
                $checkNumber = $cpuCheckIterations
                $waitTime    = [Math]::Max(0, $difference.TotalSeconds - 1)
                Start-Sleep -Seconds $waitTime
            }
            else {
                Start-Sleep -Seconds $cpuUsageCheckInterval
            }
            

            # Check if the process is still using enough CPU process power
            try {
                Test-ProcessUsage $actualCoreNumber
            }
            
            # On error, the Prime95 process is not running anymore, so skip this core
            catch {
                Write-Verbose('There has been some error in Test-ProcessUsage, checking')

                if ($Error -and $Error[0].ToString() -eq '999') {
                    Write-Verbose($selectedStressTestProgram + ' seems to have stopped with an error at Core ' + $actualCoreNumber + ' (CPU ' + $cpuNumberString + ')')
                    continue coreLoop
                }
                else {
                    Write-ColorText('FATAL ERROR:') Red
                    Write-ErrorText $Error
                    Exit-WithFatalError
                }
            }

            # Get the current CPU frequency
            $currentCpuInfo = Get-CpuFrequency $cpuNumber
            Write-Verbose('           ...current CPU frequency: ~' + $currentCpuInfo.CurrentFrequency + ' MHz (' + $currentCpuInfo.Percent + '%)')


            # Suspend and resume the stress test
            if ($settings.General.suspendPeriodically) {
                Write-Verbose('Suspending the stress test process')
                $suspended = Suspend-ProcessWithDebugMethod $stressTestProcess
                Write-Verbose('Suspended: ' + $suspended)

                Start-Sleep -Milliseconds 1000

                Write-Verbose('Resuming the stress test process')
                $resumed = Resume-ProcessWithDebugMethod $stressTestProcess
                Write-Verbose('Resumed: ' + $resumed)
            }
        }
        
        # Wait for the remaining runtime
        Start-Sleep -Seconds $runtimeRemaining
        
        # One last check
        try {
            Test-ProcessUsage $actualCoreNumber
        }
        
        # On error, the Prime95 process is not running anymore, so skip this core
        catch {
            Write-Verbose('There has been some error in Test-ProcessUsage, checking')

            if ($Error -and $Error[0] -eq '999') {
                Write-Verbose($selectedStressTestProgram + ' seems to have stopped with an error at Core ' + $actualCoreNumber + ' (CPU ' + $cpuNumberString + ')')
                continue
            }
            else {
                Write-ColorText('FATAL ERROR:') Red
                Write-ErrorText $Error
                Exit-WithFatalError
            }
        }

        $timestamp = (Get-Date).ToString("HH:mm:ss")
        Write-Text($timestamp + ' - Completed the test on Core ' + $actualCoreNumber + ' (CPU ' + $cpuNumberString + ')')
    }
    
    
    # Print out the cores that have thrown an error so far
    if ($coresWithError.Length -gt 0) {
        if ($settings.General.skipCoreOnError) {
            Write-ColorText('The following cores have thrown an error: ' + (($coresWithError | sort) -join ', ')) Blue
        }
        else {
            Write-ColorText('The following cores have thrown an error:') Blue

            $coreWithTwoDigitsHasError = $false

            foreach ($entry in $coresWithErrorsCounter.GetEnumerator()) {
                if ( $entry.Name -gt 9 -and $entry.Value -gt 0) {
                    $coreWithTwoDigitsHasError = $true
                    break
                }
            }
            
            foreach ($entry in ($coresWithErrorsCounter.GetEnumerator() | Sort Name)) {
                # No error, skip
                if ($entry.Value -lt 1) {
                    continue
                }

                $corePadding = $(if ($coreWithTwoDigitsHasError) {' '} else {''})
                $coreText  = $(if ($entry.Name -lt 10) {$corePadding})
                $coreText += $entry.Name.ToString()

                $textErrors      = 'error'
                $textIterations  = 'iteration'

                $textErrors     += $(if ($entry.Value -gt 1) {'s'})
                $textIterations += $(if ($iteration -gt 1) {'s'})

                Write-ColorText('    - Core ' + $coreText + ': ' + $entry.Value.ToString() + ' ' + $textErrors + ' in ' + $iteration + ' ' + $textIterations) Blue
            }
        }
    }
}


# The CoreCycler has finished
$timestamp = Get-Date -format HH:mm:ss
Write-Text($timestamp + ' - CoreCycler finished')
Close-StressTestProgram
Exit-Script