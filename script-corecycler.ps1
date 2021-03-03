<#
.AUTHOR
	sp00n
.VERSION
	0.55
.DESCRIPTION
	Sets the affinity of the Prime95 process to one core only and cycles through
	all the cores
.LINK
	https://github.com/sp00n/corecycler
.NOTE
	Please excuse my amateurish code in this file, it's my first attempt at writing in PowerShell ._.
#>



# Default config settings
# Change the various settings in the config.ini file

$defaults = @{

	# The mode of the test:
	# 'SSE':    lightest load on the processor, lowest temperatures, highest boost clock
	# 'AVX':    medium load on the processor, medium temperatures, medium boost clock
	# 'AVX2':   heaviest on the processor, highest temperatures, lowest boost clock
	# 'CUSTOM': you can define your own settings (see further below for setting the values)
	mode = 'SSE';


	# Set the runtime per core in seconds
	#  360 = 6 minutes
	#  600 = 10 minutes
	#  900 = 15 minutes
	# 1200 = 20 minutes
	# 1800 = 30 minutes
	# 3600 = 1 hour
	runtimePerCore = 360;


	# The number of threads to use for testing
	# You can only choose between 1 and 2
	# If Hyperthreading / SMT is disabled, this will automatically be set to 1
	# Currently there's no automatic way to determine which core has thrown an error
	# Setting this to 1 causes higher boost clock speed (due to less heat)
	# Default is 1
	# Maximum is 2
	numberOfThreads = 1;


	# The max number of iterations, 10000 is basically unlimited
	maxIterations = 10000;


	# Ignore certain cores
	# These cores will not be tested
	# The enumeration starts with a 0
	# Example: $settings.coresToIgnore = @(0, 1, 2)
	coresToIgnore = @();


	# Restart the Prime95 process for each new core test
	# So each core will have the same sequence of FFT sizes
	# The sequence of FFT sizes for Small FFTs:
	# 40, 48, 56, 64, 72, 80, 84, 96, 112, 128, 144, 160, 192, 224, 240
	# Runtime on a 5900x: 5,x minutes
	# Note: The screen never seems to turn off with this setting enabled
	restartPrimeForEachCore = 0;


	# The name of the log file
	# The $settings.mode above will be added to the name (and a .log file ending)
	logfile = 'CoreCycler';


	# Set the custom settings here for the 'CUSTOM' mode
	# Note: The automatic detection at which FFT size an error likely occurred
	#       will not work if you change the FFT sizes
	customCpuSupportsSSE  = '1';		# Needs to be set to 1 for SSE mode
	customCpuSupportsSSE2 = '1';		# Also needs to be set to 1 for SSE mode
	customCpuSupportsAVX  = '0';		# Needs to be set to 1 for AVX mode
	customCpuSupportsAVX2 = '0';		# Needs to be set to 1 for AVX2 mode
	customCpuSupportsFMA3 = '0';		# Also needs to be set to 1 for AVX2 mode on Ryzen
	customMinTortureFFT   = '36';		# The minimum FFT size to test
	customMaxTortureFFT   = '248';		# The maximum FFT size to test
	customTortureMem      = '0';		# The amount of memory to use. 0 = In-Place
	customTortureTime     = '1';		# The max amount of minutes for each FFT size
	customTortureWeak     = '1048576';	# Not sure, I haven't found much information about it
}


# Set the default settings
$settings = $defaults


# Read the config file and overwrite the settings
$userSettings = Get-Content -raw 'config.ini' | ConvertFrom-StringData

foreach ($entry in $userSettings.GetEnumerator()) {
	# Special handling for coresToIgnore
	if ($entry.Name -eq 'coresToIgnore') {
		if ($entry.Value -and ![string]::IsNullOrEmpty($entry.Value) -and ![String]::IsNullOrWhiteSpace($entry.Value)) {
			# Split the string by comma and add to the coresToIgnore entry
			$entry.Value -split ',\s*' | ForEach-Object { $settings.coresToIgnore += [Int]$_ }
		}
	}

	# Setting cannot be empty
	elseif ($entry.Value -and ![string]::IsNullOrEmpty($entry.Value) -and ![String]::IsNullOrWhiteSpace($entry.Value)) {
		$settings[$entry.Name] = $entry.Value
	}

	# If empty, just ignore and use the defaults
	else {
		
	}
}


