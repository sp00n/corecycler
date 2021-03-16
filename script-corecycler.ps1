<#
.AUTHOR
    sp00n
.VERSION
    0.7.9.2
.DESCRIPTION
    Sets the affinity of the Prime95 process to only one core and cycles through all the cores
    to test the stability of a Curve Optimizer setting
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
$version                = '0.7.9.2'
$curDateTime            = Get-Date -format yyyy-MM-dd_HH-mm-ss
$settings               = $null
$logFilePath            = $null
$processWindowHandler   = $null
$processId              = $null
$process                = $null
$processCounterPathId   = $null
$processCounterPathTime = $null
$coresWithError         = $null
$coresWithErrorsDetails = $null
$previousError          = $null


# The Prime95 executable name and path
$processName = 'prime95'
$processPath = $PSScriptRoot + '\p95\'
$primePath   = $processPath + $processName


# Used to get around the localized counter names
$englishCounterNames = @(
    'Process',
    'ID Process',
    '% Processor Time'
)

# This stores the Name:ID pairs of the english counter names
$counterNameIds = @{}

# This holds the localized counter names
$counterNames = @{
    'Process'          = ''
    'ID Process'       = ''
    '% Processor Time' = ''
    'FullName'         = ''
    'SearchString'     = ''
    'ReplaceString'    = ''
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


# Add code definitions so that we can close the Prime95 window even if it's minimized to the tray
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
    Add-Content $logFilePath ($text)
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
 # .PARAM string $color The color
 # .RETURN void
 #>
function Write-ColorText {
    param(
        $text,
        $foregroundColor
    )

    # -ForegroundColor <ConsoleColor>
    # -BackgroundColor <ConsoleColor>
    # Black, DarkBlue, DarkGreen, DarkCyan, DarkRed, DarkMagenta, DarkYellow, Gray, DarkGray, Blue, Green, Cyan, Red, Magenta, Yellow, White
    
    Write-Host $text -ForegroundColor $foregroundColor
    Add-Content $logFilePath ($text)
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
    
    if ($settings.verbosityMode) {
        if ($settings.verbosityMode -gt 1) {
            Write-Host('           ' + '      + ' + $text)
        }

        Add-Content $logFilePath ('           ' + '      + ' + $text)
    }

}


<##
 # Throw a fatal error
 # .PARAM string $text The text to display
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
 # Get the settings
 # .PARAM void
 # .RETURN void
 #>
function Get-Settings {
    # Default config settings
    # Change the various settings in the config.ini file

    $defaultSettings = @{

        # The mode of the stress test
        # 'SSE':    lightest load on the processor, lowest temperatures, highest boost clock
        # 'AVX':    medium load on the processor, medium temperatures, medium boost clock
        # 'AVX2':   heaviest on the processor, highest temperatures, lowest boost clock
        # 'CUSTOM': you can define your own settings (see further below for setting the values)
        mode = 'SSE'


        # The FFT size preset to test
        # These are basically the presets as present in Prime95
        # Note: If "mode" is set to "CUSTOM", this setting will be ignored
        # 'Smallest':  Smallest FFT: 4K to 21K     - tests L1/L2 caches, high power/heat/CPU stress
        # 'Small':     Small FFT:    36K to 248K   - tests L1/L2/L3 caches, maximum power/heat/CPU stress
        # 'Large':     Large FFT:    426K to 8192K - stresses memory controller and RAM (although memory testing is disabled here by default!)
        # 'Huge':      New custom mode: anything above 8192K
        # 'All':       All FFT:      4K to whatever is the highest FFT (32768K for SSE/AVX, 51200 for AVX2)
        # Default: 'Huge'
        FFTSize = 'Huge'


        # Set the runtime per core
        # You can use a value in seconds or use 'h' for hours, 'm' for minutes and 's' for seconds
        # Examples: 360 = 360 seconds
        #           1h4m = 1 hour, 4 minutes
        #           1.5m = 1.5 minutes = 90 seconds
        # Default: 360
        runtimePerCore = 360


        # Skip a core that has thrown an error on the following iterations
        # If set to 0, this will test a core on the next iterations even if has thrown an error before
        # Default: 1
        skipOnError = 1


        # Stop the whole testing process if an error occurred
        # If set to 0 (default), the stress test programm will be restarted when an error
        # occurs and the core that caused the error will be skipped on the next iteration
        # Default: 0
        stopOnError = 0


        # The number of threads to use for testing
        # You can only choose between 1 and 2
        # If Hyperthreading / SMT is disabled, this will automatically be set to 1
        # Currently there's no automatic way to determine which core has thrown an error
        # Setting this to 1 causes higher boost clock speed (due to less heat)
        # Default is 1
        # Maximum is 2
        numberOfThreads = 1


        # The max number of iterations, 10000 is basically unlimited
        maxIterations = 10000


        # Ignore certain cores
        # These cores will not be tested
        # The enumeration starts with a 0
        # Example: $settings.coresToIgnore = @(0, 1, 2)
        coresToIgnore = @()


        # Restart the Prime95 process for each new core test
        # So each core will have the same sequence of FFT sizes
        # The sequence of FFT sizes for Small FFTs:
        # 40, 48, 56, 64, 72, 80, 84, 96, 112, 128, 144, 160, 192, 224, 240
        # Runtime on a 5900x: 5,x minutes
        # Note: The screen never seems to turn off with this setting enabled
        restartPrimeForEachCore = 0


        # If the "restartPrimeForEachCore" flag is set, this setting will define the amount of seconds between the end of the
        # run of one core and the start of another
        # If "restartPrimeForEachCore" is 0, this setting has no effect
        # Default: 15
        delayBetweenCycles = 15


        # The name of the log file
        # The $settings.mode and the $settings.FFTSize above will be added to the name (and a .log file ending)
        logfile = 'CoreCycler'


        # Set this to 1 to see a bit more text in the terminal
        # 1: Write additional information to the log file
        # 2: Also display the additional information in the terminal
        # Default: 0
        verbosityMode = 0


        # Set the custom settings here for the 'CUSTOM' mode
        # Note: The automatic detection at which FFT size an error likely occurred
        #       will not work if you change the FFT sizes
        customCpuSupportsAVX  = 0         # Needs to be set to 1 for AVX mode (and AVX2)
        customCpuSupportsAVX2 = 0         # Needs to be set to 1 for AVX2 mode
        customCpuSupportsFMA3 = 0         # Also needs to be set to 1 for AVX2 mode on Ryzen
        customMinTortureFFT   = 36        # The minimum FFT size to test
        customMaxTortureFFT   = 248       # The maximum FFT size to test
        customTortureMem      = 0         # The amount of memory to use in MB. 0 = In-Place
        customTortureTime     = 1         # The max amount of minutes for each FFT size
    }


    # Set the default settings
    $settings = $defaultSettings


    # The full path and name of the log file
    $Script:logfilePath = $PSScriptRoot + '\logs\' + $settings.logfile + '_' + $curDateTime + '_' + $settings.mode + '.log'


    # If no config file exists, copy the config.default.ini to config.ini
    if (!(Test-Path 'config.ini' -PathType leaf)) {
        
        if (!(Test-Path 'config.default.ini' -PathType leaf)) {
            Exit-WithFatalError('Neither config.ini nor config.default.ini found!')
        }

        Copy-Item -Path 'config.default.ini' -Destination 'config.ini'
    }


    # Read the config file and overwrite the default settings
    $userSettings = Get-Content -raw 'config.ini' | ConvertFrom-StringData

    # Check if the config.ini contained valid setting
    # It may be corrupted if the computer immediately crashed due to unstable settings
    try {
        foreach ($entry in $userSettings.GetEnumerator()) {
        }
    }

    # Couldn't get the a valid content from the config.ini, replace it with the default
    catch {
        Write-ColorText('WARNING: config.ini corrupted, replacing with default values!') Yellow

        Copy-Item -Path 'config.default.ini' -Destination 'config.ini'
        $userSettings = Get-Content -raw 'config.ini' | ConvertFrom-StringData
    }


    foreach ($entry in $userSettings.GetEnumerator()) {
        # Special handling for coresToIgnore
        if ($entry.Name -eq 'coresToIgnore') {
            if ($entry.Value -and ![string]::IsNullOrEmpty($entry.Value) -and ![String]::IsNullOrWhiteSpace($entry.Value)) {
                # Split the string by comma and add to the coresToIgnore entry
                $entry.Value -split ',\s*' | ForEach-Object {
                    $settings.coresToIgnore += [Int]$_
                }
            }
        }

        # Setting cannot be empty
        elseif ($entry.Value -and ![string]::IsNullOrEmpty($entry.Value) -and ![String]::IsNullOrWhiteSpace($entry.Value)) {
            # For anything but the mode, logfile, and FFTSize parameters, transform the value to an integer
            if ($entry.Name -eq 'logfile' -or $entry.Name -eq 'mode' -or $entry.Name -eq 'FFTSize') {
                $settings[$entry.Name] = [String]$entry.Value
            }

            # Parse the runtime per core (seconds, minutes, hours)
            elseif ($entry.Name -eq 'runtimePerCore') {
                # Parse the hours, minutes, seconds
                if ($entry.Value.indexOf('h') -ge 0 -or $entry.Value.indexOf('m') -ge 0 -or $entry.Value.indexOf('s') -ge 0) {
                    $hasMatched = $entry.Value -match '((?<hours>\d+(\.\d+)*)h)*\s*((?<minutes>\d+(\.\d+)*)m)*\s*((?<seconds>\d+(\.\d+)*)s)*'
                    $seconds = [Double]$matches.hours * 60 * 60 + [Double]$matches.minutes * 60 + [Double]$matches.seconds
                    $settings[$entry.Name] = [Int]$seconds
                }

                # Treat the value as seconds
                else {
                    $settings[$entry.Name] = [Int]$entry.Value
                }
            }

            else {
                $settings[$entry.Name] = [Int]$entry.Value
            }
        }

        # If it is empty, just ignore and use the default setting
    }


    # Limit the number of threads to 1 - 2
    $settings.numberOfThreads = [Math]::Max(1, [Math]::Min(2, $settings.numberOfThreads))
    $settings.numberOfThreads = $(if ($isHyperthreadingEnabled) { $settings.numberOfThreads } else { 1 })


    # Store in the global variable
    $Script:settings = $settings
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
 # Get the main window handler for the Prime95 process
 # Even if minimized to the tray
 # .PARAM void
 # .RETURN void
 #>
function Get-Prime95WindowHandler {
    # 'Prime95 - Self-Test': worker running
    # 'Prime95 - Not running': worker not running anymore
    # 'Prime95 - Waiting for work': worker not running, tried to start, no worker started
    # 'Prime95': worker not yet started
    $windowNames = @(
        '^Prime95 \- Self\-Test$'
        '^Prime95 \- Not running$'
        '^Prime95 \- Waiting for work$'
        '^Prime95$'
    )

    Write-Verbose('Trying to get the Prime95 window handler');
    Write-Verbose('Looking for these window names:')
    Write-Verbose(($windowNames -Join ', '))

    $windowObj = [Api.Apidef]::GetWindows() | Where-Object {
        $_.WinTitle -match ($windowNames -Join '|')
    }

    Write-Verbose('Found the following window(s) with these names:')

    $windowObj | ForEach-Object {
        $path = (Get-Process -Id $_.ProcessId).Path
        Write-Verbose(' - WinTitle:     ' + $_.WinTitle)
        Write-Verbose('   ProcessId:    ' + $_.ProcessId)
        Write-Verbose('   Process Path: ' + $path)
    }


    # There might be another window open with the name "Prime95"
    # Select the correct one
    Write-Verbose('Filtering the windows for ".*prime95\.exe$":')

    $filteredWindowObj = $windowObj | Where-Object {
        (Get-Process -Id $_.ProcessId).Path -match ('.*prime95\.exe$')
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
        Write-ColorText('FATAL ERROR: Could not find the correct Prime95 window!') Red
        Write-ColorText('There exist multiple windows with the same name as the Prime95:') Red
        
        $filteredWindowObj | ForEach-Object {
            $path = (Get-Process -Id $_.ProcessId).Path
            Write-ColorText(' - Windows Title: ' + $_.WinTitle) Yellow
            Write-ColorText('   Process Path:  ' + $path) Yellow
            Write-ColorText('   Process Id:    ' + $_.ProcessId) Yellow
        }

        Write-ColorText('Please close these windows and try again.') Red
        Exit-WithFatalError
    }


    # Override the global script variables
    $Script:processWindowHandler = $filteredWindowObj.MainWindowHandle
    $Script:processId = $filteredWindowObj.ProcessId

    Write-Verbose('Prime95 window handler: ' + $processWindowHandler)
    Write-Verbose('Prime95 process ID:     ' + $processId)
}


<##
 # Open Prime95 and set global script variables
 # .PARAM void
 # .RETURN void
 #>
function Start-Prime95 {
    Write-Verbose('Starting Prime95')

    # Minimized to the tray
    $Script:process = Start-Process -filepath $primePath -ArgumentList '-t' -PassThru -WindowStyle Hidden
    
    # Minimized to the task bar
    #$Script:process = Start-Process -filepath $primePath -ArgumentList '-t' -PassThru -WindowStyle Minimized

    # This might be necessary to correctly read the process. Or not
    Start-Sleep -Milliseconds 500
    
    if (!$Script:process) {
        Exit-WithFatalError('Could not start process ' + $processName + '!')
    }

    # Get the main window handler
    # This also works for windows minimized to the tray
    Get-Prime95WindowHandler
    
    # This is to find the exact counter path, as you might have multiple processes with the same name
    try {
        # Start a background job to get around the cached Get-Counter value
        $Script:processCounterPathId = Start-Job -ScriptBlock { 
            $counterPathName = $args[0].'FullName'
            $processId = $args[1]
            ((Get-Counter $counterPathName -ErrorAction SilentlyContinue).CounterSamples | ? {$_.RawValue -eq $processId}).Path
        } -ArgumentList $counterNames, $processId | Wait-Job | Receive-Job

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
 # Create the Prime95 config files (local.txt & prime.txt)
 # This depends on the $settings.mode variable
 # .PARAM string $configType The config type to set in the config files (SSE, AVX, AVX, CUSTOM)
 # .RETURN void
 #>
function Initialize-Prime95 {
    param (
        $configType
    )

    $configFile1 = $processPath + 'local.txt'
    $configFile2 = $processPath + 'prime.txt'

    if ($configType -ne 'CUSTOM' -and $configType -ne 'SSE' -and $configType -ne 'AVX' -and $configType -ne 'AVX2') {
        Exit-WithFatalError('Invalid mode type provided!')
    }

    # Create the local.txt and overwrite if necessary
    $null = New-Item $configFile1 -ItemType File -Force

    Set-Content $configFile1 'RollingAverageIsFromV27=1'
    
    # Limit the load to the selected number of threads
    Add-Content $configFile1 ('NumCPUs=1')
    Add-Content $configFile1 ('CoresPerTest=1')
    Add-Content $configFile1 ('CpuNumHyperthreads=' + $settings.numberOfThreads)
    Add-Content $configFile1 ('WorkerThreads='      + $settings.numberOfThreads)
    Add-Content $configFile1 ('CpuSupportsSSE='     + $prime95CPUSettings[$settings.mode].CpuSupportsSSE)
    Add-Content $configFile1 ('CpuSupportsSSE2='    + $prime95CPUSettings[$settings.mode].CpuSupportsSSE2)
    Add-Content $configFile1 ('CpuSupportsAVX='     + $prime95CPUSettings[$settings.mode].CpuSupportsAVX)
    Add-Content $configFile1 ('CpuSupportsAVX2='    + $prime95CPUSettings[$settings.mode].CpuSupportsAVX2)
    Add-Content $configFile1 ('CpuSupportsFMA3='    + $prime95CPUSettings[$settings.mode].CpuSupportsFMA3)
    

    
    # Create the prime.txt and overwrite if necessary
    $null = New-Item $configFile2 -ItemType File -Force
    
    # Set the custom results.txt file name
    Set-Content $configFile2 ('results.txt=' + $primeResultsName)
    
    # Custom settings
    if ($configType -eq 'CUSTOM') {
        Add-Content $configFile2 ('TortureMem='    + $settings.customTortureMem)
        Add-Content $configFile2 ('TortureTime='   + $settings.customTortureTime)
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
    Add-Content $configFile2 '[PrimeNet]'
    Add-Content $configFile2 'Debug=0'
}


<##
 # Close Prime95
 # .PARAM void
 # .RETURN void
 #>
function Close-Prime95 {
    Write-Verbose('Closing Prime95')

    # If there is no processWindowHandler id
    # Try to get it
    if (!$processWindowHandler) {
        Get-Prime95WindowHandler
    }
    
    # If we now have a processWindowHandler, try to close the window
    if ($processWindowHandler) {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        $Error.Clear()

        Write-Verbose('Trying to gracefully close Prime95')
        
        # This returns false if no window is found with this handle
        if (![Win32]::SendMessage($processWindowHandler, [Win32]::WM_CLOSE, 0, 0) | Out-Null) {
            #'Process Window not found!'
        }

        # We've send the close request, let's wait up to 2 seconds
        elseif ($process -and !$process.HasExited) {
            #'Waiting for the exit'
            $null = $process.WaitForExit(3000)
        }
    }
    
    
    # If the window is still here at this point, just kill the process
    $process = Get-Process $processName -ErrorAction SilentlyContinue
    $Error.Clear()

    if ($process) {
        Write-Verbose('Could not gracefully close Prime95, killing the process')
        
        #'The process is still there, killing it'
        # Unfortunately this will leave any tray icons behind
        Stop-Process $process.Id -Force -ErrorAction SilentlyContinue
    }
    else {
        Write-Verbose('Prime95 closed')
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

    $timestamp = Get-Date -format HH:mm:ss
    
    # The minimum CPU usage for Prime95, below which it should be treated as an error
    # We need to account for the number of threads
    # Min. 1.5%
    # 100/32=   3,125% for 1 thread out of 32 threads
    # 100/32*2= 6,250% for 2 threads out of 32 threads
    # 100/24=   4,167% for 1 thread out of 24 threads
    # 100/24*2= 8,334% for 2 threads out of 24 threads
    # 100/12=   8,334% for 1 thread out of 12 threads
    # 100/12*2= 16,67% for 2 threads out of 12 threads
    $minPrimeUsage = [Math]::Max(1.5, $expectedUsage - [Math]::Round(100 / $numLogicalCores, 2))
    
    
    # Set to a string if there was an error
    $primeError = $false

    # Get the content of the results.txt file
    $resultFileHandle = Get-Item -Path $primeResultsPath -ErrorAction SilentlyContinue
    $Error.Clear()

    # Does the process still exist?
    $process = Get-Process $processName -ErrorAction SilentlyContinue
    $Error.Clear()
    

    # 1. The process doesn't exist anymore, immediate error
    if (!$process) {
        $primeError = 'The Prime95 process doesn''t exist anymore.'
    }

    
    # 2. Parse the results.txt file and look for an error message
    if (!$primeError) {
        # Look for a line with an "error" string in the last 3 lines
        $primeResults = $resultFileHandle | Get-Content -Tail 3 | Where-Object {$_ -like '*error*'}
        
        # Found the "error" string in the results.txt
        if ($primeResults.Length -gt 0) {
            # Get the line number of the last error message in the results.txt
            $p95Errors = Select-String $primeResultsPath -Pattern ERROR
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

                $primeError = $primeResults
            }
        }
    }


    # 3. Check if the process is still using enough CPU process power
    if (!$primeError) {
        # Get the CPU percentage
        $processCPUPercentage = [Math]::Round(((Get-Counter $processCounterPathTime -ErrorAction SilentlyContinue).CounterSamples.CookedValue) / $numLogicalCores, 2)
        $Error.Clear()
        
        Write-Verbose($timestamp + ' - ...checking CPU usage: ' + $processCPUPercentage + '%')

        # It doesn't use enough CPU power
        if ($processCPUPercentage -le $minPrimeUsage) {
            # Try to read the error from Prime95's results.txt
            # Look for a line with an "error" string in the last 3 lines
            $primeResults = $resultFileHandle | Get-Content -Tail 3 | Where-Object {$_ -like '*error*'}

            # Found the "error" string in the results.txt
            if ($primeResults.Length -gt 0) {
                $primeError = $primeResults
            }

            # Error string not found
            # This might have been a false alarm, wait a bit and try again
            else {
                $waitTime = 2000

                Write-Verbose($timestamp + ' - ...the CPU usage was too low, waiting ' + $waitTime + 'ms for another check...')

                Start-Sleep -Milliseconds $waitTime

                # The second check
                # Do the whole process path procedure again
                $thisProcessId = $process.Id[0]

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
                if ($processCPUPercentage -le $minPrimeUsage) {
                    # We don't care about an error string here anymore
                    $primeError = 'The Prime95 process doesn''t use enough CPU power anymore (only ' + $processCPUPercentage + '% instead of the expected ' + $expectedUsage + '%)'
                }
            }
        }
    }


    if ($primeError) {
        # Store the core number in the array
        $Script:coresWithError += $coreNumber

        # Count the number of errors per core
        $Script:coresWithErrorsCounter[$coreNumber]++ 

        # If Hyperthreading / SMT is enabled and the number of threads larger than 1
        if ($isHyperthreadingEnabled -and ($settings.numberOfThreads -gt 1)) {
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
        Write-ColorText('ERROR: Prime95 seems to have stopped with an error!') Magenta
        Write-ColorText('ERROR: At Core ' + $coreNumber + ' (CPU ' + $cpuNumberString + ')') Magenta
        Write-ColorText('ERROR MESSAGE: ' + $primeError) Magenta
        
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

        #if ($settings.FFTSize -eq 'Smallest' -or $settings.FFTSize -eq 'Small' -or $settings.FFTSize -eq 'Large') {

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

        # Try to close the stress test program process if it is still running
        Write-Verbose('Trying to close Prime95 to re-start it')
        Close-Prime95


        # If the stopOnError flag is set, stop at this point
        if ($settings.stopOnError) {
            Write-Text('')
            Write-ColorText('Stopping the testing process because the "stopOnError" flag was set.') Yellow

            # Display the results.txt file name for Prime95 for this run
            Write-Text('')
            Write-ColorText('Prime95''s results log file can be found at:') Cyan
            Write-ColorText($primeResultsPath) Cyan

            # And the name of the log file for this run
            Write-Text('')
            Write-ColorText('The path of the CoreCycler log file for this run is:') Cyan
            Write-ColorText($logfilePath) Cyan
            Write-Text('')
            
            Read-Host -Prompt 'Press Enter to exit'
            exit
        }
        

        # Try to restart Prime95 and continue with the next core
        # Don't try to restart here if $settings.restartPrimeForEachCore is set
        if (!$settings.restartPrimeForEachCore) {
            $timestamp = Get-Date -format HH:mm:ss
            Write-Text($timestamp + ' - Trying to restart Prime95')
            
            # Start Prime95 again
            Start-Prime95
        }
        
        
        # Throw an error to let the caller know there was an error
        #throw ('Prime95 seems to have stopped with an error at Core ' + $coreNumber + ' (CPU ' + $cpuNumberString + ')')
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
    
    Read-Host -Prompt 'Press Enter to exit'
    exit
}

# Clear the error variable, it may have been populated by the above calls
$Error.clear()


# Trry to get the localized counter names
try {
    $counterNameIds = Get-PerformanceCounterIDs $englishCounterNames

    $counterNames['Process']          = Get-PerformanceCounterLocalName $counterNameIds['Process']
    $counterNames['ID Process']       = Get-PerformanceCounterLocalName $counterNameIds['ID Process']
    $counterNames['% Processor Time'] = Get-PerformanceCounterLocalName $counterNameIds['% Processor Time']
    $counterNames['FullName']         = "\" + $counterNames['Process'] + "(*)\" + $counterNames['ID Process']
    $counterNames['SearchString']     = '\\' + $counterNames['ID Process'] + '$'
    $counterNames['ReplaceString']    = '\' + $counterNames['% Processor Time']

    # Examples
    # English: ID Process
    # German:  Prozesskennung
    # English: % Processor Time
    # German:  Prozessorzeit (%)
}
catch {
    Write-Host 'FATAL ERROR: Could not get the localized Performance Process Counter name!' -ForegroundColor Red
    Write-Host
    Write-Host 'You may need to re-enable the Performance Process Counter (PerfProc).' -ForegroundColor Red
    Write-Host 'Please see the "Troubleshooting / FAQ" section in the readme.txt.' -ForegroundColor Red
    Write-Host

    $Error

    Read-Host -Prompt 'Press Enter to exit'
    exit
}


# Try to access the Performance Process Counter
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

    Read-Host -Prompt 'Press Enter to exit'
    exit
}



# Make the external code definitions available to PowerShell
Add-Type -TypeDefinition $GetWindowDefinition
Add-Type -TypeDefinition $CloseWindowDefinition


# The Prime95 process
$process = Get-Process $processName -ErrorAction SilentlyContinue
$Error.Clear()


# The expected CPU usage for the running Prime95 process
# The selected number of threads should be at 100%, so e.g. for 1 thread out of 24 threads this is 100/24*1= 4.17%
# Used to determine if Prime95 is still running or has thrown an error
$expectedUsage = [Math]::Round(100 / $numLogicalCores * $settings.numberOfThreads, 2)


# Store all the cores that have thrown an error in Prime95
# These cores will be skipped on the next iteration
[Int[]] $coresWithError = @()


# Count the number of errors for each cores if the skipOnError setting is 0
$coresWithErrorsCounter = @{}

for ($i = 0; $i -lt $numPhysCores; $i++) {
    $coresWithErrorsCounter[$i] = 0
}


# Check the CPU usage each x seconds
# Note: 15 seconds may fail if there was an error and Prime95 was restarted -> false positive
#       20 seconds may work fine, but it's probably best to wait for longer on the first check
$cpuUsageCheckInterval = 10


# Calculate the amount of interval checks for the CPU power check
$cpuCheckIterations = [Math]::Floor($settings.runtimePerCore / $cpuUsageCheckInterval)
$runtimeRemaining   = $settings.runtimePerCore - ($cpuCheckIterations * $cpuUsageCheckInterval)


# The Prime95 CPU settings for the various test modes
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
        CpuSupportsAVX  = $settings.customCpuSupportsAVX
        CpuSupportsAVX2 = $settings.customCpuSupportsAVX2
        CpuSupportsFMA3 = $settings.customCpuSupportsFMA3
    }
}


# The various FFT sizes
# Used to determine where an error likely happened
# Note: These are different depending on the selected mode (SSE, AVX, AVX2)!
# SSE:  4, 5, 6, 8, 10, 12, 14, 16,     20,     24,     28,     32,         40, 48, 56,     64, 72, 80, 84, 96,      112,      128,      144, 160,      192,      224, 240, 256,      288, 320, 336, 384, 400, 448, 480, 512, 560, 576, 640, 672, 720, 768, 800,      896, 960, 1024, 1120, 1152, 1200, 1280, 1344, 1440, 1536, 1600, 1680, 1728, 1792, 1920, 2048, 2240, 2304, 2400, 2560, 2688, 2800, 2880, 3072, 3200, 3360, 3456, 3584, 3840,       4096, 4480, 4608, 4800, 5120, 5376, 5600, 5760, 6144, 6400, 6720, 6912, 7168, 7680, 8000,       8192, 8960, 9216, 9600, 10240, 10752, 11200, 11520, 12288, 12800, 13440, 13824, 14336, 15360, 16000, 16384, 17920, 18432, 19200, 20480, 20480, 21504, 22400, 23040, 24576, 25600, 26880, 27648, 28672, 30720, 32000, 327688192, 8960, 9216, 9600, 10240, 10752, 11200, 11520, 12288, 12800, 13440, 13824, 14336, 15360, 16000, 16384, 17920, 18432, 19200, 20480, 20480, 21504, 22400, 23040, 24576, 25600, 26880, 27648, 28672, 30720, 32000, 32768
# AVX:  4, 5, 6, 8, 10, 12, 15, 16, 18, 20, 21, 24, 25, 28,     32, 35, 36, 40, 48, 50, 60, 64, 72, 80, 84, 96, 100, 112, 120, 128, 140, 144, 160, 168, 192, 200, 224, 240, 256,      288, 320, 336, 384, 400, 448, 480, 512, 560, 576, 640, 672, 720, 768, 800, 864, 896, 960, 1024,       1152,       1280, 1344, 1440, 1536, 1600, 1680, 1728, 1792, 1920, 2048,       2304, 2400, 2560, 2688,       2880, 3072, 3200, 3360, 3456, 3584, 3840, 4032, 4096, 4480, 4608, 4800, 5120, 5376,       5760, 6144, 6400, 6720, 6912, 7168, 7680, 8000,       8192
# AVX2: 4, 5, 6, 8, 10, 12, 15, 16, 18, 20, 21, 24, 25, 28, 30, 32, 35, 36, 40, 48, 50, 60, 64, 72, 80, 84, 96, 100, 112, 120, 128,      144, 160, 168, 192, 200, 224, 240, 256, 280, 288, 320, 336, 384, 400, 448, 480, 512, 560,      640, 672,      768, 800,      896, 960, 1024, 1120, 1152,       1280, 1344, 1440, 1536, 1600, 1680,       1792, 1920, 2048, 2240, 2304, 2400, 2560, 2688, 2800, 2880, 3072, 3200, 3360,       3584, 3840,       4096, 4480, 4608, 4800, 5120, 5376, 5600, 5760, 6144, 6400, 6720,       7168, 7680, 8000, 8064, 8192
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
        # Note: Unfortunately Prime95 seems to randomize the order for larger FFT sizes
        448, 480, 512, 560, 576, 640, 672, 720, 768, 800, 896, 960, 1024, 1120, 1152, 1200, 1280, 1344, 1440, 1536, 1600, 1680, 1728, 1792, 1920,
        2048, 2240, 2304, 2400, 2560, 2688, 2800, 2880, 3072, 3200, 3360, 3456, 3584, 3840, 4096, 4480, 4608, 4800, 5120, 5376, 5600, 5760, 6144,
        6400, 6720, 6912, 7168, 7680, 8000, 8192

        # Not used in Prime95 presets
        # Now custom labeled "Huge"
        # 32768 seems to be the maximum FFT size possible for SSE
        # Note: Unfortunately Prime95 seems to randomize the order for larger FFT sizes
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
        # Note: Unfortunately Prime95 seems to randomize the order for larger FFT sizes
        448, 480, 512, 560, 576, 640, 672, 720, 768, 800, 864, 896, 960, 1024, 1152, 1280, 1344, 1440, 1536, 1600, 1680, 1728, 1792, 1920,
        2048, 2304, 2400, 2560, 2688, 2880, 3072, 3200, 3360, 3456, 3584, 3840, 4032, 4096, 4480, 4608, 4800, 5120, 5376, 5760, 6144,
        6400, 6720, 6912, 7168, 7680, 8000, 8192

        # Not used in Prime95 presets
        # Now custom labeled "Huge"
        # 32768 seems to be the maximum FFT size possible for AVX
        # Note: Unfortunately Prime95 seems to randomize the order for larger FFT sizes
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
        # Note: Unfortunately Prime95 seems to randomize the order for larger FFT sizes
        448, 480, 512, 560, 640, 672, 768, 800, 896, 960, 1024, 1120, 1152, 1280, 1344, 1440, 1536, 1600, 1680, 1792, 1920,
        2048, 2240, 2304, 2400, 2560, 2688, 2800, 2880, 3072, 3200, 3360, 3584, 3840, 4096, 4480, 4608, 4800, 5120, 5376, 5600, 5760, 6144,
        6400, 6720, 7168, 7680, 8000, 8064, 8192

        # Not used in Prime95 presets
        # Now custom labeled "Huge"
        # 51200 seems to be the maximum FFT size possible for AVX2
        # Note: Unfortunately Prime95 seems to randomize the order for larger FFT sizes
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
    $minFFTSize = [Int]$settings.customMinTortureFFT
    $maxFFTSize = [Int]$settings.customMaxTortureFFT
}
else {
    $minFFTSize = $FFTMinMaxValues[$settings.mode][$settings.FFTSize].Min
    $maxFFTSize = $FFTMinMaxValues[$settings.mode][$settings.FFTSize].Max
}


# Get the test mode, even if $settings.mode is set to CUSTOM
$cpuTestMode = $settings.mode

# If we're in CUSTOM mode, try to determine which setting preset it is
if ($settings.mode -eq 'CUSTOM') {
    $cpuTestMode = 'SSE'

    if ($settings.customCpuSupportsAVX -eq 1) {
        if ($settings.customCpuSupportsAVX2 -eq 1 -and $settings.customCpuSupportsFMA3 -eq 1) {
            $cpuTestMode = 'AVX2'
        }
        else {
            $cpuTestMode = 'AVX'
        }
    }
}


# The Prime95 results.txt file name for this run
$primeResultsName = 'results_CoreCycler_' + $curDateTime + '_' + $settings.mode + '_FFT_' + $minFFTSize + 'K-' + $maxFFTSize + 'K.txt'
$primeResultsPath = $processPath + $primeResultsName



# Close all existing instances of Prime95 and start a new one with our config
if ($process) {
    Write-Verbose('There already exists an instance of Prime95, trying to close it')
    Write-Verbose('ID: ' + $process.Id + ' - ProcessName: ' + $process.ProcessName)

    Close-Prime95
}

# Create the config file
Initialize-Prime95 $settings.mode

# Start Prime95
Start-Prime95


# Get the current datetime
$timestamp = Get-Date -format u


# Start messages
Write-ColorText('---------------------------------------------------------------------------') Green
Write-ColorText('----------- CoreCycler v' + $version + ' started at ' + $timestamp + ' -----------') Green
Write-ColorText('---------------------------------------------------------------------------') Green

# Verbosity
if ($settings.verbosityMode -eq 1) {
    Write-ColorText('Verbose mode is ENABLED: Writing to log file') Cyan
}
elseif ($settings.verbosityMode -eq 2) {
    Write-ColorText('Verbose mode is ENABLED: Displaying in terminal') Cyan
}

# Display some initial information
Write-ColorText('Selected test mode: ....... ' + $settings.mode) Cyan
Write-ColorText('Logical/Physical cores: ... ' + $numLogicalCores + ' logical / ' + $numPhysCores + ' physical cores') Cyan
Write-ColorText('Hyperthreading / SMT is: .. ' + ($(if ($isHyperthreadingEnabled) { 'ON' } else { 'OFF' }))) Cyan
Write-ColorText('Selected number of threads: ' + $settings.numberOfThreads) Cyan
Write-ColorText('Runtime per core: ......... ' + (Get-FormattedRuntimePerCoreString $settings.runtimePerCore)) Cyan
Write-ColorText('Number of iterations: ..... ' + $settings.maxIterations) Cyan

# Print a message if we're ignoring certain cores
if ($settings.coresToIgnore.Length -gt 0) {
    $settings.coresToIgnoreString = (($settings.coresToIgnore | sort) -join ', ')
    Write-ColorText('Ignored cores: ............ ' + $settings.coresToIgnoreString) Cyan
}

if ($settings.mode -eq 'CUSTOM') {
    Write-ColorText('') Cyan
    Write-ColorText('---------------------------------------------------------------------------') Cyan
    Write-ColorText('Custom settings:') Cyan
    Write-ColorText('----------------') Cyan
    Write-ColorText('CpuSupportsAVX  = ' + $settings.customCpuSupportsAVX) Cyan
    Write-ColorText('CpuSupportsAVX2 = ' + $settings.customCpuSupportsAVX2) Cyan
    Write-ColorText('CpuSupportsFMA3 = ' + $settings.customCpuSupportsFMA3) Cyan
    Write-ColorText('MinTortureFFT   = ' + $settings.customMinTortureFFT) Cyan
    Write-ColorText('MaxTortureFFT   = ' + $settings.customMaxTortureFFT) Cyan
    Write-ColorText('TortureMem      = ' + $settings.customTortureMem) Cyan
    Write-ColorText('TortureTime     = ' + $settings.customTortureTime) Cyan
}
else {
    Write-ColorText('Selected FFT size: ........ ' + $settings.FFTSize + ' (' + $minFFTSize + 'K - ' + $maxFFTSize + 'K)') Cyan
}

Write-ColorText('---------------------------------------------------------------------------') Cyan

# Display the results.txt file name for Prime95 for this run
Write-ColorText('Prime95''s results are being stored in:') Cyan
Write-ColorText($primeResultsPath) Cyan

# And the name of the log file for this run
Write-ColorText('') Cyan
Write-ColorText('The path of the CoreCycler log file is:') Cyan
Write-ColorText($logfilePath) Cyan
Write-ColorText('---------------------------------------------------------------------------') Cyan

# Try to get the affinity of the Prime95 process. If not found, abort
try {
    $null = $process.ProcessorAffinity

    Write-Verbose('The current affinity of the process: ' + $process.ProcessorAffinity)
}
catch {
    Exit-WithFatalError('Process ' + $processName + ' not found!')
}


# All the cores
$allCores = @(0..($numPhysCores-1))
$coresToTest = $allCores

# Subtract ignored cores
$coresToTest = $allCores | ? {$_ -notin $settings.coresToIgnore}


# Repeat the whole check $settings.maxIterations times
for ($iteration = 1; $iteration -le $settings.maxIterations; $iteration++) {
    $timestamp = Get-Date -format HH:mm:ss

    # Check if all of the cores have thrown an error, and if so, abort
    # Only if the skipOnError setting is set
    if ($settings.skipOnError -and $coresWithError.Length -eq ($numPhysCores - $settings.coresToIgnore.Length)) {
        # Also close the Prime95 process to not let it run unnecessarily
        Close-Prime95
        
        Write-Text($timestamp + ' - All Cores have thrown an error, aborting!')
        Read-Host -Prompt 'Press Enter to exit'
        exit
    }


    Write-ColorText('') Yellow
    Write-ColorText($timestamp + ' - Iteration ' + $iteration) Yellow
    Write-ColorText('----------------------------------') Yellow
    
    # Iterate over each core
    # Named for loop
    :coreLoop for ($coreNumber = 0; $coreNumber -lt $numPhysCores; $coreNumber++) {
        $startDateThisCore = (Get-Date)
        $endDateThisCore   = $startDateThisCore + (New-TimeSpan -Seconds $settings.runtimePerCore)
        $timestamp         = $startDateThisCore.ToString("HH:mm:ss")
        $affinity          = [Int64]0
        $cpuNumbersArray   = @()


        # Get the current CPU core(s)

        # If the number of threads is more than 1
        if ($settings.numberOfThreads -gt 1) {
            for ($currentThread = 0; $currentThread -lt $settings.numberOfThreads; $currentThread++) {
                # We don't care about Hyperthreading / SMT here, it needs to be enabled for 2 threads
                $thisCPUNumber    = ($coreNumber * 2) + $currentThread
                $cpuNumbersArray += $thisCPUNumber
                $affinity        += [Math]::Pow(2, $thisCPUNumber)
            }
        }

        # Only one thread
        else {
            # If Hyperthreading / SMT is enabled, the tested CPU number is 0, 2, 4, etc
            # Otherwise, it's the same value
            $cpuNumber        = $coreNumber * (1 + [Int]$isHyperthreadingEnabled)
            $cpuNumbersArray += $cpuNumber
            $affinity         = [Math]::Pow(2, $cpuNumber)
        }

        $cpuNumberString = (($cpuNumbersArray | sort) -join ' and ')


        # If this core is in the ignored cores array
        if ($settings.coresToIgnore -contains $coreNumber) {
            # Ignore it silently
            #Write-Text($timestamp + ' - Core ' + $coreNumber + ' (CPU ' + $cpuNumberString + ') is being ignored, skipping')
            continue
        }

        # If this core is stored in the error core array, skip it
        if ($settings.skipOnError -and $coresWithError -contains $coreNumber) {
            Write-Text($timestamp + ' - Core ' + $coreNumber + ' (CPU ' + $cpuNumberString + ') has previously thrown an error, skipping')
            continue
        }

        # If $settings.restartPrimeForEachCore is set, restart Prime95 for each core
        if ($settings.restartPrimeForEachCore -and ($iteration -gt 1 -or $coreNumber -gt $coresToTest[0])) {
            Close-Prime95

            # If the delayBetweenCycles setting is set, wait for the defined amount
            if ($settings.delayBetweenCycles -gt 0) {
                Write-Text('           Idling for ' + $settings.delayBetweenCycles + ' seconds before continuing to the next core...')

                # Also adjust the expected end time for this delay
                $endDateThisCore += New-TimeSpan -Seconds $settings.delayBetweenCycles

                Start-Sleep -Seconds $settings.delayBetweenCycles
            }

            Start-Prime95
        }
        
       
        # This core has not thrown an error yet, run the test
        $timestamp = (Get-Date).ToString("HH:mm:ss")
        Write-Text($timestamp + ' - Set to Core ' + $coreNumber + ' (CPU ' + $cpuNumberString + ')')
        
        # Set the affinity to a specific core
        try {
            Write-Verbose('Setting the affinity to ' + $affinity)

            $process.ProcessorAffinity = [System.IntPtr][Int64]$affinity
        }
        catch {
            # Apparently setting the affinity can fail on the first try, so make another attempt
            Write-Verbose('Setting the affinity has failed, trying again...')
            Start-Sleep -Milliseconds 300

            try {
                $process.ProcessorAffinity = [System.IntPtr][Int64]$affinity
            }
            catch {
                Close-Prime95
                Exit-WithFatalError('Could not set the affinity to Core ' + $coreNumber + ' (CPU ' + $cpuNumberString + ')!')                
            }
        }

        Write-Verbose('Successfully set the affinity to ' + $affinity)
        
        # If this core is stored in the error core array and the skipOnError setting is not set, display the amount of errors
        if (!$settings.skipOnError -and $coresWithError -contains $coreNumber) {
            $text  = '           Note: This core has previously thrown ' + $coresWithErrorsCounter[$coreNumber] + ' error'
            $text += $(if ($coresWithErrorsCounter[$coreNumber] -gt 1) {'s'})

            Write-Text($text)
        }

        Write-Text('           Running for ' + (Get-FormattedRuntimePerCoreString $settings.runtimePerCore) + '...')


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
                Test-ProcessUsage $coreNumber
            }
            
            # On error, the Prime95 process is not running anymore, so skip this core
            catch {
                Write-Verbose('There has been some error in Test-ProcessUsage, checking')

                if ($Error -and $Error[0].ToString() -eq '999') {
                    Write-Verbose('Prime95 seems to have stopped with an error at Core ' + $coreNumber + ' (CPU ' + $cpuNumberString + ')')
                    continue coreLoop
                }
                else {
                    Write-ColorText('FATAL ERROR:') Red
                    Write-ErrorText $Error
                    Exit-WithFatalError
                }
            }
        }
        
        # Wait for the remaining runtime
        Start-Sleep -Seconds $runtimeRemaining
        
        # One last check
        try {
            Test-ProcessUsage $coreNumber
        }
        
        # On error, the Prime95 process is not running anymore, so skip this core
        catch {
            Write-Verbose('There has been some error in Test-ProcessUsage, checking')

            if ($Error -and $Error[0] -eq '999') {
                Write-Verbose('Prime95 seems to have stopped with an error at Core ' + $coreNumber + ' (CPU ' + $cpuNumberString + ')')
                continue
            }
            else {
                Write-ColorText('FATAL ERROR:') Red
                Write-ErrorText $Error
                Exit-WithFatalError
            }
        }

        $timestamp = (Get-Date).ToString("HH:mm:ss")
        Write-Text($timestamp + ' - Completed the test on Core ' + $coreNumber + ' (CPU ' + $cpuNumberString + ')')
    }
    
    
    # Print out the cores that have thrown an error so far
    if ($coresWithError.Length -gt 0) {
        if ($settings.skipOnError) {
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
Close-Prime95
Read-Host -Prompt 'Press Enter to exit'