# The full path and name of the log file
$logfilePath = $PSScriptRoot + '\' + $settings.logfile + '-' + $settings.mode + '.log'


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


# The Prime95 executable name and path
$processName = 'prime95'
$processPath = $PSScriptRoot + '\p95\'
$primePath   = $processPath + $processName


# The Prime95 results.txt file name for this run
$primeResultsName = 'results-CoreCycler-' + (Get-Date -format yyyy-MM-dd-HH-mm-ss) + '-' + $settings.mode + '.txt'
$primeResultsPath = $processPath + $primeResultsName


# The Prime95 process
$process = Get-Process $processName -ErrorAction SilentlyContinue


# Limit the number of threads to 1 - 2
$settings.numberOfThreads = [Math]::Max(1, [Math]::Min(2, $settings.numberOfThreads))
$settings.numberOfThreads = $(if ($isHyperthreadingEnabled) { $settings.numberOfThreads } else { 1 })


# The expected CPU usage for the running Prime95 process
# The selected number of threads should be at 100%, so e.g. for 1 thread out of 24 threads this is 100/24*1= 4.17%
# Used to determine if Prime95 is still running or has thrown an error
$expectedUsage = [Math]::Round(100 / $numLogicalCores * $settings.numberOfThreads, 2)


# Store all the cores that have thrown an error in Prime95
# These cores will be skipped on the next iteration
[Int[]] $coresWithError = @()


# Check the CPU usage each x seconds
$cpuUsageCheckInterval = 30


# Calculate the interval time for the CPU power check
$cpuCheckIterations = [Math]::Floor($settings.runtimePerCore / $cpuUsageCheckInterval)
$runtimeRemaining   = $settings.runtimePerCore - ($cpuCheckIterations * $cpuUsageCheckInterval)


# The small FFT sizes
# Used to determine where an error likely happened
# 40, 48, 56, 64, 72, 80, 84, 96, 112, 128, 144, 160, 192, 224, 240
$FFTSizes = @(40, 48, 56, 64, 72, 80, 84, 96, 112, 128, 144, 160, 192, 224, 240)


# Add code definitions so that we can close the Prime95 window even if it's minimized
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

Add-Type -TypeDefinition $GetWindowDefinition -Language CSharpVersion3


$CloseWindowDefinition = @'
	using System;
	using System.Runtime.InteropServices;
	
	public static class Win32 {
		public static uint WM_CLOSE = 0x10;

		[DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = false)]
		public static extern IntPtr SendMessage(IntPtr hWnd, UInt32 Msg, IntPtr wParam, IntPtr lParam);
	}
'@

Add-Type -TypeDefinition $CloseWindowDefinition



<##
 # Write a message to the screen and to the log file
 # .PARAM void It merges all parameters into a single line
 # .RETURN void
 #>
function Write-Text {
	$args -join "" | Tee-Object -filepath $logfilePath -append
}


<##
 # Get the main window handler for the Prime95 process
 # Even if minimized to the tray
 # .PARAM void
 # .RETURN void
 #>
function Get-Prime95-WindowHandler {
	# 'Prime95 - Self-Test': worker running
	# 'Prime95': worker not running
	$windowObj = [Api.Apidef]::GetWindows() | Where-Object { $_.WinTitle -eq 'Prime95 - Self-Test' -or $_.WinTitle -eq 'Prime95' }
	
	# Override the global script variables
	$Script:processWindowHandler = $windowObj.MainWindowHandle
	$Script:processId = $windowObj.ProcessId
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

	# Create the local.txt and overwrite if necessary
	$null = New-Item $configFile1 -ItemType File -Force

	Set-Content $configFile1 'RollingAverageIsFromV27=1'
	
	# Limit the load to the selected number of threads
	Add-Content $configFile1 ('NumCPUs=1')
	Add-Content $configFile1 ('CoresPerTest=1')
	Add-Content $configFile1 ('CpuNumHyperthreads=' + $settings.numberOfThreads)
	Add-Content $configFile1 ('WorkerThreads=' + $settings.numberOfThreads)
	
	

	# Here you can define your own settings
	if ($configType -eq "CUSTOM") {
		# For Ryzen processors, FMA3 needs to be enabled as well as AVX2 to use the AVX2 mode in Prime95
		Add-Content $configFile1 ('CpuSupportsSSE='  + $settings.customCpuSupportsSSE)
		Add-Content $configFile1 ('CpuSupportsSSE2=' + $settings.customCpuSupportsSSE2)
		Add-Content $configFile1 ('CpuSupportsAVX='  + $settings.customCpuSupportsAVX)
		Add-Content $configFile1 ('CpuSupportsAVX2=' + $settings.customCpuSupportsAVX2)
		Add-Content $configFile1 ('CpuSupportsFMA3=' + $settings.customCpuSupportsFMA3)
	}
	
	# The various default test modes (see the description for $settings.mode for an explanation)
	elseif ($configType -eq "SSE") {
		Add-Content $configFile1 'CpuSupportsSSE=1'
		Add-Content $configFile1 'CpuSupportsSSE2=1'
		Add-Content $configFile1 'CpuSupportsAVX=0'
		Add-Content $configFile1 'CpuSupportsAVX2=0'
		Add-Content $configFile1 'CpuSupportsFMA3=0'
	}
	elseif ($configType -eq "AVX") {
		Add-Content $configFile1 'CpuSupportsSSE=1'
		Add-Content $configFile1 'CpuSupportsSSE2=1'
		Add-Content $configFile1 'CpuSupportsAVX=1'
		Add-Content $configFile1 'CpuSupportsAVX2=0'
		Add-Content $configFile1 'CpuSupportsFMA3=0'
	}
	elseif ($configType -eq "AVX2") {
		Add-Content $configFile1 'CpuSupportsSSE=1'
		Add-Content $configFile1 'CpuSupportsSSE2=1'
		Add-Content $configFile1 'CpuSupportsAVX=1'
		Add-Content $configFile1 'CpuSupportsAVX2=1'
		Add-Content $configFile1 'CpuSupportsFMA3=1'
	}
	else {
		'ERROR: Invalid mode type provided!'
		Read-Host -Prompt 'Press Enter to exit'
		exit
	}


	# Create the prime.txt and overwrite if necessary
	$null = New-Item $configFile2 -ItemType File -Force
	
	# Set the custom results.txt file name
	Set-Content $configFile2 ('results.txt=' + $primeResultsName)
	
	
	# Here you can define custom FFT sizes
	if ($configType -eq "CUSTOM") {
		Add-Content $configFile2 ('MinTortureFFT=' + $settings.customMinTortureFFT)
		Add-Content $configFile2 ('MaxTortureFFT=' + $settings.customMaxTortureFFT)
		Add-Content $configFile2 ('TortureMem='    + $settings.customTortureMem)
		Add-Content $configFile2 ('TortureTime='   + $settings.customTortureTime)
		Add-Content $configFile2 ('TortureWeak='   + $settings.customTortureWeak)
	}
	
	# Default settings
	else {
		# FFT size 36K to 248K
		# No memory testing ("In-Place")
		# 1 minute per FFT size
		Add-Content $configFile2 'MinTortureFFT=36'
		Add-Content $configFile2 'MaxTortureFFT=248'
		Add-Content $configFile2 'TortureMem=0'
		Add-Content $configFile2 'TortureTime=1'
		Add-Content $configFile2 'TortureWeak=1048576'
	}
	

	Add-Content $configFile2 'V24OptionsConverted=1'
	Add-Content $configFile2 'WorkPreference=0'
	Add-Content $configFile2 'V30OptionsConverted=1'
	Add-Content $configFile2 'WGUID_version=2'
	Add-Content $configFile2 'StressTester=1'
	Add-Content $configFile2 'UsePrimenet=0'
	Add-Content $configFile2 'ExitOnX=1'
	Add-Content $configFile2 '[PrimeNet]'
	Add-Content $configFile2 'Debug=0'
}


<##
 # Open Prime95 and set global script variables
 # .PARAM void
 # .RETURN void
 #>
function Start-Prime95 {
	# Minimized to the tray
	$Script:process = Start-Process -filepath $primePath -ArgumentList '-t' -PassThru -WindowStyle Hidden
	
	# Minized to the task bar
	#$Script:process = Start-Process -filepath $primePath -ArgumentList '-t' -PassThru -WindowStyle Minimized

	# This might be necessary to correctly read the process. Or not
	Start-Sleep -Milliseconds 500
	
	if (!$Script:process) {
		'ERROR: Could not start process ' + $processName + '!'
		Read-Host -Prompt 'Press Enter to exit'
		exit
	}

	# Get the main window handler
	# This also works for windows minimized to the tray
	Get-Prime95-WindowHandler
	
	# This is to find the exact counter path, as you might have multiple processes with the same name
	try {
		$Script:processCounterPath = ((Get-Counter "\Process(*)\ID Process" -ErrorAction SilentlyContinue).CounterSamples | ? {$_.RawValue -eq $processId}).Path
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
	# If there is no processWindowHandler id
	# Try to get it
	if (!$processWindowHandler) {
		Get-Prime95-WindowHandler
	}
	
	# If we now have a processWindowHandler, try to close the window
	if ($processWindowHandler) {
		$process = Get-Process -Id $processId -ErrorAction SilentlyContinue
		
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

	if ($process) {
		#'The process is still there, killing it'
		# Unfortunately this will leave any tray icons behind
		Stop-Process $process.Id -Force -ErrorAction SilentlyContinue
	}
}


<##
 # Check the CPU power usage and restart Prime95 if necessary
 # Throws an error if the CPU usage is too low
 # .PARAM int $coreNumber The current core being tested
 # .RETURN void
 #>
function Test-CPU-Usage {
	param (
		$coreNumber
	)
	
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

	# Get the content of the result.txt file
	$resultFileHandle = Get-Item -Path $primeResultsPath -ErrorAction SilentlyContinue

	# Does the process still exist?
	$process = Get-Process $processName -ErrorAction SilentlyContinue
	

	# The process doesn't exist anymore, immediate error
	if (!$process) {
		$primeError = 'The Prime95 process doesn''t exist anymore.'
	}


	# Check if the process is still using enough CPU process power
	if (!$primeError) {
		# Get the CPU percentage
		$processCPUPercentage = [Math]::Round(((Get-Counter ($processCounterPath -replace "\\ID Process$","\% Processor Time") -ErrorAction SilentlyContinue).CounterSamples.CookedValue) / $numLogicalCores, 2)
		
		# It doesn't use enough CPU power, we assume that this core errored out
		# Try to restart Prime95
		if ($processCPUPercentage -le $minPrimeUsage) {
			# Try to read the error from Prime95's results.txt
			# Look for an "error" in the last 3 lines
			$primeResults = $resultFileHandle | Get-Content -Tail 3 | Where-Object {$_ -like '*error*'}

			# Found the "error" string
			if ($primeResults.Length -gt 0) {
				$primeError = $primeResults
			}

			# Error string not found
			# This might have been a false alarm, wait a bit and try again
			else {
				Start-Sleep -Milliseconds 1000

				# The second check
				# Do the whole process path procedure again
				$processId = $process.Id[0]
				$processCounterPath = ((Get-Counter "\Process(*)\ID Process" -ErrorAction SilentlyContinue).CounterSamples | ? {$_.RawValue -eq $processId}).Path
				$processCPUPercentage = [Math]::Round(((Get-Counter ($processCounterPath -replace "\\ID Process$","\% Processor Time") -ErrorAction SilentlyContinue).CounterSamples.CookedValue) / $numLogicalCores, 2)

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


		# Try to close the Prime95 process if it is still running
		Close-Prime95
		
		
		# Put out an error message
		$timestamp = Get-Date -format HH:mm:ss
		Write-Text('ERROR: ' + $timestamp)
		Write-Text('ERROR: Prime95 seems to have stopped with an error!')
		Write-Text('ERROR: At Core ' + $coreNumber + ' (CPU ' + $cpuNumberString + ')')
		Write-Text('ERROR MESSAGE: ' + $primeError)
		
		# DEBUG
		# Also add the 5 last rows of the results.txt file
		#Write-Text('LAST 5 ROWS OF RESULTS.TXT:')
		#Write-Text(Get-Item -Path $primeResultsPath | Get-Content -Tail 5)
		
		# Try to determine the last run FFT size
		# This will horribly fail if the FFT sizes were changed in the custom config
		# If the result.txt doesn't exist, assume that it was on the very first iteration
		if (!$resultFileHandle) {
			$lastRunFFT = $FFTSizes[0]
		}
		
		# Get the last couple of rows and find the last passed FFT size
		else {
			$lastFiveRows = $resultFileHandle | Get-Content -Tail 5
			$lastPassedFFTArr = @($lastFiveRows | Where-Object {$_ -like '*passed*'})
			$hasMatched = $lastPassedFFTArr[$lastPassedFFTArr.Length-1] -match 'Self-test (\d+)K passed'
			$lastPassedFFT = [Int]$matches[1]	# $matches is a fixed(?) variable name for -match
			
			
			# If the last passed FFT size is the last entry of the FFT sizes, start at the beginning
			if ($lastPassedFFT -eq $FFTSizes[$FFTSizes.Length-1]) {
				$lastRunFFT = $FFTSizes[0]
			}
			else {
				$lastRunFFT = $FFTSizes[$FFTSizes.indexOf([Int]$matches[1])+1]
			}
		}
		
		# Educated guess
		if ($lastRunFFT) {
			Write-Text('ERROR: The error likely happened at FFT size ' + $lastRunFFT + 'K')
		}
		

		# Try to restart Prime95 and continue with the next core
		Write-Text('Trying to restart Prime95')
		
		
		# Start Prime95 again
		Start-Prime95
		
		
		# Throw an error to let the caller know there was an error
		throw 'Prime95 seems to have stopped with an error at Core ' + $coreNumber + ' (CPU ' + $cpuNumberString + ')'
	}
}


# Close all existing instances of Prime95 and start a new one with our config
if ($process) {
	Close-Prime95
}

# Create the config file
Initialize-Prime95 $settings.mode

# Start Prime95
Start-Prime95



# Get the current datetime
$timestamp = Get-Date -format u


# Start messages
Write-Text('------------------------------------------')
Write-Text('CoreCycler startet at ' + $timestamp)
Write-Text('------------------------------------------')

# Display the number of logical & physical cores
Write-Text('Found ' + $numLogicalCores + ' logical and ' + $numPhysCores + ' physical cores')
Write-Text('Hyperthreading / SMT is: ' + ($(if ($isHyperthreadingEnabled) { 'ON' } else { 'OFF' })))
Write-Text('Selected number of threads: ' + $settings.numberOfThreads)
Write-Text('Number of iterations: ' + $settings.maxIterations)

# And the selected mode (SSE, AVX, AVX2)
Write-Text('Selected mode: ' + $settings.mode)
Write-Text('------------------------------------------')


# Print a message if we're ignoring certain cores
if ($settings.coresToIgnore.Length -gt 0) {
	$settings.coresToIgnoreString = (($settings.coresToIgnore | sort) -join ', ')
	Write-Text('Ignored cores: ' + $settings.coresToIgnoreString)
	Write-Text('---------------' + ('-' * $settings.coresToIgnoreString.Length))
}


# Display the results.txt file name for Prime95 for this run
Write-Text('Prime95''s results are being stored in:')
Write-Text($primeResultsPath)


# Try to get the affinity of the Prime95 process. If not found, abort
try {
	Write-Text('Current affinity of process: ' + $process.ProcessorAffinity)
}
catch {
	Write-Text('ERROR: Process ' + $processName + ' not found!')
	Read-Host -Prompt 'Press Enter to exit'
	exit
}



# Repeat the whole check $settings.maxIterations times
for ($iteration = 1; $iteration -le $settings.maxIterations; $iteration++) {
	$timestamp = Get-Date -format HH:mm:ss

	# Check if all of the cores have thrown an error, and if so, abort
	if ($coresWithError.Length -eq ($numPhysCores - $settings.coresToIgnore.Length)) {
		# Also close the Prime95 process to not let it run unnecessarily
		Close-Prime95
		
		Write-Text($timestamp + ' - All Cores have thrown an error, aborting!')
		Read-Host -Prompt 'Press Enter to exit'
		exit
	}


	Write-Text('')
	Write-Text($timestamp + ' - Iteration ' + $iteration)
	Write-Text('---------------------------')
	
	# Iterate over each core
	# Named for loop
	:coreLoop for ($coreNumber = 0; $coreNumber -lt $numPhysCores; $coreNumber++) {
		$timestamp = Get-Date -format HH:mm:ss
		$affinity = 0
		$cpuNumbersArray = @()

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

		# If this core is stored in the error core array
		if ($coresWithError -contains $coreNumber) {
			Write-Text($timestamp + ' - Core ' + $coreNumber + ' (CPU ' + $cpuNumberString + ') has previously thrown an error, skipping')
			continue
		}


		# If $settings.restartPrimeForEachCore is set, restart Prime95 for each core
		# TODO: this check will not work correctly if core 0 is added to the $settings.coresToIgnore array
		if ($settings.restartPrimeForEachCore -and ($iteration -gt 1 -or $coreNumber -gt 0)) {
			Close-Prime95
			Start-Prime95
		}
		
	   
		# This core has not thrown an error yet, run the test
		Write-Text($timestamp + ' - Set to Core ' + $coreNumber + ' (CPU ' + $cpuNumberString + ')')
		
		# Set the affinity to a specific core
		try {
			$process.ProcessorAffinity = [System.IntPtr][Int]$affinity
			Write-Text('Running for ' + $settings.runtimePerCore + ' seconds...')
			
		}
		catch {
			Write-Text('ERROR: Could not set the affinity to Core ' + $coreNumber + ' (CPU ' + $cpuNumberString + ')!')
			Close-Prime95
			Read-Host -Prompt 'Press Enter to exit'
			exit
		}
		
		#Start-Sleep -Seconds $settings.runtimePerCore
		
		# Make a check each x seconds for the CPU power usage
		for ($checkNumber = 0; $checkNumber -lt $cpuCheckIterations; $checkNumber++) {
			Start-Sleep -Seconds $cpuUsageCheckInterval

			# Check if the process is still using enough CPU process power
			try {
				Test-CPU-Usage $coreNumber
			}
			
			# On error, the Prime95 process is not running anymore, so skip this core
			catch {
				continue coreLoop
			}
		
		}
		
		# Wait for the remaining runtime
		Start-Sleep -Seconds $runtimeRemaining
		
		# One last check
		try {
			Test-CPU-Usage $coreNumber
		}
		
		# On error, the Prime95 process is not running anymore, so skip this core
		catch {
			continue
		}
	}
	
	
	# Print out the cores that have thrown an error so far
	if ($coresWithError.Length -gt 0) {
		Write-Text('The following cores have thrown an error: ' + (($coresWithError | sort) -join ', '))
	}
}


# The CoreCycler has finished
$timestamp = Get-Date -format HH:mm:ss
Write-Text($timestamp + ' - CoreCycler finished')
Close-Prime95
Read-Host -Prompt 'Press Enter to exit'
