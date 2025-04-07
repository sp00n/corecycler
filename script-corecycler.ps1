<#
.AUTHOR
    sp00n
.VERSION
    0.10.0.1
.DESCRIPTION
    Sets the affinity of the selected stress test program process to only one
    core and cycles through all the cores which allows to test the stability of
    each individual core during single core loads
.LINK
    https://github.com/sp00n/corecycler
.LICENSE
    Creative Commons "CC BY-NC-SA"
    https://creativecommons.org/licenses/by-nc-sa/4.0/
    https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode
.PARAMETER CoreFromAutoMode
    If set, indicates that we are in Auto Mode and this core was the last one being tested before a reboot/crash
#>
param(
    [Parameter()][AllowEmptyString()] $CoreFromAutoMode = -1
)



# Our current version
$version = '0.10.1.0'


# This defines the strict mode
Set-StrictMode -Version 3.0


# Mimic the Win32 ERROR_SUCCESS constant
Set-Variable ERROR_SUCCESS -Option Constant -Value 0


# We want to use UTF-8 if possible when generating files, not UTF-16
$PSDefaultParameterValues['*:Encoding'] = 'utf8'


# Set the window title
$Host.UI.RawUI.WindowTitle = ('CoreCycler ' + $version + ' starting')



Write-Host('Starting CoreCycler v' + $version + '...')
Write-Host('Press CTRL+C to abort') -ForegroundColor Yellow



# Global variables
$scriptProcessId               = $PID
$parentProcessId               = (Get-CimInstance Win32_Process -Filter "ProcessId = $($PID)").ParentProcessId
$parentMainWindowHandle        = (Get-Process -Id $parentProcessId).MainWindowHandle
$parentMainWindowMenuHandle    = $null
$areWeAdmin                    = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$scriptStartDate               = Get-Date
$scriptStartDateTime           = Get-Date -Format yyyy-MM-dd_HH-mm-ss
$configsPath                   = 'configs'
$configsPathAbsolute           = $PSScriptRoot + '\' + $configsPath + '\'
$configDefaultPath             = $configsPathAbsolute + 'default.config.ini'
$configUserPath                = $PSScriptRoot + '\config.ini'
$customConfigPath              = $null
$canUseLogFile                 = $false
$logBuffer                     = [System.Collections.ArrayList]::new()
$logLevel                      = 2
$logFilePath                   = 'logs'
$logFilePathAbsolute           = $PSScriptRoot + '\' + $logFilePath + '\'
$logFileName                   = 'CoreCycler_' + $scriptStartDateTime + '.log'
$logFileFullPath               = $logFilePathAbsolute + $logFileName
$helpersPathAbsolute           = $PSScriptRoot + '\helpers\'
$scriptDriveLetter             = $PSScriptRoot[0]
$enableUpdateCheck             = $true
$updateCheckUrl                = 'https://api.github.com/repos/sp00n/corecycler/releases'
$updateCheckFile               = $PSScriptRoot + '\.updatecheck'
$updateCheckFrequency          = [Decimal] 24
$updateCheckJob                = $null
$updateCheckResult             = @{}
$showUpdateAvailableMessage    = $false
$settings                      = $null
$eventLogAvailable             = $false
$canUseWindowsEventLog         = $false
$storedWheaError               = $null
$selectedStressTestProgram     = $null
$useAutomaticRuntimePerCore    = $false
$consoleMode                   = $null
$windowProcess                 = $null
$windowProcessId               = $null
$windowProcessMainWindowHandle = $null
$stressTestProcess             = $null
$stressTestProcessId           = $null
$stressTestThreads             = @()
$stressTestThreadIds           = @()
$processCounterPathId          = $null
$processCounterPathTime        = $null
$currentlyTestedCore           = $null
$coresWithError                = @()
$coresWithErrorsCounter        = @{}
$numCoresWithError             = 0
$coresWithWheaError            = @()
$coresWithWheaErrorsCounter    = @{}
$numCoresWithWheaError         = 0
$errorCollector                = @{}
$stressTestLogFileName         = $null
$stressTestLogFilePath         = $null
$prime95CPUSettings            = $null
$FFTSizes                      = $null
$FFTMinMaxValues               = $null
$minFFTSize                    = $null
$maxFFTSize                    = $null
$fftSubarray                   = $null
$lastFilePosition              = 0
$lineCounter                   = 0
$newLogEntries                 = [System.Collections.ArrayList]::new()
$allLogEntries                 = [System.Collections.ArrayList]::new()
$allFFTLogEntries              = [System.Collections.ArrayList]::new()
$allTestLogEntries             = [System.Collections.ArrayList]::new()
$cpuTestMode                   = $null
$coreTestOrderMode             = $null
$coreTestOrderCustom           = [System.Collections.ArrayList]::new()
$scriptExit                    = $false
$fatalError                    = $false
$previousFileSize              = $null
$previousPassedFFTSize         = $null
$previousPassedFFTEntry        = $null
$previousPassedTest            = $null
$previousPassedTestEntry       = $null
$isPrime95                     = $false
$isAida64                      = $false
$isYCruncher                   = $false
$isYCruncherOld                = $false
$isYCruncherWithLogging        = $false
$isLinpack                     = $false
$showPrime95NewWarning         = $false
$cpuCheckIterations            = 0
$runtimeRemaining              = 0
$runtimeRemainingMax           = 0
$startedIterations             = 0
$completedIterations           = 0
$numTestedCores                = 0
$testedCoresArray              = @{}
$numberOfStartedTests          = 0


# Processor and system related variables
$freeMemory                  = 0
$processor                   = $null
$isIntelProcessor            = $false
$numLogicalCores             = 0
$numPhysCores                = 0
$numProcessorGroups          = 1
$numCpusInLastProcessorGroup = 0
$isHyperthreadingEnabled     = $false
$hasAsymmetricCoreThreads    = $false
$hasMoreThan64Cores          = $false
$coresInfo                   = @{}
$coresWithTwoThreads         = [System.Collections.ArrayList]::new()
$coresWithOneThread          = [System.Collections.ArrayList]::new()


# Automatic Test Mode variables
$CoreFromAutoMode                        = $(if (![String]::IsNullOrWhiteSpace($CoreFromAutoMode)) { [Int] $CoreFromAutoMode } else { -1 })
$useAutomaticTestMode                    = $false
$useAutomaticTestModeWithResume          = $false
$setVoltageOnlyForTestedCore             = $false
$useCurveOptimizer                       = $false
$useIntelVoltageAdjustment               = $false
$limitForCoValues                        = 50
$defaultVoltageIncrementValues           = @{ 'AMD' = 1; 'INTEL' = 5 }
$voltageStartingValues                   = @()
$voltageCurrentValues                    = @()
$coresWithIncreasedVoltageValue          = [System.Collections.ArrayList]::new()
$coresWithErrorAndMaxVoltageValue        = [System.Collections.ArrayList]::new()
$numCoresWithIncreasedVoltageValue       = 0
$numCoresWithErrorAndMaxVoltageValue     = 0
$apicIdTool                              = $PSScriptRoot + '\tools\APICID.exe'
$pboCliTool                              = $PSScriptRoot + '\tools\ryzen-smu-cli\ryzen-smu-cli.exe'
$intelCliTool                            = $PSScriptRoot + '\tools\IntelVoltageControl\IntelVoltageControl.exe'
$autoModeFile                            = $PSScriptRoot + '\.automode'
$autoModeFileTemp                        = $PSScriptRoot + '\.automode-temp'
$autoModeStartupScriptFile               = $PSScriptRoot + '\helpers\automode-startup-script.ps1'
$autoModeTaskName                        = 'CoreCycler AutoMode Startup Task'
$autoModeTaskPath                        = '\CoreCycler\'
$autoModeTaskDescription                 = 'CoreCycler Automatic Test Mode Startup Script'


# Parameters that are controllable by debug settings
$debugSettingsActive                                   = $false
$disableCpuUtilizationCheckDefault                     = 0
$useWindowsPerformanceCountersForCpuUtilizationDefault = 0
$enableCpuFrequencyCheckDefault                        = 0
$tickIntervalDefault                                   = 10
$delayFirstErrorCheckDefault                           = 0
$stressTestProgramPriorityDefault                      = 'Normal'
$stressTestProgramWindowToForegroundDefault            = 0
$suspensionTimeDefault                                 = 1000
$modeToUseForSuspensionDefault                         = 'Threads'


$disableCpuUtilizationCheck                            = $disableCpuUtilizationCheckDefault
$useWindowsPerformanceCountersForCpuUtilization        = $useWindowsPerformanceCountersForCpuUtilizationDefault
$enableCpuFrequencyCheck                               = $enableCpuFrequencyCheckDefault
$tickInterval                                          = $tickIntervalDefault
$delayFirstErrorCheck                                  = $delayFirstErrorCheckDefault
$stressTestProgramPriority                             = $stressTestProgramPriorityDefault
$stressTestProgramWindowToForeground                   = $stressTestProgramWindowToForegroundDefault
$suspensionTime                                        = $suspensionTimeDefault
$modeToUseForSuspension                                = $modeToUseForSuspensionDefault


$enablePerformanceCounters                             = $false
$showNoteForDisableCpuUtilization                      = $false
$canUseFlushToDisk                                     = $false



# The default settings for the config.ini (resp. default.config.ini)
$DEFAULT_SETTINGS_STRING = @"
# Config file for CoreCycler
# You can always find the default config file in configs\default.config.ini as a reference




# General settings
[General]

# Use a predefined config file instead of this one
# If this value is set, it will use the content from the file provided, overwriting all settings further below
# (which means that if you use this setting, you can safely remove all other settings in the "main" config.ini file)
# If this value is empty or invalid, the other settings from this file will apply
#
# It's useful for quickly switching between various configs, and you can find some predefined config files in the "configs" directory
# The setting uses a relative path from the location where this file is located in
# Example:
# useConfigFile = configs\quick-initial-test.yCruncher.config.ini
#
# Default: (empty)
useConfigFile =


# The program to perform the actual stress test
# The following programs are available:
# - PRIME95
# - AIDA64
# - YCRUNCHER
# - YCRUNCHER_OLD
# - LINPACK
# You can change the test mode and options for each stress test program in the respective [section] further down
# Note: For AIDA64, you need to manually download and extract the portable ENGINEER version and put it
#       in the /test_programs/aida64/ folder
#       AIDA64 is somewhat sketchy as well
# Note: There are two versions of y-cruncher included, which you can select with either "YCRUNCHER" or "YCRUNCHER_OLD"
#       The "old" version uses the binaries and test algorithms that were available before version 0.8 of y-cruncher
#       See the comments in the [yCruncher] section for a more detailed description
#
# Default: PRIME95
stressTestProgram = PRIME95


# Set the runtime per core
# You can define a specific runtime per core, by entering a numeric value in seconds,
# or use 'h' for hours, 'm' for minutes and 's' for seconds
# Examples: 360 = 360 seconds
#           1h4m = 1 hour, 4 minutes
#           1.5m = 1.5 minutes = 90 seconds
#
# Automatic runtime:
# You can also set it to "auto", in which case it will perform one "full" run for each core
# For Prime95, it will wait until all of the FFT sizes in the selected preset have been tested and
# will then continues to the next core and start again
# For y-cruncher the "auto" setting will wait until all selected tests have been finished for a core
# and will then continue to the next core
# If logging has been disabled for y-cruncher, it will fall back to 10 minutes per core
# For Aida64 the "auto" setting will default to 10 minutes per core
#
# Below are some examples of the runtime for one iteration of Prime95 for the various tests on my 5900X with one thread
# The first iteration is also usually the fastest one
# Selecting two threads usually takes *much* longer than one thread for one iteration in Prime95
# - Prime95 "Smallest":     4K to   21K - [SSE] ~3-4 Minutes   <|> [AVX] ~8-9 Minutes    <|> [AVX2] ~8-10 Minutes
# - Prime95 "Small":       36K to  248K - [SSE] ~4-6 Minutes   <|> [AVX] ~14-19 Minutes  <|> [AVX2] ~14-19 Minutes
# - Prime95 "Large":      426K to 8192K - [SSE] ~18-22 Minutes <|> [AVX] ~37-44 Minutes  <|> [AVX2] ~38-51 Minutes
# - Prime95 "Huge":      8960K to   MAX - [SSE] ~13-19 Minutes <|> [AVX] ~27-40 Minutes  <|> [AVX2] ~33-51 Minutes
# - Prime95 "All":          4K to   MAX - [SSE] ~40-65 Minutes <|> [AVX] ~92-131 Minutes <|> [AVX2] ~102-159 Minutes
# - Prime95 "Moderate":  1344K to 4096K - [SSE] ~7-15 Minutes  <|> [AVX] ~17-30 Minutes  <|> [AVX2] ~17-33 Minutes
# - Prime95 "Heavy":        4K to 1344K - [SSE] ~15-28 Minutes <|> [AVX] ~43-68 Minutes  <|> [AVX2] ~47-73 Minutes
# - Prime95 "HeavyShort":   4K to  160K - [SSE] ~6-8 Minutes   <|> [AVX] ~22-24 Minutes  <|> [AVX2] ~23-25 Minutes
#
# Default: 6m
runtimePerCore = 6m


# Periodically suspend the stress test program
# This can simulate load changes / switches to idle and back
# Setting this to 1 will periodically suspend the stress test program, wait for a bit, and then resume it
# You should see the CPU load and clock speed drop significantly while the program is suspended and rise back up again
# Note: This will increase the runtime of the various stress tests as seen in the "runtimePerCore" setting by roughly 10%
#
# Default: 1
suspendPeriodically = 1


# The test order of the cores
# Available modes:
# Default:    On CPUs with more than 8 physical cores: 'Alternate'. Otherwise 'Random'
# Alternate:  Alternate between the 1st core on CCD1, then 1st on CCD2, then 2nd on CCD1, then 2nd on CCD2, etc.
#             This should distribute the heat more evenly and possibly allow for higher clocks on CPUs with 2 CCDs
# Random:     A random order
# Sequential: Cycle through the cores in numerical order
#
# You can also define your own testing order by entering a list of comma separated values.
# The list will be processed as provided, which means you can test the same core multiple times per iteration.
# Do note however that the "coresToIgnore" setting still takes precedence over any core listed here.
# The enumeration of cores starts with 0
# Example: 5, 4, 0, 5, 5, 7, 2
#
# Default: Default
coreTestOrder = Default


# Skip a core that has thrown an error in the following iterations
# If set to 0, this will test a core in the next iterations even if has thrown an error before
#
# Default: 1
skipCoreOnError = 1


# Stop the whole testing process if an error occurred
# If set to 0 (default), the stress test programm will be restarted when an error
# occurs and the core that caused the error will be skipped in the next iteration
#
# Default: 0
stopOnError = 0


# The number of threads to use for testing
# You can only choose between 1 and 2
# If Hyperthreading / SMT is disabled, this will automatically be set to 1
# Currently there's no automatic way to determine which core has thrown an error
# Setting this to 1 causes higher boost clock speed (due to less heat)
#
# Default: 1
# Maximum: 2
numberOfThreads = 1


# Use only one thread for load generation, but assign this thread to both virtual (logical) cores
# This way the Windows Scheduler or the internal CPU scheduler will choose which of both virtual CPU is used
# This may lead to additional stress situation otherwise not possible
# This setting has no effect if Hyperthreading / SMT is disabled or if numberOfThreads = 2
#
# Default: 0
assignBothVirtualCoresForSingleThread = 0


# The max number of iterations
# High values are basically unlimited (good for testing over night)
#
# Default: 10000
maxIterations = 10000


# Ignore certain cores
# Comma separated list of cores that will not be tested
# The enumeration of cores starts with 0
#
# Example: coresToIgnore = 0, 1, 2
# Default: (empty)
coresToIgnore =


# Restart the stress test process when a new core is selected
# This means each core will perform the same sequence of tests during the stress test
# This setting is best combined with runtimePerCore = auto
# Note: The monitor doesn't seem to turn off when this setting is enabled
#
# Important note:
# One disadvantage of this setting is that it has the potential to limit the amount of tests that the stress test program
# can run.
# In Prime95 for example, each FFT size will run for roughly 1 minute (except for very small ones), so if you want to make
# sure that Prime95 runs all of the available FFT sizes for a setting, you'll have to extend the "runtimePerCore" setting
# from the default value to something higher.
# For example the "Huge"/SSE preset has 19 FFT entries, and tests on my 5900X showed that it roughly takes 13-19 Minutes
# until all FFT sizes have been tested. The "Large"/SSE seems to take between 18 and 22 Minutes.
# I've included the measured times in the comment for the "runtimePerCore" setting above.
# This is why setting runtimePerCore = auto is beneficial when using this setting, to make sure every test is performed
# for every core.
#
# If this setting is disabled, a new core will very likely start with a different test / FFT size than the previous one.
# For longer testing periods (e.g. over night), the tested FFT sizes / algorithms will even out eventually, but if you
# want to make sure that each core is tested in exactly the same way, you should enable this setting.
#
# Default: 0
restartTestProgramForEachCore = 0


# Set a delay between the cores
# If the "restartTestProgramForEachCore" flag is set, this setting will define the amount of seconds between the end of
# the run of one core and the start of another
# If "restartTestProgramForEachCore" is 0, this setting has no effect
# Using this setting may help your CPU to cool down a little between cores, which could result in slightly higher
# core clocks at the start of the test (which could help in identifying instabilities)
#
# Default: 15
delayBetweenCores = 15


# Beep on a core error
# Play a beep when a core has thrown an error
#
# Default: 1
beepOnError = 1


# Flash on a core error
# Flash the window/icon in the taskbar when a core has thrown an error
#
# Default: 1
flashOnError = 1


# Check for WHEA errors
# If this is enabled, CoreCycler will periodicall check the Windows Event Log for WHEA errors
# These WHEA errors do not necessarily cause or show up together with a stress test error, but are indicative
# of an unstable overclock/undervolt
# A stable system should not produce any WHEA errors/warnings
#
# Default: 1
lookForWheaErrors = 1


# Treat a WHEA Warning Event Log entry as an error
# If this is enabled, a WHEA warning (Event Id 19, "corrected hardware error") will be treated as a "real" error
# The testing on the core will be stopped and continued on the next one
# However only if the APIC ID from the WHEA message matches the core that was currently tested, otherwise
# only a warning will be displayed
#
# Default: 1
treatWheaWarningAsError = 1




# Prime95 specific settings
[Prime95]

# The test modes for Prime95
# SSE       Lightest load on the processor, lowest temperatures, highest boost clock
# AVX       Medium load on the processor, medium temperatures, medium boost clock
# AVX2      Heavy load on the processor, highest temperatures, lowest boost clock
# AVX512    Only available for certain CPUs (Ryzen 7000, some Intel Alder Lake, etc)
# CUSTOM    You can define your own settings for Prime. See the "customs" section further below
#
# Default: SSE
mode = SSE


# The FFT size preset to test for Prime95
# These are basically the presets as present in Prime95, plus an additional few
# Note: If "mode" is set to "CUSTOM", this setting will be ignored
# Smallest         4K to   21K - Prime95 preset text: "tests L1/L2 caches, high power/heat/CPU stress"
# Small           36K to  248K - Prime95 preset text: "tests L1/L2/L3 caches, maximum power/heat/CPU stress"
# Large          426K to 8192K - Prime95 preset text: "stresses memory controller and RAM" (although dedicated memory stress testing is disabled here by default!)
# Huge          8960K to   MAX - Anything beginning at 8960K up to the highest FFT size (32768K for SSE/AVX, 51200K for AVX2, 65536K for AVX512)
# All              4K to   MAX - 4K to up to the highest FFT size (32768K for SSE/AVX, 51200K for AVX2, 65536K for AVX512)
# Moderate      1344K to 4096K - special preset, recommended in the "Curve Optimizer Guide Ryzen 5000"
# Heavy            4K to 1344K - special preset, recommended in the "Curve Optimizer Guide Ryzen 5000"
# HeavyShort       4K to  160K - special preset, recommended in the "Curve Optimizer Guide Ryzen 5000"
#
# You can also define you own range by entering two FFT sizes joined by a hyphen, e.g 36-1344
#
# Default: Huge
FFTSize = Huge




# y-cruncher specific settings
# These apply to both "YCRUNCHER" and "YCRUNCHER_OLD"
[yCruncher]

# The test modes for y-cruncher
# y-cruncher offer various test modes (binaries/algorithms), that require different instruction sets to be available
# See the \test_programs\y-cruncher\Binaries\Tuning.txt file for a detailed explanation
#
# Test Mode Name       Automatic Selection For             Required Instruction Set
# --------------       -----------------------             ------------------------
# "04-P4P"             Intel Pentium 4 Prescott            SSE, SSE2, SSE3
# "05-A64 ~ Kasumi"    AMD Athlon 64                       x64, SSE, SSE2, SSE3
# "08-NHM ~ Ushio"     Intel Nehalem                       x64, SSE, SSE2, SSE3, SSSE3, SSE4.1
# "11-SNB ~ Hina"      Intel Sandy Bridge                  x64, SSE, SSE2, SSE3, SSSE3, SSE4.1, SSE4.2, AVX
# "12-BD2 ~ Miyu"      AMD Piledriver                      x64, SSE, SSE2, SSE3, SSSE3, SSE4.1, SSE4.2, AVX, ABM, FMA3
# "13-HSW ~ Airi"      Intel Haswell                       x64, ABM, BMI1, BMI2, SSE, SSE2, SSE3, SSSE3, SSE4.1, SSE4.2, AVX, FMA3, AVX2
# "14-BDW ~ Kurumi"    Intel Broadwell                     x64, ABM, BMI1, BMI2, ADX, SSE, SSE2, SSE3, SSSE3, SSE4.1, SSE4.2, AVX, FMA3, AVX2
# "17-SKX ~ Kotori"    Intel Skylake X [AVX512]            x64, ABM, BMI1, BMI2, ADX, SSE, SSE2, SSE3, SSSE3, SSE4.1, SSE4.2, AVX, FMA3, AVX2, AVX512-(F/CD/VL/BW/DQ)
# "17-ZN1 ~ Yukina"    AMD Zen 1 Summit Ridge              x64, ABM, BMI1, BMI2, ADX, SSE, SSE2, SSE3, SSSE3, SSE4.1, SSE4.2, AVX, FMA3, AVX2
# "18-CNL ~ Shinoa"    Intel Cannon Lake [AVX512]          x64, ABM, BMI1, BMI2, ADX, SSE, SSE2, SSE3, SSSE3, SSE4.1, SSE4.2, AVX, FMA3, AVX2, AVX512-(F/CD/VL/BW/DQ/IFMA/VBMI)
# "19-ZN2 ~ Kagari"    AMD Zen 2 Matisse (and Zen 3)       x64, ABM, BMI1, BMI2, ADX, SSE, SSE2, SSE3, SSSE3, SSE4.1, SSE4.2, AVX, FMA3, AVX2
# "22-ZN4 ~ Kizuna"    AMD Zen 4 Raphael [AVX512]          x64, ABM, BMI1, BMI2, ADX, SSE, SSE2, SSE3, SSSE3, SSE4.1, SSE4.2, AVX, FMA3, AVX2, AVX512-(F/CD/VL/BW/DQ/IFMA/VBMI/GFNI)
# "24-ZN5 ~ Komari"    AMD Zen 5 Granite Ridge [AVX512]    x64, ABM, BMI1, BMI2, ADX, SSE, SSE2, SSE3, SSSE3, SSE4.1, SSE4.2, AVX, FMA3, AVX2, AVX512-(F/CD/VL/BW/DQ/IFMA/VBMI/VBMI2/GFNI)
#
# If you let y-cruncher run on its own, it will automatically select one of these test modes depending on the processor it detects,
# this is the "Automatic Selection For" column in the table above
# For CoreCycler however you need to select a specific test mode to be run
# As a general rule you can assume that the less instructions are required, the less heat a test mode will produce, and therefore the boost clocks can go higher
# On the other hand, if you actually want to test all the transistors in your chip, you will need to select a test mode that covers all of the available instruction sets
# So it's advised that you test both with the least and the highest amount of available instruction sets for your processor to cover all use cases
#
# Be aware that test modes that require AVX512 instructions will not work on processors that do not support AVX512!
# It will either outright crash or simply not start
#
# A quick overview:
# "04-P4P" produces the least amount of heat and should therefore produce the highest boost clock on most tests
# "14-BDW ~ Kurumi" is the test that y-cruncher itself would default to if you run it on an Intel CPU up to at least 14th gen
# "19-ZN2 ~ Kagari" is the test that y-cruncher itself would default to for Zen 2/3 (Ryzen 3000/5000)
# "22-ZN4 ~ Kizuna" is the test that y-cruncher itself would default to for Zen 4 (Ryzen 7000) and uses AVX512 instructions
# "24-ZN5 ~ Komari" is the test that y-cruncher itself would default to for Zen 5 (Ryzen 9000) and uses AVX512 instructions
#
# User experience seems to indicate that "19-ZN2 ~ Kagari" is pretty good for testing stability, even for Zen 4 (Ryzen 7000) CPUs
# It is unclear yet how Zen 5 / Ryzen 9000 CPUs will turn out
# So as a recommendation, use "04-P4P" for low load testing and "19-ZN2 ~ Kagari" for higher/AVX2 load scenarios
# As "14-BDW ~ Kurumi" is the test mode that y-cruncher chooses for Intel CPUs, it is not entirely clear if this or "19-ZN2 ~ Kagari"
# is the better test for AVX/AVX2 loads on Intel CPUs. At least they share the same instruction sets, so you might need to check for yourself
#
#
# When using the old y-cruncher version ("YCRUNCHER_OLD" selected as the stress test), there's an additional test mode you can use:
#
# Test Mode Name       Automatic Selection For       Required Instruction Set
# --------------       -----------------------       ------------------------
# "00-x86"             Legacy x86                    86/IA-32 since Pentium (BSWAP, CMPXCHG, CPUID, RDTSC, possibly others...)
#
# It is not available anymore in the recent version of y-cruncher, which is now the default one ("YCRUNCHER"), so if you want to use a test
# with the least used instruction sets for low loads, you would need to switch to "YCRUNCHER_OLD" as the stress test
# Also note that if you use "YCRUNCHER_OLD", you will also need to adapt the "tests" setting, as the old version uses different names
#
# Furthermore the "12-BD2 ~ Miyu" test mode is named "11-BD1 ~ Miyu" in "YCRUNCHER_OLD"
#
# Default: 04-P4P
mode = 04-P4P


# Set the test algorithms to run for y-cruncher
# y-crunchers offers various different test algorithms that it can run, here you can select which ones it should use
# Tag     Test Name                     Component        CPU------Mem
# ---     ---------                     ---------        ------------
# BKT     Basecase + Karatsuba          Scalar Integer   -|--------
# BBP     BBP Digit Extraction          AVX2 Float       |---------
# SFT     Small In-Cache FFTv3          AVX2 Float       -|--------
# SFTv4   Small In-Cache FFTv4          AVX2 Float       -|--------
# SNT     Small In-Cache N63            AVX2 Integer     --|-------
# SVT     Small In-Cache VT3            AVX2 Float       --|-------
# FFT     Fast Fourier Transform (v3)   AVX2 Float       ---------|
# FFTv4   Fast Fourier Transform (v4)   AVX2 Float       ---------|
# N63     Classic NTT (v2)              AVX2 Integer     ---|------
# VT3     Vector Transform (v3)         AVX2 Float       ----|-----

#
# Use a comma separated list
# Default: BKT, BBP, SFT, SFTv4, SNT, SVT, FFT, FFTv4, N63, VT3
tests = BKT, BBP, SFT, SFTv4, SNT, SVT, FFT, FFTv4, N63, VT3


# Set the test algorithms to run for the "old" version of y-cruncher ("YCRUNCHER_OLD" selected as the stress test)
# This older version (v0.7.10.9513) has a different set of tests to choose from
# Tag   Test Name               Component         CPU------Mem
# ---   ---------               ---------         ------------
# BKT   Basecase + Karatsuba    Scalar Integer    -|--------
# BBP   BBP Digit Extraction    Floating-Point    |---------    depending on the selected mode uses SSE, AVX, AVX2 or AVX512
# SFT   Small In-Cache FFT      Floating-Point    -|--------    depending on the selected mode uses SSE, AVX, AVX2 or AVX512
# FFT   Fast Fourier Transform  Floating-Point    ---------|    depending on the selected mode uses SSE, AVX, AVX2 or AVX512
# N32   Classic NTT (32-bit)    Scalar Integer    -----|----    depending on the selected mode uses SSE, AVX, AVX2 or AVX512
# N64   Classic NTT (64-bit)    Scalar Integer    ---|------    depending on the selected mode uses SSE, AVX, AVX2 or AVX512
# HNT   Hybrid NTT              Mixed Workload    -----|----
# VST   Vector Transform        Floating-Point    ------|---    depending on the selected mode uses SSE, AVX, AVX2 or AVX512
# C17   Code 17 Experiment      AVX2/512 Mixed    ---|------    depending on the selected mode uses AVX2 or AVX512
#
# Important:
# "C17" (Code 17 Experiment) will only work with a AVX2 and AVX512 workload (so with mode "13-HSW ~ Airi" and above)
#
# Use a comma separated list
# Default: BKT, BBP, SFT, FFT, N32, N64, HNT, VST
#tests = BKT, BBP, SFT, FFT, N32, N64, HNT, VST


# Set the duration in seconds for each test in y-cruncher
# The duration for each individual test selected above in the "tests" setting
# Note: not the total runtime
#
# Default: 60
testDuration = 60


# Memory allocation for y-cruncher
# This allows you to customize the allocated memory for y-cruncher
# Set the value in bytes or use a "short" notation like e.g. "64MB"
# The default setting uses 13.4 MB (13418572 bytes, 12.8 MiB) for one resp. 26.7 MB (26567600 bytes, 25.3 MiB) for two threads
# Note the difference between "MB" (1000 kilobyte = 1000*1000 byte) and "MiB" (1024 kibibyte = 1024*1024 byte)
#
# Default: Default
memory = Default


# Enable or disable the custom logging wrapper for y-cruncher
# We are using the helpers/WriteConsoleToWriteFileWrapper.exe executable to capture the output of y-cruncher and write it to a file
# It is using the Microsoft Detours C++ library to do so
# Here you can disable this behaviour and revert back to the original y-cruncher execution
#
# It is strongly recommended to leave this setting enabled, unless you're experiencing problems with it!
#
# Default: 1
enableYCruncherLoggingWrapper = 1




# Aida64 specific settings
[Aida64]

# The test modes for Aida64
# Note: "RAM" consumes basically all of the available memory and makes the computer pretty slow
#       You can change the amount of RAM being used / tested with the "maxMempory" setting below
# CACHE: Starts Aida64 with the "Cache" stress test
# CPU:   Starts Aida64 with the "CPU" stress test
# FPU:   Starts Aida64 with the "FPU" stress test
# RAM:   Starts Aida64 with the "Memory" stress test
# You can also combine multiple stress tests like so: CACHE,CPU,FPU
#
# Default: CACHE
mode = CACHE


# Use AVX for Aida64
# This enables or disables the usage of AVX instructions during Aida64's stress tests
#
# Default: 0
useAVX = 0


# The maximum memory allocation for Aida64
# Sets the maximum memory usage during the "RAM" stress test in percent
# Note: Setting this too high can cause your Windows to slow down to a crawl!
#
# Default: 90
maxMemory = 90




# Linpack specific settings
[Linpack]

# Which version of Linpack to use
# There are four different choices available
# 2018: Intel Linpack version 2018.0.3.1 - this is the same version as used in Linpack Xtreme 1.1.5
# 2019: Intel Linpack version 2019.0.3.1
# 2021: Intel Linpack version 2021.4.1.0 - this version always uses FASTEST (AVX2)
# 2024: Intel Linpack version 2024.2.1.0 - this version always uses FASTEST (AVX2)
#
# Version 2018 and 2019 are the only ones where you can set the mode to anything but "FASTEST"
# These two version also run slightly faster (more GFlops) on AMD processors than the newer versions when set to "FASTEST"
# But the newer versions might have additional optimizations that are missing in the older ones
#
# Default: 2018
version = 2018


# The test mode for Linpack
# You can choose between five settings:
# SLOWEST
# SLOW
# MEDIUM
# FAST
# FASTEST
# These settings define how fast one iteration will be completed (how many GFlops you'll see and the time it takes)
# It should also affect which instruction set is being used, e.g. FASTEST should enable AVX2, while FAST should
# use AVX
# I'm not entirely sure what instructions the other settings use exactly, but I did see a difference in the runtime
# and GFlops for these settings
# Here are some examples (not comparable to anything else, since determined with a custom overclock/undervolt setting):
#             Ryzen 5900X 1 Thread         Intel 14900KF 1 Thread
#             GFlops    Time    Temp       GFlops    Time    Temp
# SLOWEST     ~21       ~126s   ~67°C      ~28       ~96s    ~64°C
# SLOW        ~25       ~105s   ~71°C      ~28       ~94s    ~65°C
# MEDIUM      ~27       ~99s    ~71°C      ~30       ~89s    ~66°C
# FAST        ~45       ~59s    ~75°C      ~51       ~52s    ~66°C
# FASTEST     ~66       ~40s    ~76°C      ~78       ~34s    ~69°C
#
# As you can see, the setting has a more pronounced effect on AMD CPUs, but Intel CPUs are affected as well, just not
# as much on the slower settings
# This setting makes use of an undocumentented environment variable (MKL_DEBUG_CPU_TYPE) for Intel's MKL library
# (Math Kernel Library), which is interally used by Linpack
#
# Default: MEDIUM
mode = MEDIUM


# Memory allocation for Linpack
# Set the amount of memory to use with Linpack
# Enter the value either as a string like 500MB, 2GB, 4GB, etc
# Or as a raw value in bytes, e.g. 250000000 (which would equal "250MB")
# Note the difference between "MB" (1000 kilobyte = 1000*1000 byte) and "MiB" (1024 kibibyte = 1024*1024 byte)
# Also be aware that the memory size directly influences the time it takes to run one test, here are some examples:
# Setting    Sample runtime    Sample runtime
#               with MEDIUM      with FASTEST
# 100MB                  1s              0.5s
# 250MB                  4s                2s
# 500MB                 12s                5s
# 750MB                 23s                9s
# 1GB                   35s               14s
# 2GB                   99s               40s
# 4GB                  287s              117s
# 6GB                  534s              216s
# 30GB         unknown, >1h        not tested    (I aborted after over an hour)
# Also note that choosing more memory doesn't necessarily help in finding CPU related problems
# It may help identifying RAM or IMC (Internal Memory Controller) related issues
#
# Default: 2GB
memory = 2GB




# Settings for the Automatic Test Mode
[AutomaticTestMode]

# Enable the automatic test mode
# If you enable this setting, the script will automatically adjust the Curve Optimizer or voltage offset values
# when an error occurs
#
# For Ryzen CPUs it uses "ryzen-smu-cli", which is included in the /tools/ryzen-smu-cli/ directory
# For Intel, it uses "IntelVoltageControl", which allows you to set a voltage offset (also included in the /tools/ directory)
#
# Note that this will only INCREASE the Curve Optimizer / voltage offset values, i.e. it will try to make the settings
# more stable, it will never push the settings more into the negative
# Also note that enabling this setting will require the script to be run with administrator privileges
# And lastly, enabling it will set "skipCoreOnError" to 0 and "stopOnError" to 0 as long as the limit has not been reached
#
# IMPORTANT: The automatically adjusted Curve Optimizer / voltage offset values are NOT permanent, so after a regular reboot they
#            will not be applied anymore
#            If you want to permanently set these values, you will need to set them in the BIOS, or use a startup script to
#            set them on every Windows start (see the .txt files for ryzen-smu-cli resp. IntelVoltageControl in the /tools
#            directory for an explanation of the various settings)
#
# Default: 0
enableAutomaticAdjustment = 0


# The starting Curve Optimizer / voltage offset values
# You can provide the Curve Optimizer / voltage offset starting values here, or let them be automatically detected
# If you specify values here, they will overwrite your currently applied CO / voltage offset settings
# If you leave the value blank or at "Default", it will try to automatically detect your current settings
#
# Use a comma separated list or define a single value that will be applied to all cores
# You can also use spaces or "|" to separate the cores
# For Intel, this currently only really supports a single voltage offset that is applied to each core
# For Ryzen, you can define the Curve Optimizer value for each core
#
# Note: For Ryzen, the minimum possible Curve Optimizer value is defined by your CPU (and possibly motherboard)
#       -30 is a common minimum value for Curve Optimizer, sometimes even -50
# Note: For Intel, the values are provided in millivolts, so e.g. -130 for an undervolt of -0.130v
#
# IMPORTANT: Use a negative sign if you want negative CO values / a negative voltage offset, not providing a negative sign will
#            instead apply a positive CO / voltage offset!
# IMPORTANT: The automatically adjusted Curve Optimizer / voltage offset values are TEMPORARY, so after a regular reboot they
#            will not be applied anymore
#            If you want to permanently set these values, you will need to set them in the BIOS, or use a startup script to
#            set them on every Windows start (see the text files in the /tools directory for an explanation of the various settings)
#
# Example for setting Curve Optimizer values for a Ryzen 5800X with 8 cores:
# startValues = -15, -10, -15, -8, 2, -20, 0, -30
# Or
# startValues = -15 -10 -15 -8 2 -20 0 -30
# Or
# startValues = -15 | -10 | -15 | -8 | 2 | -20 | 0 | -30
#
# Example to assign a single Curve Optimizer value to all cores:
# startValues = -20
#
# Example to assign a voltage offset of -0.120v (-120mv) for Intel processors:
# startValues = -120
#
# Default: Default
startValues = Default


# The upper limit for the Curve Optimizer values / voltage offset
# If this limit has been reached, no further adjustments will be performed
# Instead the core will now simply throw an error and the regular "skipCoreOnError" setting will be obeyed
# This is either a Curve Optimizer value or a voltage offset value
#
# IMPORTANT: Be sensible about this value, setting it too high into the positive could apply a too high
#            voltage to your CPU and may damage it!
#
# Default: 0
maxValue = 0


# The amount by which to increase the Curve Optimizer / voltage offset value
# On an error, the Curve Optimizer / voltage offset value will be increased by this amount
# For Ryzen, a value between 1 and 5 seems reasonable
# For Intel, you should probably set this to 5 to increase the vCore by 5mv after an error
#
# Setting it to "Default" will set the value to 1 for Ryzen and 5 for Intel
#
# Default: Default
incrementBy = Default


# Set only the currently tested core to the selected Curve Optimizer / voltage offset value
# All the other cores will be set to 0, resp. the determined maximum value if it's higher than 0
# This should prevent errors caused by other cores than the currently tested one, or at least diminish the chance for that
#
# Note: Currently this only has an effect for Ryzen processors, for Intel up to 14th gen there is only one voltage value
#
# Default: 0
setVoltageOnlyForTestedCore = 0


# Repeat the test on a core if it has thrown an error and the Curve Optimizer / voltage offset value was increased
# Setting this to 1 will restart the test, until it has not thrown an error, or until the maximum value has been reached
# Setting it to 0, the script will continue to the next core in line as normal
#
# Default: 1
repeatCoreOnError = 1


# Try to automatically resume after a crash / hard reboot
# If this setting is enabled, the script will try to automatically resume after a reboot has occurred
# It creates a Scheduled Task that will be run at logon, which then tries to resume where it left off,
# optionally repeating the last core with an adjusted value (see the repeatCoreOnError setting)
#
# IMPORTANT: If you just close the CoreCycler window without properly exiting the script with CTRL+C,
#            the Scheduled Task will remain and will be executed on the next reboot!
#            So make sure that you always exit CoreCycler by pressing CTRL+C
#
# IMPORTANT: The Scheduled Task will execute once you log back in to your user account
#            So for a true automated testing, it would be beneficial if you activated auto-logon
#            Be aware that this might pose a security risk though, so make sure to consider the risks!
#            https://learn.microsoft.com/en-us/sysinternals/downloads/autologon
#            https://learn.microsoft.com/en-us/troubleshoot/windows-server/user-profiles-and-logon/turn-on-automatic-logon
#
# Default: 0
enableResumeAfterUnexpectedExit = 0


# Windows treats crashes or reboots that happen within 120 seconds of the boot as a "failed" boot
# To prevent the Windows Recovery Screen from appearing after three of those "failed" boots, the script will wait for this
# amount of time before resuming the testing process
# Set this to 0 if you don't care about that and want to resume immediately
#
# Default: 120
waitBeforeAutomaticResume = 120




# Log specific settings
[Logging]

# The name of the log file
# The "mode" parameter, the selected stress test program and test mode, as well as the start date & time will be
# added to the name, with a .log file ending
#
# Default: CoreCycler
name = CoreCycler


# Set the log level
# 0: Do not log or display additional information
# 1: Write additional information to the log file (verbose)
# 2: Write even more information to the log file (debug)
# 3: Also display the verbose messages in the terminal
# 4: Also display the debug messages in the terminal
#
# Default: $logLevel
logLevel = $logLevel


# Make use of the Windows Event Log to log core tests and core errors
# If this is enabled, CoreCycler will add entries to the Windows Event Log when it has been started, ended,
# and also when iterating over the cores
# This can be helpful if you suffer from corrupted log files after a hard reboot during testing
# To be able to use this, a new Windows Event "Source" for CoreCycler needs to be added, the script will ask
# you add this if it's not available yet
# Adding this Source will require Administrator rights (once), but after it has been added, no additional rights
# are required
# The entries can be found in the Windows Logs/Application section of the Event Viewer
#
# Default: 1
useWindowsEventLog = 1


# Periodically flush the disk write cache
# If this is enabled, CoreCycler will periodically try to flush the disk write cache, which could help to prevent
# corrupted log files when a hard reboot during testing occurs
# Note that some drives have an additional internal write cache, which is NOT affected by this setting
# Also note that this will not work for all drives/volumes, e.g. if you run the script from a VeraCrypt volume,
# this setting will have no effect
#
# Default: 0
flushDiskWriteCache = 0




# Settings for updates
[Update]

# Enable the update check
#
# Default: $([Int] $enableUpdateCheck)
enableUpdateCheck = $([Int] $enableUpdateCheck)


# The frequency of the check, in hours
#
# Default: $updateCheckFrequency
updateCheckFrequency = $updateCheckFrequency




# Custom settings for Prime95
[Prime95Custom]

# This needs to be set to 1 for AVX mode
# (and also if you want to set AVX2 below)
CpuSupportsAVX = 0


# This needs to be set to 1 for AVX2 mode
CpuSupportsAVX2 = 0


# This also needs to be set to 1 for AVX2 mode on Ryzen
CpuSupportsFMA3 = 0


# This needs to be set to 1 for AVX512 mode
CpuSupportsAVX512 = 0


# The minimum FFT size to test
# Value for "Smallest FFT":   4
# Value for "Small FFT":     36
# Value for "Large FFT":    426
MinTortureFFT = 4


# The maximum FFT size to test
# Value for "Smallest FFT":   21
# Value for "Small FFT":     248
# Value for "Large FFT":    8192
MaxTortureFFT = 8192


# The amount of memory to use in MB
# 0 = In-Place
TortureMem = 0


# The max amount of minutes for each FFT size during the stress test
# Note: It may be much less than one minute, basically it seems to be "one run or one minute, whichever is less"
TortureTime = 1




# Debug settings that shouldn't need to be changed
# Only change them if you know what you're doing and there's a problem you're trying to identify
[Debug]

# Debug setting to disable the periodic CPU utilization check
#
# This setting enables or disables the CPU utilization check during stress testing.
# Some stress test programs (like Aida64) do not generate a log file, so the only way to detect an error is by
# checking the current CPU utilization.
#
# This uses a pretty basic check to see if the stress is still running at all, for a more detailled check
# enable the "useWindowsPerformanceCountersForCpuUtilization" below.
# Be aware that enabling the Windows Performance Counters may introduce other issues though, see the
# corresponding setting for an explanation.
#
# Default: $disableCpuUtilizationCheckDefault
disableCpuUtilizationCheck = $disableCpuUtilizationCheckDefault


# Debug setting to enable the use of Windows Performance Counters for the CPU utilization check
#
# This setting controls if the Windows Performance Counters should be used, which can be corrupted for unknown
# reasons. Please see the readme.txt and the /tools/enable_performance_counter.bat file for a possible way
# to fix these issues. There's no guarantee that it works though.
#
# Default: $useWindowsPerformanceCountersForCpuUtilizationDefault
useWindowsPerformanceCountersForCpuUtilization = $useWindowsPerformanceCountersForCpuUtilizationDefault


# Debug setting to enable querying for the CPU frequency
#
# This setting enables checking the CPU frequency
# Currently it doesn't really serve any purpose. The retrieved CPU frequency is not accurate enough (e.g. compared to HWiNFO),
# and its output is limited to the "verbose" channel.

# According to some reports, enabling it can result in incorrect CPU utilization readings, so be aware of this when you enable
# this setting.
#
# Note that this also enables the usage of the Windows Performance Counters, which may not work on certain systems.
# They can become corrupted, please see the readme.txt and the /tools/enable_performance_counter.bat file for a possible way
# to fix these issues. There's no guarantee that it works though.
#
# Default: $enableCpuFrequencyCheckDefault
enableCpuFrequencyCheck = $enableCpuFrequencyCheckDefault


# Debug setting to control the interval in seconds for the CPU utilization check and the "suspendPeriodically" functionality
#
# Don't set this too low, it will spam the log file and can produce unnecessary CPU load.
# It would also increase the time when the stress test program is suspended
# I'd consider 10 to be the minimum reasonable value (which is also the default)
#
# If 0, will disable this functionality
# This basically would mean "disableCpuUtilizationCheck = 1" and "suspendPeriodically = 0"
# Not entirely though, as the last check before changing a core is not affected
#
# Default: $tickIntervalDefault
tickInterval = $tickIntervalDefault


# Debug setting to delay the first error check for each core
#
# With this setting you can define a wait time before the first error check happens for each core
# Some systems may need longer to initialize the stress test program, which can result in an incorrect CPU utilization detection,
# so setting this value might resolve this issue
# Don't set this value too high in relation to your "runTimePerCore" though
#
# Default: $delayFirstErrorCheckDefault
delayFirstErrorCheck = $delayFirstErrorCheckDefault


# Debug setting to set the priority of the stress test program
#
# The default priority is set to "High" so that other applications don't interfere with the testing
# It can cause the computer to behave sluggish though. Setting a lower priority can fix this
#
# Note: "RealTime" probably won't work and you shouldn't set this anway, as the computer won't be responsive anymore
#
# Possible values:
# Idle
# BelowNormal
# Normal
# AboveNormal
# High
# RealTime
#
# Default: $stressTestProgramPriorityDefault
stressTestProgramPriority = $stressTestProgramPriorityDefault


# Debug setting to display the stress test program window in the foreground
#
# If enabled, will display the window of the stress test program in the foreground, stealing focus
# If disabled (default), the window will either be minimized to the tray (Prime95) or be moveed to the background,
# without stealing focus of the currently opened window (y-cruncher)
#
# Default: $stressTestProgramWindowToForegroundDefault
stressTestProgramWindowToForeground = $stressTestProgramWindowToForegroundDefault


# Debug setting to control the amount of milliseconds the stress test program is being suspended
#
# Default: $suspensionTimeDefault
suspensionTime = $suspensionTimeDefault


# Debug setting to define the method that is used to suspend the stress test process
#
# Can either be set to "Debugger" or "Threads"
# "Debugger" uses the "DebugActiveProcess" and "DebugActiveProcessStop" kernel32.dll methods on the main process
# "Threads" uses the "SuspendThread" and "ResumeThread" kernel32.dll methods on the process threads
# There's no clear benefit to either of these settings, but if there's a problem with one of these settings,
# the other one may work better
#
# Default: $modeToUseForSuspensionDefault
modeToUseForSuspension = $modeToUseForSuspensionDefault
"@



# Stress test program executables and paths
# The window behaviours:
# 0 = Hide
# 1 = NormalFocus
# 2 = MinimizedFocus
# 3 = MaximizedFocus
# 4 = NormalNoFocus
# 6 = MinimizedNoFocus
$stressTestPrograms = @{
    'prime95'       = @{
        'displayName'         = 'Prime95'
        'processName'         = 'prime95'
        'processNameExt'      = 'exe'
        'processNameForLoad'  = 'prime95'
        'processPath'         = 'test_programs\p95'
        'installPath'         = 'test_programs\p95'
        'requiresCpuCheck'    = $false
        'configName'          = $null
        'configFilePath'      = $null
        'absolutePath'        = $null
        'absoluteInstallPath' = $null
        'fullPathToExe'       = $null
        'command'             = '"%fullPathToExe%" -t'
        'windowBehaviour'     = 0
        'testModes'           = @(
            'SSE'
            'AVX'
            'AVX2'
            'AVX512'
            'CUSTOM'
        )
        'windowNames'         = @(
            '^Prime95 \- Torture Test$'
            '^Prime95 \- Self\-Test$'
            '^Prime95 \- Not running$'
            '^Prime95 \- Waiting for work$'
            '^Prime95$'
        )
    }

    'prime95_dev'   = @{
        'displayName'         = 'Prime95 DEV'
        'processName'         = 'prime95_dev'
        'processNameExt'      = 'exe'
        'processNameForLoad'  = 'prime95_dev'
        'processPath'         = 'test_programs\p95_dev'
        'installPath'         = 'test_programs\p95_dev'
        'requiresCpuCheck'    = $false
        'configName'          = $null
        'configFilePath'      = $null
        'absolutePath'        = $null
        'absoluteInstallPath' = $null
        'fullPathToExe'       = $null
        'command'             = '"%fullPathToExe%" -t'
        'windowBehaviour'     = 0
        'testModes'           = @(
            'SSE'
            'AVX'
            'AVX2'
            'AVX512'
            'CUSTOM'
        )
        'windowNames'         = @(
            '^Prime95 \- Torture Test$'
            '^Prime95 \- Self\-Test$'
            '^Prime95 \- Not running$'
            '^Prime95 \- Waiting for work$'
            '^Prime95$'
        )
    }

    'aida64'        = @{
        'displayName'         = 'Aida64'
        'processName'         = 'aida64'
        'processNameExt'      = 'exe'
        'processNameForLoad'  = 'aida_bench64.dll'   # This needs to be with file extension
        'processPath'         = 'test_programs\aida64'
        'installPath'         = 'test_programs\aida64'
        'requiresCpuCheck'    = $true   # No log file, need to check the current CPU usage
        'configName'          = $null
        'configFilePath'      = $null
        'absolutePath'        = $null
        'absoluteInstallPath' = $null
        'fullPathToExe'       = $null
        'command'             = '"%fullPathToExe%" /SAFEST /SILENT /SST %mode%'
        'windowBehaviour'     = 6
        'testModes'           = @(
            'CACHE'
            'CPU'
            'FPU'
            'RAM'
        )
        'windowNames'         = @(
            '^System Stability Test \- AIDA64*'
        )
    }

    'ycruncher'     = @{
        'displayName'         = 'y-cruncher'
        'processName'         = '' # Depends on the selected modeYCruncher
        'processNameExt'      = 'exe'
        'processNameForLoad'  = '' # Depends on the selected modeYCruncher
        'processPath'         = 'test_programs\y-cruncher\Binaries'
        'installPath'         = 'test_programs\y-cruncher'
        'configName'          = 'stressTest.cfg'
        'requiresCpuCheck'    = $false  # Since 0.9.5 and with enableYCruncherLoggingWrapper enabled, can now read its output to look for errors
        'configFilePath'      = $null
        'absolutePath'        = $null
        'absoluteInstallPath' = $null
        'fullPathToExe'       = $null
        'fullPathToLoadExe'   = $null
        'command'             = 'cmd /C start /MIN /AFFINITY 0xC "y-cruncher - %fileName%" "%fullPathToExe%" priority:2 config "%configFilePath%"'
        'commandWithLogging'  = 'cmd /C start /MIN /AFFINITY 0xC "y-cruncher - %fileName%" "%helpersPath%WriteConsoleToWriteFileWrapper.exe" "%fullPathToLoadExe%" priority:2 config "%configFilePath%" /dlllog:"%logFilePath%"'
        'windowBehaviour'     = 6
        'testModes'           = @(
            '04-P4P'
            '05-A64 ~ Kasumi'
            '08-NHM ~ Ushio'
            '11-SNB ~ Hina'
            '12-BD2 ~ Miyu'
            '13-HSW ~ Airi'
            '14-BDW ~ Kurumi'
            '17-ZN1 ~ Yukina'
            '19-ZN2 ~ Kagari'

            # The following settings seem to be designed for Intel CPUs and don't run on Ryzen CPUs
            '17-SKX ~ Kotori'
            '18-CNL ~ Shinoa'

            # This setting is designed for Ryzen 7000 (Zen 4) CPUs and uses AVX-512
            '22-ZN4 ~ Kizuna'

            # This setting is designed for Ryzen 9000 (Zen 5) CPUs and uses AVX-512
            '24-ZN5 ~ Komari'
        )
        'availableTests'      = @('BKT', 'BBP', 'SFT', 'SFTv4', 'SNT', 'SVT', 'FFT', 'FFTv4', 'N63', 'VT3')
        'defaultTests'        = @('BKT', 'BBP', 'SFT', 'SFTv4', 'SNT', 'SVT', 'FFT', 'FFTv4', 'N63', 'VT3')
        'windowNames'         = @(
            '' # Depends on the selected modeYCruncher
        )
    }


    # Version 0.7.10 of y-cruncher
    'ycruncher_old' = @{
        'displayName'         = 'y-cruncher [0.7.10]'
        'processName'         = '' # Depends on the selected modeYCruncher
        'processNameExt'      = 'exe'
        'processNameForLoad'  = '' # Depends on the selected modeYCruncher
        'processPath'         = 'test_programs\y-cruncher-0.7.10\Binaries'
        'installPath'         = 'test_programs\y-cruncher-0.7.10'
        'configName'          = 'stressTest.cfg'
        'requiresCpuCheck'    = $false  # Since 0.9.5 and with enableYCruncherLoggingWrapper enabled, can now read its output to look for errors
        'configFilePath'      = $null
        'absolutePath'        = $null
        'absoluteInstallPath' = $null
        'fullPathToExe'       = $null
        'fullPathToLoadExe'   = $null
        'command'             = 'cmd /C start /MIN /AFFINITY 0xC "y-cruncher - %fileName%" "%fullPathToExe%" priority:2 config "%configFilePath%"'
        'commandWithLogging'  = 'cmd /C start /MIN /AFFINITY 0xC "y-cruncher - %fileName%" "%helpersPath%WriteConsoleToWriteFileWrapper.exe" "%fullPathToLoadExe%" priority:2 config "%configFilePath%" /dlllog:"%logFilePath%"'
        'windowBehaviour'     = 6
        'testModes'           = @(
            '00-x86'
            '04-P4P'
            '05-A64 ~ Kasumi'
            '08-NHM ~ Ushio'
            '11-BD1 ~ Miyu'
            '11-SNB ~ Hina'
            '13-HSW ~ Airi'
            '14-BDW ~ Kurumi'
            '17-ZN1 ~ Yukina'
            '19-ZN2 ~ Kagari'
            '20-ZN3 ~ Yuzuki'

            # The following settings seem to be designed for Intel CPUs and don't run on Ryzen CPUs
            '17-SKX ~ Kotori'
            '18-CNL ~ Shinoa'

            # This setting is designed for Ryzen 7000 (Zen 4) CPUs and uses AVX-512
            '22-ZN4 ~ Kizuna'
        )
        'availableTests'      = @('BKT', 'BBP', 'SFT', 'FFT', 'N32', 'N64', 'HNT', 'VST', 'C17')
        'defaultTests'        = @('BKT', 'BBP', 'SFT', 'FFT', 'N32', 'N64', 'HNT', 'VST')
        'windowNames'         = @(
            '' # Depends on the selected modeYCruncher
        )
    }


    # Linpack
    'linpack'       = @{
        'displayName'         = 'Linpack'
        'processName'         = 'linpack_patched'
        'processNameExt'      = 'exe'
        'processNameForLoad'  = 'linpack_patched'
        'processPath'         = 'test_programs\linpack'
        'installPath'         = 'test_programs\linpack'
        'configName'          = 'stressTest.ini'
        'requiresCpuCheck'    = $false
        'configFilePath'      = $null
        'absolutePath'        = $null
        'absoluteInstallPath' = $null
        'fullPathToExe'       = $null
        'fullPathToLoadExe'   = $null
        'command'             = 'cmd /C start /MIN "Linpack CoreCycler ' + $version + '" powershell.exe -Command "$Host.UI.RawUI.WindowTitle = ''Linpack CoreCycler ' + $version + '''; $PSDefaultParameterValues[''*:Encoding''] = ''utf8''; $env:OMP_NUM_THREADS = %OMP_NUM_THREADS%; %MKL_DEBUG_CPU_TYPE% $env:OMP_PLACES = ''CORES''; $env:OMP_PROC_BIND = ''SPREAD''; $env:MKL_DYNAMIC = ''FALSE''; $logFilePath = ''%logFilePath%''; if (!([IO.File]::Exists($logFilePath))) { [IO.File]::WriteAllLines($logFilePath, (Get-Date -Format HH:mm:ss)) }; & \"%fullPathToLoadExe%\" ''%configFilePath%'' | Tee-Object -FilePath $logFilePath -Append"'
        'windowBehaviour'     = 6
        'testModes'           = @(
            'SLOWEST'
            'SLOW'
            'MEDIUM'
            'FAST'
            'FASTEST'
        )
        'availableTests'      = @()
        'defaultTests'        = @()
        'windowNames'         = @(
            '^Linpack CoreCycler ' + $version + '$'
        )
    }
}


# Programs where both the main window and the stress test are the same process
$stressTestProgramsWithSameProcess = @(
    'prime95', 'prime95_dev', 'ycruncher', 'ycruncher_old', 'linpack'
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
    'Process'          = ''
    'ID Process'       = ''
    '% Processor Time' = ''
    'FullName'         = ''
    'SearchString'     = ''
    'ReplaceString'    = ''

    # Possible future use
    #'Processor Information'   = ''
    #'% Processor Performance' = ''
    #'% Processor Utility'     = ''
}


# If we haven't got a parentMainWindowHandle, look through the window titles
if ($parentMainWindowHandle -eq [System.IntPtr]::Zero) {
    $oldWindowTitle  = $Host.UI.RawUI.WindowTitle
    $tempWindowTitle = $oldWindowTitle + ' - ' + $scriptProcessId

    $Host.UI.RawUI.WindowTitle = $tempWindowTitle

    $parentProcess = Get-Process | Where-Object {
        $_.MainWindowTitle -Match ('^' + $tempWindowTitle + '$')
    }

    $Host.UI.RawUI.WindowTitle = $oldWindowTitle

    if ($parentProcess) {
        $parentProcessId = $parentProcess.Id
        $parentMainWindowHandle = $parentProcess.MainWindowHandle
    }
}


# Use Format-List to make a Hash-Table debug output readable
Update-TypeData -TypeName System.Collections.HashTable -MemberType ScriptMethod -MemberName ToString -Value { return ($this | Format-List | Out-String) } -Force



# Prevent Sleep/Standby/Hibernation while the script is running
# Source: https://stackoverflow.com/a/65162017/973927
$PowerUtilDefinition = @'
    // Member variables.
    static IntPtr _powerRequest;
    static bool _mustResetDisplayRequestToo;

    // P/Invoke function declarations.
    [DllImport("kernel32.dll")]
    static extern IntPtr PowerCreateRequest(ref POWER_REQUEST_CONTEXT Context);

    [DllImport("kernel32.dll")]
    static extern bool PowerSetRequest(IntPtr PowerRequestHandle, PowerRequestType RequestType);

    [DllImport("kernel32.dll")]
    static extern bool PowerClearRequest(IntPtr PowerRequestHandle, PowerRequestType RequestType);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true, ExactSpelling = true)]
    static extern int CloseHandle(IntPtr hObject);

    // Availablity Request Enumerations and Constants
    enum PowerRequestType {
            PowerRequestDisplayRequired = 0,
            PowerRequestSystemRequired,
            PowerRequestAwayModeRequired,
            PowerRequestMaximum
    }

    const int POWER_REQUEST_CONTEXT_VERSION = 0;
    const int POWER_REQUEST_CONTEXT_SIMPLE_STRING = 0x1;

    // Availablity Request Structures
    // Note:  Windows defines the POWER_REQUEST_CONTEXT structure with an
    // internal union of SimpleReasonString and Detailed information.
    // To avoid runtime interop issues, this version of
    // POWER_REQUEST_CONTEXT only supports SimpleReasonString.
    // To use the detailed information,
    // define the PowerCreateRequest function with the first
    // parameter of type POWER_REQUEST_CONTEXT_DETAILED.
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct POWER_REQUEST_CONTEXT {
            public UInt32 Version;
            public UInt32 Flags;
            [MarshalAs(UnmanagedType.LPWStr)]
            public string SimpleReasonString;
    }

    /// <summary>
    /// Prevents the system from going to sleep, by default not including the display.
    /// </summary>
    /// <param name="enable">
    ///   True to turn on, False to turn off. Passing True must be paired with a later call passing False.
    ///   If you pass True repeatedly, subsequent invocations take no actions and ignore the parameters.
    ///   If you pass False, the remaining parameters are ignored.
    //    If you pass False without having passed True earlier, no action is performed.
    //// </param>
    /// <param name="includeDisplay">True to also keep the display awake; defaults to False.</param>
    /// <param name="reasonString">
    ///   A string describing why the system is being kept awake; defaults to the current process' command line.
    ///   This will show in the output from `powercfg -requests` (requires elevation).
    /// </param>
    public static void StayAwake(bool enable, bool includeDisplay = false, string reasonString = null) {
        if (enable) {
            // Already enabled: quietly do nothing.
            if (_powerRequest != IntPtr.Zero) { return; }

            // Configure the reason string.
            POWER_REQUEST_CONTEXT powerRequestContext;
            powerRequestContext.Version = POWER_REQUEST_CONTEXT_VERSION;
            powerRequestContext.Flags = POWER_REQUEST_CONTEXT_SIMPLE_STRING;
            powerRequestContext.SimpleReasonString = reasonString ?? System.Environment.CommandLine; // The reason for making the power request

            // Create the request (returns a handle).
            _powerRequest = PowerCreateRequest(ref powerRequestContext);

            // Set the request(s).
            PowerSetRequest(_powerRequest, PowerRequestType.PowerRequestSystemRequired);

            if (includeDisplay) {
                PowerSetRequest(_powerRequest, PowerRequestType.PowerRequestDisplayRequired);
            }

            _mustResetDisplayRequestToo = includeDisplay;

        }
        else {

            // Not previously enabled: quietly do nothing.
            if (_powerRequest == IntPtr.Zero) {
                return;
            }

            // Clear the request
            PowerClearRequest(_powerRequest, PowerRequestType.PowerRequestSystemRequired);

            if (_mustResetDisplayRequestToo) {
                PowerClearRequest(_powerRequest, PowerRequestType.PowerRequestDisplayRequired);
            }

            CloseHandle(_powerRequest);
            _powerRequest = IntPtr.Zero;

        }
    }

    // Overload that allows passing a reason string while defaulting to keeping the display awake too.
    public static void StayAwake(bool enable, string reasonString) {
        StayAwake(enable, false, reasonString);
    }
'@



# Windows 11 still seems to go into Hybrid Sleep, even if the Power Request is set
# Let's try to use ShutdownBlockReasonCreate
# Source: https://www.reddit.com/r/PowerShell/comments/p1rdkd/can_powershell_prevent_system_shutdown_while_a/
#
#  Your application will appear in the "Applications that prevent the shutdown" list with the message you register using the ShutdownBlockReasonCreate function
# - but only if it returns FALSE for the WM_QUERYENDSESSION message.
# If the user has the AutoEndTasks registry value set (found in HKCU\Control Panel\Desktop registry key), then the shutdown does not show any UI to let the user cancel shutdown
$ShutdownBlockDefinition = @'
    using System;
    using System.Runtime.InteropServices;

    public class ShutdownBlock {
        [DllImport(@"user32.dll", SetLastError = true)]
        public static extern bool ShutdownBlockReasonCreate(IntPtr WindowHandle, string Reason);

        [DllImport(@"user32.dll", SetLastError = true)]
        public static extern bool ShutdownBlockReasonDestroy(IntPtr WindowHandle);

        //[DllImport(@"user32.dll", SetLastError = true)]
        //public static extern bool ShutdownBlockReasonQuery(IntPtr WindowHandle, [MarshalAs(UnmanagedType.LPWStr)] StringBuilder pwszBuff, ref uint pcchBuff);

        [DllImport("kernel32.dll")]
        public static extern uint GetLastError();

        [DllImport("kernel32.dll", CharSet = CharSet.Auto)]
        public static extern uint FormatMessage(uint dwFlags, IntPtr lpSource, uint dwMessageId, uint dwLanguageId, ref IntPtr lpBuffer, uint nSize, IntPtr Arguments);
    }
'@



# Add code definitions so that we can close a window even if it's minimized to the tray
# The regular PowerShell way unfortunetely doesn't work in this case
# The definition to get the main window handle even if the process is minimized to the tray
$GetWindowsDefinition = @'
    using System;
    using System.Text;
    using System.Collections.Generic;
    using System.Runtime.InteropServices;

    namespace GetWindows {
        public class WinStruct {
            public string WinTitle {get; set; }
            public int MainWindowHandle { get; set; }
            public string ProcessPath { get; set; }
            public int ProcessId { get; set; }
        }

        public class Main {
            private static int PROCESS_QUERY_INFORMATION = (0x00000400);
            private static int PROCESS_VM_READ           = (0x00000010);

            private delegate bool CallBackPtr(int hwnd, int lParam);
            private static CallBackPtr callBackPtr = Callback;
            private static List<WinStruct> _WinStructList = new List<WinStruct>();

            // Get all windows
            [DllImport("user32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            private static extern bool EnumWindows(CallBackPtr lpEnumFunc, IntPtr lParam);

            // Get the window title
            [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
            static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

            // Get the process id for the window
            [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
            static extern int GetWindowThreadProcessId(IntPtr hWnd, out int ProcessId);

            // Open a process
            [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
            static extern int OpenProcess(int dwDesiredAccess, bool bInheritHandle, int dwProcessId);

            // Get the process path for a window
            [DllImport("psapi.dll", CharSet = CharSet.Auto, SetLastError = true)]
            static extern int GetModuleFileNameEx(IntPtr hProcess, IntPtr hModule, StringBuilder lpFilename, int nSize);


            private static bool Callback(int hWnd, int lparam) {
                int processId;
                StringBuilder sb1 = new StringBuilder(1024);
                StringBuilder sb2 = new StringBuilder(1024);

                int getIdResult         = GetWindowThreadProcessId((IntPtr)hWnd, out processId);
                int getWindowTextResult = GetWindowText((IntPtr)hWnd, sb1, 1024);
                int openProcessResult   = OpenProcess((PROCESS_QUERY_INFORMATION+PROCESS_VM_READ), true, processId);
                int getFileNameResult   = GetModuleFileNameEx((IntPtr)openProcessResult, IntPtr.Zero, sb2, 1024);

                _WinStructList.Add(new WinStruct { MainWindowHandle = hWnd, WinTitle = sb1.ToString(), ProcessPath = sb2.ToString(), ProcessId = processId });
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



# The definition to send a message to a process
$SendMessageDefinition = @'
    using System;
    using System.Runtime.InteropServices;

    public static class SendMessageClass {
        // Values for Msg
        public static uint WM_SETFOCUS             = 0x0007;    // Set focus command
        public static uint WM_CLOSE                = 0x0010;    // Close command
        public static uint WM_SYSCOMMAND           = 0x0112;    // Initiate a system command (minimize, maximize, etc)
        public static uint WM_SYSCHAR              = 0x0106;    // Send a system character. This is a bit confusing
        public static uint WM_SYSKEYDOWN           = 0x0104;    // System key down
        public static uint WM_SYSKEYUP             = 0x0105;    // System key up
        public static uint KEY_DOWN                = 0x0100;    // Key down
        public static uint KEY_UP                  = 0x0101;    // Key up
        public static uint VM_CHAR                 = 0x0102;    // Send a keyboard character (see below)
        public static uint LBUTTONDOWN             = 0x0201;    // Left mouse button down
        public static uint LBUTTONUP               = 0x0202;    // Left mouse button up

        // This needs to be send to a button child "window" handle
        public static uint BM_CLICK                = 0x00F5;    // Mouse click on a button

        // Values for wParam
        public static uint KEY_A                   = 0x0041;    // A
        public static uint KEY_D                   = 0x0044;    // D
        public static uint KEY_E                   = 0x0045;    // E
        public static uint KEY_S                   = 0x0053;    // S
        public static uint KEY_T                   = 0x0054;    // T
        public static uint KEY_MENU                = 0x0012;    // ALT Key

        // To be used in conjunction with WM_SYSCOMMAND
        public static uint SC_CLOSE                = 0xF060;    // Close command
        public static uint SC_MINIMIZE             = 0xF020;    // Minimize command
        public static uint SC_RESTORE              = 0xF120;    // Restore window command

        // Values for calculating lParam
        public static uint MAPVK_VK_TO_VSC         = 0x0000;
        public static uint MAPVK_VSC_TO_VK         = 0x0001;
        public static uint MAPVK_VK_TO_CHAR        = 0x0002;
        public static uint MAPVK_VSC_TO_VK_EX      = 0x0003;
        public static uint MAPVK_VK_TO_VSC_EX      = 0x0004;

        // Values for the "fuFlags" parameter in SendMessageTimeout
        public static uint SMTO_ABORTIFHUNG        = 0x0002;    // The function returns without waiting for the time-out period to elapse if the receiving thread appears to not respond or "hangs."
        public static uint SMTO_BLOCK              = 0x0001;    // Prevents the calling thread from processing any other requests until the function returns.
        public static uint SMTO_NORMAL             = 0x0000;    // The calling thread is not prevented from processing other requests while waiting for the function to return.
        public static uint SMTO_NOTIMEOUTIFNOTHUNG = 0x0008;    // The function does not enforce the time-out period as long as the receiving thread is processing messages.
        public static uint SMTO_ERRORONEXIT        = 0x0020;    // The function should return 0 if the receiving window is destroyed or its owning thread dies while the message is being processed.


        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = false)]
        public static extern uint MapVirtualKey(uint uCode, uint uMapType);

        public static uint GetLParam(Int16 repeatCount, uint key, byte extended, byte contextCode, byte previousState, byte transitionState) {
            var lParam = (uint) repeatCount;
            uint scanCode = MapVirtualKey(key, MAPVK_VK_TO_CHAR);

            lParam += scanCode*0x10000;
            lParam += (uint) ((extended)*0x1000000);
            lParam += (uint) ((contextCode*2)*0x10000000);
            lParam += (uint) ((previousState*4)*0x10000000);
            lParam += (uint) ((transitionState*8)*0x10000000);

            return lParam;
        }

        // SendMessage. Seems to return always 0
        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = false)]
        public static extern IntPtr SendMessage(IntPtr hWnd, UInt32 Msg, IntPtr wParam, IntPtr lParam);

        // PostMessage. Seems to return always 1
        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = false)]
        public static extern IntPtr PostMessage(IntPtr hWnd, UInt32 Msg, IntPtr wParam, IntPtr lParam);

        // SendMessageTimeout
        // The "lParam" parameter is trobulesome, if set to anything but "string" it crashes
        // But it also crashes if set to "string" and WM_CLOSE is being sent
        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern IntPtr SendMessageTimeout(IntPtr hWnd, UInt32 Msg, IntPtr wParam, string lParam, IntPtr fuFlags, UInt32 uTimeout);
    }
'@


# Defintions for the the API functions to suspend and resume a process with the Debug method
$SetSuspendAndResumeWithDebugDefinition = @'
    using System;
    using System.Runtime.InteropServices;

    public class SuspendProcessWithDebug
    {
        // Suspends a process using the Debug method
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool DebugActiveProcess(IntPtr processId);


        // Resumes a process using the Debug method
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool DebugActiveProcessStop(IntPtr processId);


        // Retrieves the calling thread's last-error code value
        [DllImport("kernel32.dll")]
        public static extern uint GetLastError();


        // Formats a message string
        [DllImport("kernel32.dll", CharSet = CharSet.Auto)]
        public static extern uint FormatMessage(uint dwFlags, IntPtr lpSource, uint dwMessageId, uint dwLanguageId, ref IntPtr lpBuffer, uint nSize, IntPtr Arguments);
    }
'@



# Define the necessary API functions and structures to handle individual threads of a process
# This can also set the affinity for different Processor Groups if the total amount of logical processors is larger than 64
$SetThreadHandlerDefinition = @'
    using System;
    using System.Runtime.InteropServices;

    public class ThreadHandler
    {
        public const int PROCESS_ALL_ACCESS        = 0x1F0FFF;
        public const int PROCESS_QUERY_INFORMATION = 0x0400;
        public const int PROCESS_SET_INFORMATION   = 0x0200;
        public const int THREAD_QUERY_INFORMATION  = 0x0040;
        public const int THREAD_SET_INFORMATION    = 0x0020;
        public const int THREAD_SUSPEND_RESUME     = 0x0002;

        [StructLayout(LayoutKind.Sequential)]
        public struct GROUP_AFFINITY
        {
            public ulong Mask;
            public ushort Group;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 3)]
            public ushort[] Reserved;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct PROCESSOR_NUMBER
        {
            public ushort Group;
            public byte Number;
            public byte Reserved;
        }


        // Retrieves the processor group affinity of the specified process
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool GetProcessGroupAffinity(IntPtr hProcess, ref ushort GroupCount, [Out] ushort[] GroupArray);


        // Retrieves the processor group affinity of the specified thread
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool GetThreadGroupAffinity(IntPtr hThread, ref GROUP_AFFINITY GroupAffinity);


        // Sets the processor group affinity for the specified thread
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool SetThreadGroupAffinity(IntPtr hThread, ref GROUP_AFFINITY GroupAffinity, IntPtr PreviousGroupAffinity);


        // Sets a processor affinity mask for the threads of the specified process
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool SetProcessAffinityMask(IntPtr hProcess, UIntPtr dwProcessAffinityMask);


        // Opens an existing local process object
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr OpenProcess(int dwDesiredAccess, bool bInheritHandle, int dwProcessId);


        // Opens an existing thread object
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr OpenThread(int dwDesiredAccess, bool bInheritHandle, int dwThreadId);


        // Closes an open object handle
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool CloseHandle(IntPtr hObject);


        // Suspend a thread
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern int SuspendThread(IntPtr hThread);


        // Resume a thread
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern int ResumeThread(IntPtr hThread);


        // Retrieves the calling thread's last-error code value
        [DllImport("kernel32.dll")]
        public static extern uint GetLastError();


        // Formats a message string
        [DllImport("kernel32.dll", CharSet = CharSet.Auto)]
        public static extern uint FormatMessage(uint dwFlags, IntPtr lpSource, uint dwMessageId, uint dwLanguageId, ref IntPtr lpBuffer, uint nSize, IntPtr Arguments);
    }
'@


# Definition to make a window flash in the taskbar
$WindowFlashDefinition = @'
    using System;
    using System.Collections.Generic;
    using System.Linq;
    using System.Text;
    using System.Runtime.InteropServices;

    public class Window
    {
        [StructLayout(LayoutKind.Sequential)]
        public struct FLASHWINFO
        {
            public UInt32 cbSize;
            public IntPtr hwnd;
            public UInt32 dwFlags;
            public UInt32 uCount;
            public UInt32 dwTimeout;
        }

        // Stop flashing. The system restores the window to its original state.
        const UInt32 FLASHW_STOP = 0;
        // Flash the window caption.
        const UInt32 FLASHW_CAPTION = 1;
        // Flash the taskbar button.
        const UInt32 FLASHW_TRAY = 2;
        // Flash both the window caption and taskbar button.
        // This is equivalent to setting the FLASHW_CAPTION | FLASHW_TRAY flags.
        const UInt32 FLASHW_ALL = 3;
        // Flash continuously, until the FLASHW_STOP flag is set.
        const UInt32 FLASHW_TIMER = 4;
        // Flash continuously until the window comes to the foreground.
        const UInt32 FLASHW_TIMERNOFG = 12;


        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool FlashWindowEx(ref FLASHWINFO pwfi);

        public static bool FlashWindow(IntPtr handle, UInt32 timeout, UInt32 count)
        {
            IntPtr hWnd = handle;
            FLASHWINFO fInfo = new FLASHWINFO();

            fInfo.cbSize = Convert.ToUInt32(Marshal.SizeOf(fInfo));
            fInfo.hwnd = hWnd;
            fInfo.dwFlags = FLASHW_ALL | FLASHW_TIMERNOFG;
            fInfo.uCount = count;
            fInfo.dwTimeout = timeout;

            return FlashWindowEx(ref fInfo);
        }
    }
'@


# Definition to disable the close button on the console window
# Only works if run in a separate window, not within Windows Terminal
$ConsoleWindowMenuDefinition = @'
    using System;
    using System.Runtime.InteropServices;

    public class ConsoleWindowMenu {
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr GetConsoleWindow();

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr GetSystemMenu(IntPtr hWnd, bool bRevert);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool DeleteMenu(IntPtr hMenu, uint uPosition, uint uFlags);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool AppendMenu(IntPtr hMenu, uint uFlags, uint uIDNewItem, string lpNewItem);

        public const uint MF_BYCOMMAND = 0x00000000;
        public const uint MF_STRING    = 0x00000000;
        public const uint SC_CLOSE     = 0xF060;
        public const uint MF_ENABLED   = 0x00000000;
        public const uint MF_DISABLED  = 0x00000001;
    }
'@


# Definition to change the console mode for terminal windows
# Used to disable the "QuickEdit Mode" feature
# This works only for a cmd window, but that's fine, since within Windows Terminal marking text doesn't stop the script execution
# Sources: https://mazeez.dev/posts/quick-edit-mode
#          https://github.com/rprichard/winpty/blob/master/misc/ConinMode.ps1
$ChangeConsoleModeDefinition = @'
    using System;
    using System.Runtime.InteropServices;

    public class ChangeConsoleMode {
        public const int STD_INPUT_HANDLE = -10;             // The standard input device. Initially, this is the console input buffer, CONIN$


        // The various mode bitmask variables
        public const uint ENABLE_PROCESSED_INPUT = 0x0001;
        public const uint ENABLE_LINE_INPUT      = 0x0002;
        public const uint ENABLE_ECHO_INPUT      = 0x0004;
        public const uint ENABLE_MOUSE_INPUT     = 0x0010;
        public const uint ENABLE_INSERT_MODE     = 0x0020;
        public const uint ENABLE_QUICK_EDIT_MODE = 0x0040;   // To enable this mode, use ENABLE_QUICK_EDIT_MODE | ENABLE_EXTENDED_FLAGS
        public const uint ENABLE_EXTENDED_FLAGS  = 0x0080;   // Calling only this disables the QuickEdit Mode
        public const uint ENABLE_AUTO_POSITION   = 0x0100;


        // We need to get the handle for the console output, not the console window or main window handle
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr GetStdHandle(int nStdHandle);


        // This gets the current console mode
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);


        // This sets the new mode
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);


        // Get the current mode
        public static uint GetMode()
        {
            // The handle to our console
            IntPtr handle = GetStdHandle(STD_INPUT_HANDLE);

            uint currentMode;

            GetConsoleMode(handle, out currentMode);
            return currentMode;
        }


        // Set a specific mode
        public static bool SetMode(uint modeToSet)
        {
            // The handle to our console
            IntPtr handle = GetStdHandle(STD_INPUT_HANDLE);

            return SetConsoleMode(handle, modeToSet);
        }


        // Disable the QuickEdit Mode
        public static bool DisableQuickEdit()
        {
            // Quick Edit mode freezes the app to let users select text
            // We don't want that. We want the app to run smoothly in the background
            // - https://stackoverflow.com/q/4453692
            // - https://stackoverflow.com/a/4453779
            // - https://stackoverflow.com/a/30517482


            // The handle to our console
            IntPtr handle = GetStdHandle(STD_INPUT_HANDLE);


            // Get the previous (current) console mode
            uint previousMode;
            GetConsoleMode(handle, out previousMode);


            // Set the mode, but without the flag to enable the quick edit
            return SetConsoleMode(handle, previousMode & ~ENABLE_QUICK_EDIT_MODE);
        }


        // Enable the QuickEdit Mode
        public static bool EnableQuickEdit()
        {
            // The handle to our console
            IntPtr handle = GetStdHandle(STD_INPUT_HANDLE);


            // Get the previous (current) console mode
            uint previousMode;
            GetConsoleMode(handle, out previousMode);


            // Set the mode with the flag to enable the quick edit
            return SetConsoleMode(handle, previousMode | ENABLE_QUICK_EDIT_MODE);
        }
    }
'@



# Definition to flush the registry to the disk
# Used to make sure that the Automatic Test Mode scheduled task can be correctly executed on the next boot
# Sources: https://gist.github.com/ryanries/4dd567d08e2eace9683ffef67e20028e
#          https://blog.coursemonster.com/registry-monitor-for-powershell
#          https://github.com/PowerShell/PowerShell/blob/master/src/System.Management.Automation/namespaces/TransactedRegistryKey.cs
#          https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regflushkey
$RegistryFlusherDefinition = @'
    using System;
    using System.Runtime.InteropServices;

    public class RegistryFlusher {
        [DllImport("Advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern int RegOpenKeyExW(int hKey, string lpSubKey, int ulOptions, uint samDesired, out IntPtr phkResult);

        [DllImport("Advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern int RegCloseKey(IntPtr hKey);

        [DllImport("Advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern int RegFlushKey(IntPtr hKey);
    }
'@


# Make the external code definitions available to PowerShell
Add-Type -ErrorAction Stop -Name PowerUtil -Namespace Windows -MemberDefinition $PowerUtilDefinition
Add-Type -ErrorAction Stop -TypeDefinition $ShutdownBlockDefinition
Add-Type -ErrorAction Stop -TypeDefinition $GetWindowsDefinition
Add-Type -ErrorAction Stop -TypeDefinition $WindowFlashDefinition
Add-Type -ErrorAction Stop -TypeDefinition $ConsoleWindowMenuDefinition
Add-Type -ErrorAction Stop -TypeDefinition $ChangeConsoleModeDefinition
Add-Type -ErrorAction Stop -TypeDefinition $SetThreadHandlerDefinition
Add-Type -ErrorAction Stop -TypeDefinition $SetSuspendAndResumeWithDebugDefinition
Add-Type -ErrorAction Stop -TypeDefinition $RegistryFlusherDefinition
$SendMessage = Add-Type -ErrorAction Stop -TypeDefinition $SendMessageDefinition -PassThru


# Also make VisualBasic available
Add-Type -Assembly Microsoft.VisualBasic




<#
.DESCRIPTION
    Helper function to get the current line number
.OUTPUTS
    [Int] The current line number where the function was called from
#>
function Get-ScriptLineNumber {
    return $MyInvocation.ScriptLineNumber
}



<#
.DESCRIPTION
    Write a string to the log file
.PARAMETER string
    [String] The string to log
.PARAMETER NoNewline
    [Switch] (optional) If set, will not end the line after the text
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
    $stream = [System.IO.StreamWriter]::new($logFileFullPath, $true, ([System.Text.Utf8Encoding]::new()))

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
    Write an error message to the screen and to the log file
.PARAMETER errorArray
    [Array] An array with the text entries to output
.OUTPUTS
    [Void]
#>
function Write-ErrorText {
    param(
        [Parameter(Mandatory=$true)] $errorArray
    )

    foreach ($entry in $errorArray) {
        $lines  = @()
        $lines += $entry.Exception.Message
        $lines += $entry.InvocationInfo.PositionMessage
        $lines += ('    + CategoryInfo          : ' + $entry.CategoryInfo.Category + ': (' + $entry.CategoryInfo.TargetName + ':' + $entry.CategoryInfo.TargetType + ') [' + $entry.CategoryInfo.Activity + '], ' + $entry.CategoryInfo.Reason)
        $lines += ('    + FullyQualifiedErrorId : ' + $entry.FullyQualifiedErrorId)
        $string = $lines | Out-String

        Write-Host $string -ForegroundColor Red
        Write-LogEntry $string
    }
}



<#
.DESCRIPTION
    Write a message to the screen with a specific color and to the log file
.PARAMETER text
    [String] The text to output
.PARAMETER foregroundColor
    [String] The foreground color
.PARAMETER backgroundColor
    [String] (optional) The background color
.PARAMETER NoNewline
    [Switch] (optional) If set, will not end the line after the text
.OUTPUTS
    [Void]
#>
function Write-ColorText {
    param(
        [Parameter(Mandatory=$true)] $text,
        [Parameter(Mandatory=$true)] $foregroundColor,
        [Parameter(Mandatory=$false)] $backgroundColor,
        [Parameter(Mandatory=$false)] [Switch] $NoNewline
    )

    $paramsLog = @{
        'string'    = $text
        'NoNewline' = $NoNewline.IsPresent
    }

    $paramsText = @{
        'Object'          = $paramsLog['string']
        'NoNewline'       = $paramsLog['NoNewline']
        'ForegroundColor' = $foregroundColor
    }

    # -ForegroundColor <ConsoleColor>
    # -BackgroundColor <ConsoleColor>
    # Black, DarkBlue, DarkGreen, DarkCyan, DarkRed, DarkMagenta, DarkYellow, Gray, DarkGray, Blue, Green, Cyan, Red, Magenta, Yellow, White
    if ($backgroundColor) {
        $paramsText['BackgroundColor'] = $backgroundColor
    }

    Write-Host @paramsText
    Write-LogEntry @paramsLog
}



<#
.DESCRIPTION
    Write a verbose message to the screen and to the log file
    Verbose output
.PARAMETER text
    [String] The text to output
.PARAMETER NoNewline
    [Switch] (optional) If set, will not end the line after the text
.PARAMETER SkipIndentation
    [Switch] (optional) If set, will not add indentation to the text. Best used in combination with -NoNewline
.OUTPUTS
    [Void]
#>
function Write-VerboseText {
    param(
        [Parameter(Mandatory=$true)] $text,
        [Parameter(Mandatory=$false)] [Switch] $NoNewline,
        [Parameter(Mandatory=$false)] [Switch] $SkipIndentation
    )

    $string = $(if ($SkipIndentation.IsPresent) { $text } else { ''.PadLeft(14, ' ') + '+   ' + $text })

    $paramsLog = @{
        'string'    = $string
        'NoNewline' = $NoNewline.IsPresent
    }

    $paramsText = @{
        'Object'          = $paramsLog['string']
        'NoNewline'       = $paramsLog['NoNewline']
        'ForegroundColor' = 'DarkGray'
    }


    if ($logLevel -ge 1) {
        if ($logLevel -ge 3) {
            Write-Host @paramsText
        }

        Write-LogEntry @paramsLog
    }
}



<#
.DESCRIPTION
    Write a debug message to the screen and to the log file
    Debug output
.PARAMETER text
    [String] The text to output
.PARAMETER NoNewline
    [Switch] (optional) If set, will not end the line after the text
.PARAMETER SkipIndentation
    [Switch] (optional) If set, will not add indentation to the text. Best used in combination with -NoNewline
.OUTPUTS
    [Void]
#>
function Write-DebugText {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '')]

    param(
        [Parameter(Mandatory=$true)] $text,
        [Parameter(Mandatory=$false)] [Switch] $NoNewline,
        [Parameter(Mandatory=$false)] [Switch] $SkipIndentation
    )

    $string = $(if ($SkipIndentation.IsPresent) { $text } else { ''.PadLeft(14, ' ') + '+++ ' + $text })

    $paramsLog = @{
        'string'    = $string
        'NoNewline' = $NoNewline.IsPresent
    }

    $paramsText = @{
        'Object'          = $paramsLog['string']
        'NoNewline'       = $paramsLog['NoNewline']
        'ForegroundColor' = 'DarkGray'
    }

    if ($logLevel -ge 2) {
        if ($logLevel -ge 4) {
            Write-Host @paramsText
        }

        Write-LogEntry @paramsLog
    }
}



<#
.DESCRIPTION
    Exit the script
.PARAMETER text
    [String] (optional) The text to display
.OUTPUTS
    [Void]
#>
function Exit-Script {
    param(
        [Parameter(Mandatory=$false)] $text
    )

    $Script:scriptExit = $true

    if ($text) {
        Write-Text($text)
    }

    exit
}



<#
.DESCRIPTION
    Throw a fatal error and exit the script
.PARAMETER text
    [String] (optional) The text to display
.PARAMETER lineNumber
    [Int] (optional) The line number where this was called from
.OUTPUTS
    [Void]
#>
function Exit-WithFatalError {
    param(
        [Parameter(Mandatory=$false)] $text,
        [Parameter(Mandatory=$false)] $lineNumber
    )

    $Script:fatalError = $true


    if ($text) {
        Write-ColorText('FATAL ERROR: ' + $text) Red
    }

    if ($lineNumber) {
        Write-Host('Line Number: ' + $lineNumber)
    }

    # Remove the .automode file if it exists
    Remove-AutoModeFile


    Write-Host
    Write-Host
    Write-Host 'You can find more information in the log file:' -ForegroundColor Yellow
    Write-Host $logFileFullPath -ForegroundColor Cyan
    Write-Host 'When reporting this error, please provide this log file.' -ForegroundColor Yellow

    Read-Host -Prompt 'Press Enter to exit'
    exit
}



<#
.DESCRIPTION
    Check if the Visual C++ Redistributable package is installed
.OUTPUTS
    [Bool]
#>
function Test-IsVisualCInstalled {
    $found = $false
    $regKeyEntries = Get-ChildItem 'HKLM:\SOFTWARE\WoW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'

    foreach ($entry in $regKeyEntries) {
        $displayName = $entry.GetValue('DisplayName')

        if ($displayName -match '^Microsoft Visual C\+\+\D*(?<Year>(\d|-){4,9}).*Redistributable.*') {
            $versionString = $entry.GetValue('DisplayVersion')
            $versionArr = $versionString -Split '\.'

            # At least version 14 I guess
            # We may need to ask for more specific sub versions
            if ($versionArr[0] -Match '^[\d\.]+$' -and [Int] $versionArr[0] -ge 14) {
                $found = $true
                break
            }
        }
    }

    return $found
}



<#
.DESCRIPTION
    Check if the .NET 8 is installed
.OUTPUTS
    [Bool]
#>
function Test-IsDotNetInstalled {
    $found = $false
    $hasDotNetExe = Get-Command 'dotnet' -ErrorAction Ignore

    if (!$hasDotNetExe) {
        return $false
    }

    $installedVersions = Get-ChildItem $hasDotNetExe.Path.Replace('dotnet.exe', 'shared\Microsoft.NETCore.App') -ErrorAction Ignore | ForEach-Object {
        $_.Name
    }

    foreach ($versionString in $installedVersions) {
        $versionArr = $versionString -Split '\.'

        if ($versionArr[0] -Match '^[\d\.]+$' -and [Int] $versionArr[0] -ge 8) {
            $found = $true
            break
        }
    }

    return $found
}



<#
.DESCRIPTION
    Get a value in bytes from a string value
    The string may contain "tb", "gb", "mb", "kb" and/or "b" as an abbreviation (SI notation, multiplier 1000)
    It can also contain "tib", "gib", "mib" and "kib" (multiplier 1024)
.PARAMETER string
    [String] The string to convert
.OUTPUTS
    [UInt64] The string converted to bytes
#>
function Get-ByteValueFromString {
    param(
        [Parameter(Mandatory=$true)] [String] $string
    )

    [UInt64] $finalValue = 0
    $null = $string -Match '(?-i)((?<tb>\d+(\.\d+)*)\s*tb)*\s*((?<gb>\d+(\.\d+)*)\s*gb)*\s*((?<mb>\d+(\.\d+)*)\s*mb)*\s*((?<kb>\d+(\.\d+)*)\s*kb)*\s*((?<tib>\d+(\.\d+)*)\s*tib)*\s*((?<gib>\d+(\.\d+)*)\s*gib)*\s*((?<mib>\d+(\.\d+)*)\s*mib)*\s*((?<kib>\d+(\.\d+)*)\s*kib)*\s*((?<b>\d+(\.\d+)*)\s*b)*'

    Write-DebugText('Convert to bytes from string:        ' + $string)

    # Is it using the short notation, or is it a raw value?
    $isShortNotation = ($Matches['tb'] -or $Matches['gb'] -or $Matches['mb'] -or $Matches['kb'] -or $Matches['tib'] -or $Matches['gib'] -or $Matches['mib'] -or $Matches['kib'] -or $Matches['b'])

    # Parse the values
    if ($isShortNotation) {
        [UInt64] $byteValueSi  = [UInt64] $Matches['tb']  * [Math]::Pow(1000, 4) + [UInt64] $Matches['gb']  * [Math]::Pow(1000, 3) + [UInt64] $Matches['mb']  * [Math]::Pow(1000, 2) + [UInt64] $Matches['kb']  * 1000
        [UInt64] $byteValueIec = [UInt64] $Matches['tib'] * [Math]::Pow(1024, 4) + [UInt64] $Matches['gib'] * [Math]::Pow(1024, 3) + [UInt64] $Matches['mib'] * [Math]::Pow(1024, 2) + [UInt64] $Matches['kib'] * 1024
        [UInt64] $byteValue    = [UInt64] $Matches['b']
        [UInt64] $finalValue   = $byteValueSi + $byteValueIec + $byteValue

        Write-DebugText('Byte value from SI notation  (1000): ' + $byteValueSi)
        Write-DebugText('Byte value from IEC notation (1024): ' + $byteValueIec)
        Write-DebugText('Single byte value:                   ' + $byteValue)
    }

    # No short notation, treat it as a raw byte value
    else {
        $null = $string -Match '\d+'

        if ($Matches[0]) {
            [UInt64] $finalValue = $Matches[0]
        }
    }

    Write-DebugText('Converted to final byte value:       ' + $finalValue)

    return $finalValue
}



<#
.DESCRIPTION
    Get the problem size value for Linpack
    Problem size = sqrt(memory in bytes / 8), ceiled to the next integer
    Apparently the problem size does not need to be divisible by 8, 16, or 32:
    http://web.archive.org/web/20240725212018/https://community.intel.com/t5/Intel-oneAPI-Math-Kernel-Library/Linpack-Correctly-calculate-the-number-of-equations-problem-size/m-p/1617218/highlight/true#M36293
.PARAMETER memoryBytes
    [UInt64] The memory in bytes
.PARAMETER usesAvx
    [Bool] Uses different formulas depending on AVX or not
.OUTPUTS
    [UInt64] The problem size
#>
function Get-LinpackProblemSize {
    param(
        [Parameter(Mandatory=$true)] [UInt64] $memoryBytes,
        [Parameter(Mandatory=$true)] [Bool] $usesAvx
    )

    # Only full integers
    [UInt64] $problemSize = [Math]::Floor([Math]::Sqrt($memory / 8))

    return $problemSize
}



<#
.DESCRIPTION
    Get a value for the leading dimension size (LDA parameter) for Linpack
    It's advised to select the next larger integer value that is divisble by 8 (apparently "odd" multiple, see below)
    From the xhelp.lpk file:
    The leading dimension must be no less than the number of equations. Experience has shown that the best performance for a given problem size
    is obtained when the leading dimension is set to the nearest odd multiple of 8 (16 for Intel(R) AVX processors) equal to or larger
    than the number of equations (divisible by 8 but not by 16, or divisible by 16 but not 32 for Intel(R) AVX processors).
    https://stackoverflow.com/questions/49345420/understanding-linpack-input-configuration
    Also here:
    http://web.archive.org/web/20240725212018/https://community.intel.com/t5/Intel-oneAPI-Math-Kernel-Library/Linpack-Correctly-calculate-the-number-of-equations-problem-size/m-p/1617218/highlight/true#M36293
.PARAMETER problemSize
    [UInt64] The problem size
.PARAMETER usesAvx
    [Bool] If set, use a different formula to determine the leading dimension value
.OUTPUTS
    [UInt64] The leading dimension value
#>
function Get-LinpackLeadingDimensionValue {
    param(
        [Parameter(Mandatory=$true)] [UInt64] $problemSize,
        [Parameter(Mandatory=$true)] [Bool] $usesAvx
    )

    # Uses no AVX: the nearest odd multiple of 8, divisible by 8 but not by 16
    # Uses AVX:    the nearest odd multiple of 16, divisible by 16 but not 32
    $divisorShouldMatch    = $(if ($usesAvx) { 16 } else { 8 })
    $divisorShouldNotMatch = $(if ($usesAvx) { 32 } else { 16 })


    # The leading dimension should be divisible by 8 or 16 (the problem size doesn't need to)
    [UInt64] $leadingDimensionSize = [Math]::Ceiling($problemSize / $divisorShouldMatch) * $divisorShouldMatch

    Write-DebugText('Problem size:                ' + $problemSize)
    Write-DebugText('Use AVX:                     ' + $usesAvx)

    while ($true) {
        Write-DebugText('Checking leading dimension:  ' + $leadingDimensionSize) -NoNewline
        Write-DebugText(' ║ % ' + $divisorShouldMatch    + ' == 0: ' + ($leadingDimensionSize % $divisorShouldMatch -eq 0).ToString().PadRight(5, ' ')    + (' (' + ($leadingDimensionSize % $divisorShouldMatch)    + ')').PadLeft(5, ' ')) -NoNewline -SkipIndentation
        Write-DebugText(' ║ % ' + $divisorShouldNotMatch + ' != 0: ' + ($leadingDimensionSize % $divisorShouldNotMatch -ne 0).ToString().PadRight(5, ' ') + (' (' + ($leadingDimensionSize % $divisorShouldNotMatch) + ')').PadLeft(5, ' ')) -SkipIndentation

        if ($leadingDimensionSize % $divisorShouldMatch -eq 0 -and $leadingDimensionSize % $divisorShouldNotMatch -ne 0) {
            Write-DebugText('The final leading dimension: ' + $leadingDimensionSize)
            return $leadingDimensionSize
        }

        $leadingDimensionSize = $leadingDimensionSize + 1
    }
}



<#
.DESCRIPTION
    Final summary when exiting the script
.PARAMETER ReturnText
    [Switch] (optional) If set, will only return a the text, not using the Write-X functions
.OUTPUTS
    [Void] or [String]
#>
function Show-FinalSummary {
    param(
        [Parameter(Mandatory=$false)] [Switch] $ReturnText
    )

    # Get the total runtime
    $scriptEndDate   = Get-Date
    $differenceTotal = New-TimeSpan -Start $scriptStartDate -End $scriptEndDate
    $runtimeArray    = @()

    if ($differenceTotal.Days -gt 0) {
        $runtimeArray += ($differenceTotal.Days.ToString() + ' days')
    }
    if ($differenceTotal.Hours -gt 0) {
        $runtimeArray += ($differenceTotal.Hours.ToString().PadLeft(2, '0') + ' hours')
    }
    if ($differenceTotal.Minutes -gt 0) {
        $runtimeArray += ($differenceTotal.Minutes.ToString().PadLeft(2, '0') + ' minutes')
    }
    if ($differenceTotal.Seconds -gt 0) {
        $runtimeArray += ($differenceTotal.Seconds.ToString().PadLeft(2, '0') + ' seconds')
    }

    $runTimeString = $runtimeArray -Join ', '

    $testedCoresSorted = @($testedCoresArray.GetEnumerator() | Sort-Object -Property Name | ForEach-Object { 'Core ' + $_.Name.ToString() +' (' + $_.Value.ToString() + 'x)' })
    $testedCoresGroups = [System.Collections.ArrayList]::new()
    $groupSize = 5
    $numTestedCoresGroups = [Math]::Ceiling($testedCoresSorted.Count / $groupSize)

    for ($i = 0; $i -lt $numTestedCoresGroups; $i++) {
        $startKey = $i * $groupSize
        $endKey   = $startKey + $groupSize - 1

        if ($endKey -gt $testedCoresSorted.Count - 1) {
            $endKey = $testedCoresSorted.Count - 1
        }

        [Void] $testedCoresGroups.Add($testedCoresSorted[$startKey..$endKey])
    }

    # Only return the text, do not display it
    if ($ReturnText.IsPresent) {
        $testedCoresString = ($testedCoresGroups | ForEach-Object { $_ -Join ', ' }) -Join [Environment]::NewLine

        $returnString  = [Environment]::NewLine
        $returnString += ('Summary:') + [Environment]::NewLine
        $returnString += ('Run time: ' + $runTimeString) + [Environment]::NewLine
        $returnString += ('Iterations: ' + $startedIterations + ' started / ' + $completedIterations + ' completed') + [Environment]::NewLine
        $returnString += ('Tested cores: ' + $testedCoresArray.Count + ' cores / ' + $numTestedCores + ' tests') + [Environment]::NewLine
        $returnString += ($testedCoresString) + [Environment]::NewLine

        # Display the cores with an error
        if ($numCoresWithError -gt 0) {
            $coresWithErrorString = (($coresWithError | Sort-Object | Get-Unique) -Join ', ')

            if ($numCoresWithError -eq 1) {
                $returnString += ('The following core has thrown an error: ') + [Environment]::NewLine
            }
            else {
                $returnString += ('The following cores have thrown an error: ') + [Environment]::NewLine
            }

            $returnString += (' - ' + $coresWithErrorString) + [Environment]::NewLine
            $returnString += [Environment]::NewLine


            # Extended error information
            $coresWithCollectedErrors = $errorCollector.GetEnumerator() | ForEach-Object { $_.Name } | Sort-Object
            $maxStringLengths = @{
                'core' = 0
                'cpu'  = 0
                'type' = 0
            }

            # Collect the max string lengths for a nicer output
            $coresWithCollectedErrors | ForEach-Object {
                $core = $_
                $coreEntry = $errorCollector[$core]

                $maxStringLengths['core'] = [Math]::Max($maxStringLengths['core'], $core.ToString().Length)

                $coreEntry | ForEach-Object {
                    $maxStringLengths['cpu']  = [Math]::Max($maxStringLengths['cpu'], $_['cpuNumberString'].ToString().Length)
                    $maxStringLengths['type'] = [Math]::Max($maxStringLengths['type'], $_['errorType'].ToString().Length)
                }
            }

            $coresWithCollectedErrors | ForEach-Object {
                $core  = $_
                $coreEntry = $errorCollector[$core]

                $coreEntry | ForEach-Object {
                    $coreString = 'Core ' + ($core.ToString().PadRight($maxStringLengths['core'], ' '))
                    $cpuString  = 'CPU '  + ($_['cpuNumberString'].PadRight($maxStringLengths['cpu'], ' '))

                    $returnString += ($coreString + ' | ' + $cpuString + ' | ' + $_['date'] + ' | ')
                    $returnString += ($_['errorType']) + [Environment]::NewLine
                    $returnString += (' - ' + $_['stressTestError']) + [Environment]::NewLine

                    if ($_['errorMessage'] -and $_['errorMessage'].Length -gt 0) {
                        $returnString += ($_['errorMessage']) + [Environment]::NewLine
                    }
                }

                $returnString += [Environment]::NewLine
            }
        }
        else {
            $returnString += ('No core has thrown an error') + [Environment]::NewLine
        }


        # Display the cores with a WHEA error
        if ($settings.General.lookForWheaErrors -gt 0) {
            if ($numCoresWithWheaError -gt 0) {
                if ($numCoresWithWheaError -eq 1) {
                    $returnString += ('There has been a WHEA error while testing:') + [Environment]::NewLine
                }
                else {
                    $returnString += ('There have been WHEA errors while testing:') + [Environment]::NewLine
                }

                $filteredCoresWithWheaErrors = @($coresWithWheaErrorsCounter.GetEnumerator() | Where-Object { $_.Value -gt 0 })
                $coresWithWheaErrorsCounterString = ($filteredCoresWithWheaErrors.GetEnumerator() | Sort-Object -Property Name | ForEach-Object { 'Core ' + $_.Name.ToString() +' (' + $_.Value.ToString() + 'x)' }) -Join ', '

                $returnString += (' - ' + $coresWithWheaErrorsCounterString) + [Environment]::NewLine
                $returnString += [Environment]::NewLine
                $returnString += ('Note that it is not necessarily the tested core that caused the WHEA error') + [Environment]::NewLine
                $returnString += ('Check the Windows Event Log for more details') + [Environment]::NewLine
            }
            else {
                $returnString += ('No WHEA errors were observed during the test') + [Environment]::NewLine
            }
        }


        # Display the Curve Optimizer values
        if ($useCurveOptimizer) {
            $coCoresString    = ((0..($numPhysCores-1)) | ForEach-Object { ('C' + $_.ToString()).PadLeft(4, ' ') }) -Join ' |'
            $startingCoString = ($voltageStartingValues | ForEach-Object { $_.ToString().PadLeft(4, ' ') }) -Join ' |'
            $currentCoString  = ($voltageCurrentValues | ForEach-Object { $_.ToString().PadLeft(4, ' ') }) -Join ' |'

            if ($numCoresWithIncreasedVoltageValue -gt 0) {
                $returnString += ('There have been adjustments to the Curve Optimizer values:') + [Environment]::NewLine
                $returnString += ('Core            ' + $coCoresString) + [Environment]::NewLine
                $returnString += ('Starting values ' + $startingCoString) + [Environment]::NewLine
                $returnString += ('Current values  ' + $currentCoString) + [Environment]::NewLine
            }
            else {
                $returnString += ('No adjustments to the Curve Optimizer values were necessary') + [Environment]::NewLine
                $returnString += ('Core      ' + $coCoresString) + [Environment]::NewLine
                $returnString += ('CO values ' + $startingCoString) + [Environment]::NewLine
            }
        }

        # Display the Intel voltage offset value
        if ($useIntelVoltageAdjustment) {
            if ($voltageCurrentValues[0] -ne $voltageStartingValues[0]) {
                $returnString += ('There have been adjustments to the voltage offset:') + [Environment]::NewLine
                $returnString += ('Starting value: ' + $voltageStartingValues[0] + 'mv') + [Environment]::NewLine
                $returnString += ('Current value:  ' + $voltageCurrentValues[0]  + 'mv') + [Environment]::NewLine
            }
            else {
                $returnString += ('No adjustments to the voltage offset were necessary') + [Environment]::NewLine
                $returnString += ('Voltage offset: ' + $voltageStartingValues[0] + 'mv') + [Environment]::NewLine
            }
        }

        return $returnString
    }



    # Write the text directly
    $testedCoresString = ($testedCoresGroups | ForEach-Object { '              ' + ($_ -Join ', ') }) -Join [Environment]::NewLine

    Write-Text('')
    Write-ColorText('╔══════════════════════════════════════════════════════════════════════════════╗') Green
    Write-ColorText('╟──────────────────────────────────┤ Summary ├─────────────────────────────────╢') Green
    Write-ColorText('╚══════════════════════════════════════════════════════════════════════════════╝') Green
    Write-Text('')
    Write-ColorText('Run time:     ' + $runTimeString) Cyan
    Write-ColorText('Iterations:   ' + $startedIterations + ' started / ' + $completedIterations + ' completed') Cyan
    Write-ColorText('Tested cores: ' + $testedCoresArray.Count + ' cores / ' + $numTestedCores + ' tests') Cyan
    Write-ColorText($testedCoresString) Cyan
    Write-Text('')
    Write-ColorText('────────────────────────────────────────────────────────────────────────────────') Cyan
    Write-Text('')


    # Display the cores with an error
    if ($numCoresWithError -gt 0) {
        $coresWithErrorString = (($coresWithError | Sort-Object | Get-Unique) -Join ', ')

        if ($numCoresWithError -eq 1) {
            Write-ColorText('The following core has thrown an error: ') Cyan
        }
        else {
            Write-ColorText('The following cores have thrown an error: ') Cyan
        }

        Write-ColorText(' - ' + $coresWithErrorString) Cyan
        Write-Text('')


        # Extended error information
        $coresWithCollectedErrors = $errorCollector.GetEnumerator() | ForEach-Object { $_.Name } | Sort-Object
        $maxStringLengths = @{
            'core' = 0
            'cpu'  = 0
            'type' = 0
        }

        # Collect the max string lengths for a nicer output
        $coresWithCollectedErrors | ForEach-Object {
            $core = $_
            $coreEntry = $errorCollector[$core]

            $maxStringLengths['core'] = [Math]::Max($maxStringLengths['core'], $core.ToString().Length)

            $coreEntry | ForEach-Object {
                $maxStringLengths['cpu']  = [Math]::Max($maxStringLengths['cpu'], $_['cpuNumberString'].ToString().Length)
                $maxStringLengths['type'] = [Math]::Max($maxStringLengths['type'], $_['errorType'].ToString().Length)
            }
        }

        $coresWithCollectedErrors | ForEach-Object {
            $core  = $_
            $coreEntry = $errorCollector[$core]

            $coreEntry | ForEach-Object {
                $coreString = 'Core ' + ($core.ToString().PadRight($maxStringLengths['core'], ' '))
                $cpuString  = 'CPU '  + ($_['cpuNumberString'].PadRight($maxStringLengths['cpu'], ' '))

                Write-ColorText($coreString + ' | ' + $cpuString + ' | ' + $_['date'] + ' | ') Cyan -NoNewline
                Write-ColorText($_['errorType']) Magenta
                Write-ColorText(' - ' + $_['stressTestError']) Cyan

                if ($_['errorMessage'] -and $_['errorMessage'].Length -gt 0) {
                    Write-ColorText('   ' + $_['errorMessage']) Cyan
                }
            }
        }
    }
    else {
        Write-ColorText('No core has thrown an error') Cyan
    }


    # Display the cores with a WHEA error
    if ($settings.General.lookForWheaErrors -gt 0) {
        Write-Text('')

        if ($numCoresWithWheaError -gt 0) {
            if ($numCoresWithWheaError -eq 1) {
                Write-ColorText('There has been a WHEA error while testing: ') Cyan
            }
            else {
                Write-ColorText('There have been WHEA errors while testing: ') Cyan
            }

            $filteredCoresWithWheaErrors = @($coresWithWheaErrorsCounter.GetEnumerator() | Where-Object { $_.Value -gt 0 })
            $coresWithWheaErrorsCounterString = ($filteredCoresWithWheaErrors.GetEnumerator() | Sort-Object -Property Name | ForEach-Object { 'Core ' + $_.Name.ToString() +' (' + $_.Value.ToString() + 'x)' }) -Join ', '

            Write-ColorText(' - ' + $coresWithWheaErrorsCounterString) Cyan
            Write-Text('')
            Write-ColorText('Note that it is not necessarily the tested core that caused the WHEA error') Cyan
            Write-ColorText('Check the Windows Event Log for more details') Cyan
        }
        else {
            Write-ColorText('No WHEA errors were observed during the test') Cyan
        }
    }


    # Display the Curve Optimizer values
    if ($useCurveOptimizer) {
        Write-Text('')
        Write-ColorText('────────────────────────────────────────────────────────────────────────────────') Cyan
        Write-Text('')

        $coCoresString    = ((0..($numPhysCores-1)) | ForEach-Object { ('C' + $_.ToString()).PadLeft(4, ' ') }) -Join ' |'
        $startingCoString = ($voltageStartingValues | ForEach-Object { $_.ToString().PadLeft(4, ' ') }) -Join ' |'
        $currentCoString  = ($voltageCurrentValues | ForEach-Object { $_.ToString().PadLeft(4, ' ') }) -Join ' |'

        if ($numCoresWithIncreasedVoltageValue -gt 0) {
            Write-ColorText('There have been adjustments to the Curve Optimizer values:') Cyan
            Write-ColorText('Core            ' + $coCoresString) Cyan
            Write-ColorText('Starting values ' + $startingCoString) Cyan
            Write-ColorText('Current values  ' + $currentCoString) Cyan
        }
        else {
            Write-ColorText('No adjustments to the Curve Optimizer values were necessary') Cyan
            Write-ColorText('Core      ' + $coCoresString) Cyan
            Write-ColorText('CO values ' + $startingCoString) Cyan
        }
    }

    # Display the Intel voltage offset value
    if ($useIntelVoltageAdjustment) {
        Write-Text('')
        Write-ColorText('────────────────────────────────────────────────────────────────────────────────') Cyan
        Write-Text('')

        if ($voltageCurrentValues[0] -ne $voltageStartingValues[0]) {
            Write-ColorText('There have been adjustments to the voltage offset:') Cyan
            Write-ColorText('Starting value: ' + $voltageStartingValues[0] + 'mv') Cyan
            Write-ColorText('Current value:  ' + $voltageCurrentValues[0]  + 'mv') Cyan
        }
        else {
            Write-ColorText('No adjustments to the voltage offset were necessary') Cyan
            Write-ColorText('Voltage offset: ' + $voltageStartingValues[0] + 'mv') Cyan
        }
    }


    # Display the log file location(s)
    Write-Text('')
    Write-ColorText('────────────────────────────────────────────────────────────────────────────────') Cyan
    Write-Text('')

    $leftStringLength = $(if ($stressTestLogFileName) { [Math]::Max(10, $stressTestPrograms[$settings.General.stressTestProgram]['displayName'].Length) + 5 } else { 15 })

    Write-ColorText('The log files for this run are stored in:') Cyan
    Write-ColorText($logFilePathAbsolute) Cyan
    Write-ColorText((' - CoreCycler:').PadRight($leftStringLength, ' ') + $logFileName) Cyan

    if ($stressTestLogFileName) {
        Write-ColorText((' - ' + $stressTestPrograms[$settings.General.stressTestProgram]['displayName'] + ':').PadRight($leftStringLength, ' ') + $stressTestLogFileName) Cyan
    }

    Write-Text('')
}



<#
.DESCRIPTION
    Get the localized counter name
    Yes, they're localized. Way to go Microsoft!
.PARAMETER ID
    [UInt32] The id of the counter name. See the link above on how to get the IDs
.PARAMETER ComputerName
    [String] The name of the computer to query. Defaults to the current computer
.OUTPUTS
    [String] The localized name
.LINK
    https://www.powershellmagazine.com/2013/07/19/querying-performance-counters-from-powershell/
#>
function Get-PerformanceCounterLocalName {
    param (
        [UInt32] $ID,
        $ComputerName = $env:COMPUTERNAME
    )

    $code  = '[DllImport("pdh.dll", SetLastError=true, CharSet=CharSet.Unicode)] '
    $code += 'public static extern UInt32 PdhLookupPerfNameByIndex(string szMachineName, uint dwNameIndex, System.Text.StringBuilder szNameBuffer, ref uint pcchNameBufferSize);'

    $Buffer = New-Object System.Text.StringBuilder(1024)
    [UInt32] $BufferSize = $Buffer.Capacity

    $type = Add-Type -MemberDefinition $code -PassThru -Name PerfCounter -Namespace Utility
    $queryResult = $type::PdhLookupPerfNameByIndex($ComputerName, $ID, $Buffer, [Ref] $BufferSize)

    # 0 = ERROR_SUCCESS
    if ($queryResult -eq $ERROR_SUCCESS) {
        $Buffer.ToString().Substring(0, $BufferSize-1)
    }
    else {
        throw('Get-PerformanceCounterLocalName : Unable to retrieve localized name. Check computer name and performance counter ID.')
    }
}



<#
.DESCRIPTION
    This is used to get the Performance Counter IDs, which will be used to get the localized names
.PARAMETER englishCounterNames
    [Array] An array with the english names of the counters
.OUTPUTS
    [HashTable] A hashtable with Name:ID pairs of the counters
#>
function Get-PerformanceCounterIDs {
    param (
        [Parameter(Mandatory=$true)] [Array] $englishCounterNames
    )

    $key          = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib\009'
    $allCounters  = (Get-ItemProperty -Path $key -Name Counter).Counter
    $numCounters  = $allCounters.Count
    $countersHash = @{}

    # The string contains two-line pairs
    # The first line is the ID
    # The second line is the name
    # TODO: Maybe make it more robust by actually checking the order of the ID and Text
    for ($i = 0; $i -lt $numCounters; $i += 2) {
        $counterId = [Int] $allCounters[$i]

        if ($counterid -lt 1) {
            continue
        }

        $counterName = [String] $allCounters[$i+1]

        if ($englishCounterNames -contains $counterName -and !$countersHash.ContainsKey($counterName)) {
            $countersHash[$counterName] = $counterId
        }
    }

    return $countersHash
}



<#
.DESCRIPTION
    Suspend a process
.PARAMETER process
    [System.Diagnostics.Process] The process to suspend
.OUTPUTS
    [Mixed] Either the number of suspended threads from this process and -1 if something failed
            Or true/false if used with the debug method
#>
function Suspend-Process {
    param(
        [Parameter(Mandatory=$true)] [System.Diagnostics.Process] $process
    )

    $result = $false

    # The process may have exited in the meantime, silently skip the resume/suspend process if that's the case
    $checkProcess = Get-Process -Id $process.Id -ErrorAction Ignore

    if (!$checkProcess) {
        Write-DebugText('The process to suspend doesn''t exist, skipping')
        return $false
    }


    if ($modeToUseForSuspension -eq 'debugger') {
        $result = Suspend-ProcessWithDebugMethod $process
    }
    elseif ($modeToUseForSuspension -eq 'threads') {
        $result = Suspend-ProcessThreads $process
    }
    else {
        throw('Could not find the suspension method "' + $modeToUseForSuspension + '"!')
    }

    return $result
}



<#
.DESCRIPTION
    Resumes a process
.PARAMETER process
    [System.Diagnostics.Process] The process to resume
.PARAMETER ignoreError
    [Bool] If set, will not throw an error. This may be needed if we want to resume a process that isn't suspended
.OUTPUTS
    [Mixed] Either the number of resumed threads from this process and -1 if something failed
            Or true/false if used with the debug method
#>
function Resume-Process {
    param(
        [Parameter(Mandatory=$true)] [System.Diagnostics.Process] $process,
        [Parameter(Mandatory=$false)] [Bool] $ignoreError
    )

    $result = $false

    # The process may have exited in the meantime, silently skip the resume/suspend process if that's the case
    $checkProcess = Get-Process -Id $process.Id -ErrorAction Ignore

    if (!$checkProcess) {
        Write-DebugText('The process to resume doesn''t exist, skipping')
        return $false
    }


    if ($modeToUseForSuspension -eq 'debugger') {
        $result = Resume-ProcessWithDebugMethod $process $ignoreError
    }
    elseif ($modeToUseForSuspension -eq 'threads') {
        $result = Resume-ProcessThreads $process $ignoreError
    }
    else {
        throw('Could not find the suspension method "' + $modeToUseForSuspension + '"!')
    }

    return $result
}



<#
.DESCRIPTION
    Suspend the threads of a process
.PARAMETER passedProcess
    [System.Diagnostics.Process] The process to suspend
.OUTPUTS
    [Int] The number of suspended threads from this process. -1 if something failed
#>
function Suspend-ProcessThreads {
    param(
        [Parameter(Mandatory=$true)] [System.Diagnostics.Process] $passedProcess
    )

    if (!$passedProcess -or !($passedProcess | Get-Member Threads)) {
        return -2
    }

    Write-VerboseText('Suspending threads for process: ') -NoNewline
    Write-VerboseText($passedProcess.Id.ToString() + ' - ' + $passedProcess.ProcessName.ToString()) -SkipIndentation

    $numThreads = 0
    $suspendCounts = 0
    $openedThreadsArray = @()
    $processedThreadsArray = @()
    $previousSuspendCountArray = @()
    $suspendErrors = @()


    # For some reason the threads don't always seem to be able to read correctly when using the passed process
    # So get it again
    $process = Get-Process -InputObject $passedProcess

    if (!$process -or !($process | Get-Member Threads)) {
        return -3
    }


    Write-DebugText('           ID:') -NoNewline

    $process.Threads | ForEach-Object {
        $currentThreadId = $_.Id

        # See https://docs.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-openthread
        $currentThreadHandle = [ThreadHandler]::OpenThread([ThreadHandler]::THREAD_SUSPEND_RESUME, $false, $currentThreadId)

        if ($currentThreadHandle -eq [IntPtr]::Zero) {
            continue
        }

        $numThreads++
        $openedThreadsArray += $currentThreadId

        #Write-DebugText('  - Suspending thread with id: ' + $currentThreadId) -NoNewline
        Write-DebugText(' - ' + $currentThreadId) -NoNewline -SkipIndentation

        # See https://docs.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-suspendthread
        # Do we also need Wow64SuspendThread?
        # https://docs.microsoft.com/en-us/windows/win32/api/wow64apiset/nf-wow64apiset-wow64suspendthread
        $returnedPreviousSuspendCount = [ThreadHandler]::SuspendThread($currentThreadHandle)
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        [Void] [ThreadHandler]::CloseHandle($currentThreadHandle)

        #Write-DebugText(' ... Returned suspend count was: ' + $returnedPreviousSuspendCount) -NoNewline -SkipIndentation

        # $returnedPreviousSuspendCount should be 0 if the thread is suspended now
        # If it > 0, then there is more than one suspended "state" on the thread. All of these need to be resumed to fully resume the thread/process
        # If it is -1, the operation has failed
        if ($returnedPreviousSuspendCount -ge 0) {
            #Write-DebugText(' ... Thread suspended') -SkipIndentation
            Write-DebugText(' ok') -NoNewline -SkipIndentation
        }

        # We don't care about failed suspend calls at this point, just collect the errors
        if ($returnedPreviousSuspendCount -eq -1) {
            #Write-DebugText(' ... Failed to suspend the thread!') -SkipIndentation
            Write-DebugText(' failed!') -NoNewline -SkipIndentation

            if ($errorCode -gt 0) {
                #Write-DebugText('Error Code: ' + $errorCode + ' - Line: ' + (Get-ScriptLineNumber))
                $errorResult = Get-DotNetErrorMessage $errorCode

                $errorEntry = $errorResult
                $errorEntry['threadId']     = $currentThreadId
                $errorEntry['threadHandle'] = $currentThreadHandle
                $errorEntry['suspendCount'] = $returnedPreviousSuspendCount

                $suspendErrors += $errorResult

                #throw('Failed to suspend thread.' + [Environment]::NewLine + 'Error code: ' + $errorResult['errorCode'] + '. Error message: ' + $errorResult['errorMessage'])
            }
            else {
                $suspendErrors += @{
                    'threadId'     = $currentThreadId
                    'threadHandle' = $currentThreadHandle
                    'suspendCount' = $returnedPreviousSuspendCount
                    'errorCode'    = 0
                    'errorMessage' = 'Failed to suspend thread. No error code was provided'
                }
            }

            #throw('Failed to suspend thread. No error code was provided')
        }

        $processedThreadsArray     += $currentThreadId
        $previousSuspendCountArray += $returnedPreviousSuspendCount

        if ($returnedPreviousSuspendCount -ge 0) {
            $suspendCounts++
        }
    }

    # End the -NoNewline
    Write-DebugText('') -SkipIndentation

    # Write-DebugText('Threads that were opened:     ' + ($openedThreadsArray -Join ', '))
    # Write-DebugText('Threads that were processed:  ' + ($processedThreadsArray -Join ', '))
    # Write-DebugText('Suspend counts (should be 0): ' + ($previousSuspendCountArray -Join ', '))

    # At least one of the threads already had a suspended state
    # if (($previousSuspendCountArray | Measure-Object -Maximum).Maximum -gt 0) {
    #     Write-DebugText('           There was a thread with a previous suspend count larger than 0, which means')
    #     Write-DebugText('           a thread of the process was already suspended (curious, but not an error)')
    # }

    # An error happened, but don't throw
    if ($suspendErrors.Count -gt 0) {
        Write-VerboseText('    There was an error while trying to suspend a thread!')

        $suspendErrors | ForEach-Object {
            Write-VerboseText('    - Thread ID:     ' + $_['threadId'])
            Write-VerboseText('    - Error Code:    ' + $_['errorCode'])
            Write-VerboseText('    - Error Message: ' + $_['errorMessage'])
        }
    }


    if ($suspendCounts -eq $numThreads) {
        return $suspendCounts
    }
    else {
        return -1
    }
}



<#
.DESCRIPTION
    Resumes the suspended threads of a process
.PARAMETER passedProcess
    [System.Diagnostics.Process] The process to resume
.PARAMETER ignoreError
    [Bool] If set, will not throw an error. This may be needed if we want to resume a process that isn't suspended
.OUTPUTS
    [Int] The number of resumed threads from this process. -1 if something failed
#>
function Resume-ProcessThreads {
    param(
        [Parameter(Mandatory=$true)] [System.Diagnostics.Process] $passedProcess,
        [Parameter(Mandatory=$false)] [Bool] $ignoreError
    )

    if (!$passedProcess -or !($passedProcess | Get-Member Threads)) {
        return -2
    }

    Write-VerboseText('Resuming threads for process: ') -NoNewline
    Write-VerboseText($passedProcess.Id.ToString() + ' - ' + $passedProcess.ProcessName.ToString()) -SkipIndentation

    $numThreads = 0
    $resumeCounts = 0
    $openedThreadsArray = @()
    $processedThreadsArray = @()
    $previousSuspendCountArray = @()
    $resumeErrors = @()


    # For some reason the threads don't always seem to be able to read correctly when using the passed process
    # So get it again
    $process = Get-Process -InputObject $passedProcess

    if (!$process -or !($process | Get-Member Threads)) {
        return -3
    }


    Write-DebugText('           ID:') -NoNewline

    $process.Threads | ForEach-Object {
        $currentThreadId = $_.Id

        # See https://docs.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-openthread
        $currentThreadHandle = [ThreadHandler]::OpenThread([ThreadHandler]::THREAD_SUSPEND_RESUME, $false, $currentThreadId)

        if ($currentThreadHandle -eq [IntPtr]::Zero) {
            continue
        }

        $numThreads++
        $openedThreadsArray += $currentThreadId

        #Write-DebugText('  - Resuming thread with id: ' + $currentThreadId) -NoNewline
        Write-DebugText(' - ' + $currentThreadId) -NoNewline -SkipIndentation

        # $returnedPreviousSuspendCount should be 1 if the thread is resumed now
        # If it > 1, then there is more than one suspended "state" on the thread. All of these need to be resumed to fully resume the thread/process
        # If it is -1, the operation has failed
        # Since we only set a single suspend state, we also only remove one
        # Maybe it was set by the stress test program itself, and we don't want to interfere

        # See https://docs.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-resumethread
        $returnedPreviousSuspendCount = [ThreadHandler]::ResumeThread($currentThreadHandle)
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()

        [Void] [ThreadHandler]::CloseHandle($currentThreadHandle)

        #Write-DebugText(' ... Returned suspend count was: ' + $returnedPreviousSuspendCount) -NoNewline -SkipIndentation

        if ($returnedPreviousSuspendCount -gt -1) {
            #Write-DebugText(' ... Thread resumed') -SkipIndentation
            Write-DebugText(' ok') -NoNewline -SkipIndentation
        }

        if (!$ignoreError -and $returnedPreviousSuspendCount -eq -1) {
            #Write-DebugText(' ... Failed to resume the thread!') -SkipIndentation
            Write-DebugText(' failed!') -NoNewline -SkipIndentation

            if ($errorCode -gt 0) {
                #Write-DebugText('Error Code: ' + $errorCode + ' - Line: ' + (Get-ScriptLineNumber))
                $errorResult = Get-DotNetErrorMessage $errorCode

                $errorEntry = $errorResult
                $errorEntry['threadId']     = $currentThreadId
                $errorEntry['threadHandle'] = $currentThreadHandle
                $errorEntry['suspendCount'] = $returnedPreviousSuspendCount

                $resumeErrors += $errorResult

                #throw('Failed to resume thread.' + [Environment]::NewLine + 'Error code: ' + $errorResult.errorCode + '. Error message: ' + $errorResult.errorMessage)
            }
            else {
                $resumeErrors += @{
                    'threadId'     = $currentThreadId
                    'threadHandle' = $currentThreadHandle
                    'suspendCount' = $returnedPreviousSuspendCount
                    'errorCode'    = 0
                    'errorMessage' = 'Failed to resume thread. No error code was provided'
                }
            }

            #throw('Failed to resume thread. No error code was provided.')
        }

        $processedThreadsArray     += $currentThreadHandle
        $previousSuspendCountArray += $returnedPreviousSuspendCount

        # If the previous suspend count is greater than one, the thread had multiple suspend states
        # But we don't care about this, since it was set externally, either by the stress test program, or by the user
        #if ($returnedPreviousSuspendCount -eq 1) {
        if ($returnedPreviousSuspendCount -ge 1) {
            $resumeCounts++
        }
    }

    # End the -NoNewline
    Write-DebugText('') -SkipIndentation


    # Write-DebugText('Threads that were opened:     ' + ($openedThreadsArray -Join ', '))
    # Write-DebugText('Threads that were processed:  ' + ($processedThreadsArray -Join ', '))
    # Write-DebugText('Suspend counts (should be 1): ' + ($previousSuspendCountArray -Join ', '))


    # At least one of the threads already had a suspended state
    # if (($previousSuspendCountArray | Measure-Object -Maximum).Maximum -gt 1) {
    #     Write-DebugText('           There was a thread with a previous suspend count larger than 1, which means')
    #     Write-DebugText('           a thread of the process was already suspended (curious, but not an error)')
    # }

    # An error happened
    if ($resumeErrors.Count -gt 0) {
        Write-VerboseText('    There was an error while trying to resume a thread!')

        $resumeErrors | ForEach-Object {
            Write-VerboseText('    - Thread ID:     ' + $_['threadId'])
            Write-VerboseText('    - Error Code:    ' + $_['errorCode'])
            Write-VerboseText('    - Error Message: ' + $_['errorMessage'])
        }

        # Do we want to exit at this point?
        # Resuming is kind of important...
        throw('Failed to resume thread.' + [Environment]::NewLine + 'Error code: ' + $errorResult[0].errorCode + '. Error message: ' + $errorResult[0].errorMessage)
    }


    if ($resumeCounts -eq $numThreads) {
        return $resumeCounts
    }
    else {
        return -1
    }
}



<#
.DESCRIPTION
    Suspends a process via the DebugActiveProcess method
.PARAMETER process
    [System.Diagnostics.Process] The process to suspend
.OUTPUTS
    [Bool]
#>
function Suspend-ProcessWithDebugMethod {
    param(
        [Parameter(Mandatory=$true)] [System.Diagnostics.Process] $process
    )

    if (!$process) {
        return $false
    }

    $result = [SuspendProcessWithDebug]::DebugActiveProcess($process.Id)
    $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()

    if (!$result) {
        Write-DebugText('Failed to suspend process!')

        if ($errorCode -gt 0) {
            Write-DebugText('Error Code: ' + $errorCode + ' - Line: ' + (Get-ScriptLineNumber))
            $errorResult = Get-DotNetErrorMessage $errorCode

            throw('Failed to suspend process.' + [Environment]::NewLine + 'Error code: ' + $errorResult.errorCode + '. Error message: ' + $errorResult.errorMessage)
        }

        throw('Failed to suspend process. No error code was provided.')
    }

    return $result
}



<#
.DESCRIPTION
    Resumes a suspended process
.PARAMETER process
    [System.Diagnostics.Process] The process to resume
.PARAMETER ignoreError
    [Bool] If set, will not throw an error. This may be needed if we want to resume a process that isn't suspended
.OUTPUTS
    [Bool]
#>
function Resume-ProcessWithDebugMethod {
    param(
        [Parameter(Mandatory=$true)] [System.Diagnostics.Process] $process,
        [Parameter(Mandatory=$false)] [Bool] $ignoreError
    )

    if (!$process) {
        return $false
    }

    $result = [SuspendProcessWithDebug]::DebugActiveProcessStop($process.Id)
    $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()

    if (!$ignoreError -and !$result) {
        Write-DebugText('Failed to resume suspended process!')

        if ($errorCode -gt 0) {
            Write-DebugText('Error Code: ' + $errorCode + ' - Line: ' + (Get-ScriptLineNumber))
            $errorResult = Get-DotNetErrorMessage $errorCode

            throw('Failed to resume suspended process.' + [Environment]::NewLine + 'Error code: ' + $errorResult.errorCode + '. Error message: ' + $errorResult.errorMessage)
        }

        throw('Failed to resume suspended process. No error code was provided.')
    }

    return $result
}



<#
.DESCRIPTION
    Gets the current CPU frequency of a specific core / CPU
.PARAMETER cpuNumber
    [Int] The CPU to query
.OUTPUTS
    [HashTable] The current frequency and percent
.NOTES
    The calculated value does not 100% match the one from HWInfo64 or Ryzen Master, it's a bit lower
    I'm not sure why or if there's any way to fix this
    It's still higher than the one reported by Windows Task Manager though
#>
function Get-CpuFrequency {
    param(
        [Parameter(Mandatory=$true)] [Int] $cpuNumber
    )

    $timestamp1 = Get-Date -Format HH:mm:ss
    Write-DebugText($timestamp1 + ' - Starting Get-CpuFrequency')

    # We need two snapshots to be able to calculate an average over the time passed
    # We could also use a Start-Sleep function call to increase the timespan, without one it seems to be around 10ms
    $snapshot1 = Get-CimInstance -Query ('SELECT * from Win32_PerfRawData_Counters_ProcessorInformation WHERE Name LIKE "0,' + $cpuNumber + '"')
    $snapshot2 = Get-CimInstance -Query ('SELECT * from Win32_PerfRawData_Counters_ProcessorInformation WHERE Name LIKE "0,' + $cpuNumber + '"')

    $ProcessorFrequency                   = $snapshot1.ProcessorFrequency

    $PercentProcessorPerformance1         = $snapshot1.PercentProcessorPerformance
    $PercentProcessorPerformance_Base1    = $snapshot1.PercentProcessorPerformance_Base

    $PercentProcessorPerformance2         = $snapshot2.PercentProcessorPerformance
    $PercentProcessorPerformance_Base2    = $snapshot2.PercentProcessorPerformance_Base

    $PercentProcessorPerformanceDiff      = $PercentProcessorPerformance2 - $PercentProcessorPerformance1
    $PercentProcessorPerformance_BaseDiff = $PercentProcessorPerformance_Base2 - $PercentProcessorPerformance_Base1

    # Error check, if the base values are the same, let's do another query
    for ($i = 0; $i -lt 10; $i++) {
        if ($PercentProcessorPerformanceDiff -lt 1000 -or $PercentProcessorPerformance_BaseDiff -lt 1000) {
            Write-DebugText('The difference in processor performance is too low, repeating the query (' + $i + ')')

            Start-Sleep -Milliseconds 50
            $snapshot2 = Get-CimInstance -Query ('SELECT * from Win32_PerfRawData_Counters_ProcessorInformation WHERE Name LIKE "0,' + $cpuNumber + '"')

            $PercentProcessorPerformance2         = $snapshot2.PercentProcessorPerformance
            $PercentProcessorPerformance_Base2    = $snapshot2.PercentProcessorPerformance_Base

            $PercentProcessorPerformanceDiff      = $PercentProcessorPerformance2 - $PercentProcessorPerformance1
            $PercentProcessorPerformance_BaseDiff = $PercentProcessorPerformance_Base2 - $PercentProcessorPerformance_Base1
        }
    }

    $PercentProcessorPerformance = $PercentProcessorPerformanceDiff / $PercentProcessorPerformance_BaseDiff
    $Frequency                   = $ProcessorFrequency * ($PercentProcessorPerformance / 100)

    $returnObj = @{
        'CurrentFrequency' = [Math]::Round($Frequency, 0)
        'Percent'          = [Math]::Round($PercentProcessorPerformance, 2)
    }

    Write-DebugText('CurrentFrequency: ' + $returnObj.CurrentFrequency)
    Write-DebugText('Percent:          ' + $returnObj.Percent)

    $timestamp2 = Get-Date -Format HH:mm:ss
    Write-DebugText($timestamp2 + ' - Ended Get-CpuFrequency')

    return $returnObj
}



<#
.DESCRIPTION
    Gets the inital log level from the config file
    Will be overwritten by the final config log parsing
.PARAMETER
    [Void]
.OUTPUTS
    [Int] The log level
#>
function Get-InitialLogLevel {
    # Check if the config.ini file exists
    if (!(Test-Path $configUserPath -PathType Leaf)) {
        return $logLevel
    }

    $logLevel = $Script:logLevel
    $configPath = $configUserPath

    $patternCustomConfig = '^useConfigFile\s*=\s*([aA-zZ0-9\.\-_\\:/ ]+)$'
    $patternLogLevel     = '^logLevel\s*=\s*(\d+)$'


    # Check if there's a custom config file being used
    $foundCustomConfigLine = Select-String -Path $configPath -Pattern $patternCustomConfig | Select-Object -Property Line -Last 1

    if ($foundCustomConfigLine) {
        $foundCustomConfigFile = $foundCustomConfigLine.Line -Match '=\s*(.+)'

        if ($foundCustomConfigFile -and $Matches[1]) {
            $configPathTemp = $PSScriptRoot + '\' + $Matches[1].Trim(' ', '"', '''', [Char]0x09)

            if (Test-Path $configPathTemp -PathType Leaf) {
                $configPath = $configPathTemp
            }
        }
    }

    # Check for the logLevel = n string
    $foundLogLevelLine = Select-String -Path $configPath -Pattern $patternLogLevel | Select-Object -Property Line -Last 1

    if ($foundLogLevelLine) {
        $logLevelMatched = $foundLogLevelLine.Line -Match '=\s*(\d+)\s*'

        if ($logLevelMatched -and $Matches[1]) {
            $logLevel = [Int] $Matches[1]
        }
    }

    return $logLevel
}



<#
.DESCRIPTION
    Initiate a job to perform an update check
.PARAMETER updateSettings
    [Hashtable] (optional) The update settings. If not set, uses the $settings.Update hashtable
.OUTPUTS
    [PSRemotingJob Object] The job object
#>
function Start-UpdateCheckBackgroundJob {
    param(
        [Parameter(Mandatory=$false)] $updateSettings
    )

    Write-DebugText('Starting the update check background job')

    if (!$updateSettings) {
        $updateSettings = $settings.Update
    }

    $updateCheckBackgroundJob = Start-Job -Name 'UpdateCheck' -ScriptBlock {
        $startTime = Get-Date
        $messages = [System.Collections.ArrayList] @()

        # Wrap Write-DebugText to add to $messages instead, since we're in a job
        function Write-DebugText {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '')]

            param(
                [Parameter(Mandatory=$true)][AllowEmptyString()] [String] $string
            )

            [Void] $messages.Add($string)
        }


        Write-DebugText('Checking for updates...')
        Write-DebugText('Started: ' + $startTime.ToString('HH:mm:ss'))

        $updateCheckUrl        = $args[0]
        $updateCheckFile       = $args[1]
        $currentVersionString  = $args[2]
        $updateSettings        = $args[3]
        $currentVersionInt     = 0
        $lastReleaseString     = ''
        $lastReleaseInt        = 0
        $lastCheckedTime       = 0
        $lastCheckedVersionInt = 0
        $lastCheckedVersionStr = ''
        $lastCheckedUrl        = ''
        $doOnlineCheck         = $false


        $returnObj = @{
            'isNew'    = $false
            'version'  = ''
            'url'      = ''
            'messages' = [System.Collections.ArrayList] @()
        }

        $currentVersion = @{
            'major'    = 0
            'minor'    = 0
            'revision' = 0
            'build'    = 0
        }

        $lastRelease = @{
            'major'    = 0
            'minor'    = 0
            'revision' = 0
            'build'    = 0
        }


        # Get the current version int value
        $null = $currentVersionString -Match '(?-i)(?<major>\d+)\.(?<minor>\d+)\.(?<revision>\d+)\.(?<build>\d+)(?<string>[aA-zZ0-9_\.\-]*)'

        Write-DebugText('The current version string:   ' + $currentVersionString)

        $currentVersion['major']    = $(if ($Matches['major'])    { $Matches['major'] }    else { 0 })
        $currentVersion['minor']    = $(if ($Matches['minor'])    { $Matches['minor'] }    else { 0 })
        $currentVersion['revision'] = $(if ($Matches['revision']) { $Matches['revision'] } else { 0 })
        $currentVersion['build']    = $(if ($Matches['build'])    { $Matches['build'] }    else { 0 })
        $currentVersion['string']   = $(if ($Matches['string'])   { -1 }                   else { 0 })  # If there's a string behind the version number, it's not a final version

        # If a string is present in the version number, reduce the int value by one to match the (assumed) previous version
        # E.g. 0.9.5.3alpha1 would become 9005002, which makes it equal to 0.9.5.2
        # This is to prevent that 0.9.5.3alpha1 would not register an available update for the final 0.9.5.3 (without string)
        [UInt64] $currentVersionInt = [UInt64] $currentVersion['major'] * 1000000000000 + [UInt64] $currentVersion['minor'] * 1000000000 + [UInt64] $currentVersion['revision'] * 1000000 + [UInt64] $currentVersion['build'] * 1000 + $currentVersion['string']
        Write-DebugText('Int value of current version: ' + $currentVersionInt)


        # Check the stored .updatecheck file
        if (!(Test-Path $updateCheckFile -PathType Leaf)) {
            Write-DebugText('The .updatecheck file doesn''t exist, initiate online check')
            $doOnlineCheck = $true
        }
        else {
            Write-DebugText('Reading the .updatecheck file:')

            $reader = [System.IO.File]::OpenText($updateCheckFile)
            $updateCheckContentString = $reader.ReadToEnd()
            $reader.Close()

            $updateCheckContent = @($updateCheckContentString -Split '\r?\n')

            foreach ($line in $updateCheckContent) {
                Write-DebugText($line)
            }

            # 0 should be the timestamp
            # 1 should be the version int value
            # 2 should be the version string
            # 3 should be the URL
            # 4 may not exist or be empty
            if ($updateCheckContent.Count -gt 3) {
                try {
                    $lastCheckedTime       = [UInt64] $updateCheckContent[0]
                    $lastCheckedVersionInt = [UInt64] $updateCheckContent[1]
                    $lastCheckedVersionStr = $updateCheckContent[2]
                    $lastCheckedUrl        = $updateCheckContent[3]

                    if ($lastCheckedVersionStr.Length -lt 6) {
                        $lastCheckedVersionStr = $lastCheckedVersionInt.ToString()
                    }

                    if (!$lastCheckedUrl -or $lastCheckedUrl.Length -lt 30) {
                        $lastCheckedUrl = 'https://github.com/sp00n/corecycler/releases'
                    }


                    Write-DebugText('Last checked timestamp:   ' + $lastCheckedTime)
                    Write-DebugText('Last checked version int: ' + $lastCheckedVersionInt)
                    Write-DebugText('Last checked version str: ' + $lastCheckedVersionStr)
                    Write-DebugText('Last checked URL:         ' + $lastCheckedUrl)

                    [UInt64] $curTimeStamp = Get-Date -UFormat %s -Millisecond 0
                    [UInt64] $sinceLastCheck = $curTimeStamp - $lastCheckedTime
                    [UInt64] $maxSeconds = $updateSettings.updateCheckFrequency * 60 * 60

                    Write-DebugText('Current timestamp:        ' + $curTimeStamp)
                    Write-DebugText('Time since last check:    ' + $sinceLastCheck + 's (' + [Math]::Round($sinceLastCheck/60/60, 3)  + 'h)')
                    Write-DebugText('Check interval:           ' + $maxSeconds + 's (' + [Math]::Round($maxSeconds/60/60, 3)  + 'h)')

                    if ($sinceLastCheck -gt $maxSeconds) {
                        Write-DebugText('The check interval time has been exceeded, initiate a new online check')
                        $doOnlineCheck = $true
                    }
                    else {
                        Write-DebugText('The check interval time has not yet been exceeded, do not initiate a new online check')
                    }
                }
                catch {
                    Write-DebugText($_)
                }
            }
        }


        # Don't do the online check
        # Because the interval time hasn't passed yet
        if (!$doOnlineCheck) {
            Write-DebugText('Not performing an online check')

            # But check if the stored information points to a newer version
            if ($lastCheckedVersionInt -gt $currentVersionInt) {
                Write-DebugText('The stored information points to a newer version')
                Write-DebugText('This version: ' + $currentVersionInt)
                Write-DebugText('New version:  ' + $lastCheckedVersionInt)

                $returnObj['isNew']    = $true
                $returnObj['version']  = $lastCheckedVersionStr
                $returnObj['url']      = $lastCheckedUrl
            }

            $endTime = Get-Date
            $runTime = $endTime - $startTime

            Write-DebugText('Background Job Started:             ' + $startTime.ToString('HH:mm:ss'))
            Write-DebugText('Background Job Ended:               ' + $endTime.ToString('HH:mm:ss'))
            Write-DebugText('Background Job Runtime:             ' + $runTime.TotalSeconds)

            $returnObj['messages'] = $messages

            return $returnObj
        }


        # Try to limit the time it takes before aborting
        $oriIdleTime = [System.Net.ServicePointManager]::MaxServicePointIdleTime

        # Disable the progress bar for Invoke-WebRequest and enable it again later
        $originalProgressPreference = $global:ProgressPreference
        $global:ProgressPreference = 'SilentlyContinue'

        # Make the request
        $content, $statusCode = try {
            [System.Net.ServicePointManager]::MaxServicePointIdleTime = 2000
            $response = Invoke-WebRequest -Uri $updateCheckUrl -TimeoutSec 2 -ErrorAction Stop
            $response.Content
            $response.StatusCode
        }
        catch [System.Net.WebException] {
            $response = $_.Exception.Response

            if ($response) {
                try {
                    $stream = $response.GetResponseStream()
                    $encoding = [System.Text.Encoding]::GetEncoding($response.CharacterSet)
                    $reader = [System.IO.StreamReader]::new($stream, $encoding)
                    $reader.DiscardBufferedData()
                    $reader.ReadToEnd()
                }
                finally {
                    $reader.Close()
                }

                $response.StatusCode.value__
            }
        }

        # Restore the original settings
        $global:ProgressPreference = $originalProgressPreference
        [System.Net.ServicePointManager]::MaxServicePointIdleTime = $oriIdleTime

        Write-DebugText('Web request status code: ' + $statusCode)


        # Couldn't get the releases
        if (!$content) {
            Write-DebugText('No content found for the request!')

            # But maybe the stored file already contains a newer version info
            if ($lastCheckedVersionInt -gt $currentVersionInt) {
                Write-DebugText('But the already stored information points to a newer version')
                Write-DebugText('This version: ' + $currentVersionInt)
                Write-DebugText('New version:  ' + $lastCheckedVersionInt)

                $returnObj['isNew']    = $true
                $returnObj['version']  = $lastCheckedVersionStr
                $returnObj['url']      = $lastCheckedUrl
            }

            $endTime = Get-Date
            $runTime = $endTime - $startTime

            Write-DebugText('Background Job Started:             ' + $startTime.ToString('HH:mm:ss'))
            Write-DebugText('Background Job Ended:               ' + $endTime.ToString('HH:mm:ss'))
            Write-DebugText('Background Job Runtime:             ' + $runTime.TotalSeconds)

            $returnObj['messages'] = $messages

            return $returnObj
        }


        # Parse the response and convert it to JSON
        $releases = ConvertFrom-Json $content
        $lastReleaseEntry = @()

        foreach ($release in $releases) {
            # Write-DebugText('$release[draft]: ' + $release.draft)
            # Write-DebugText('$release[prerelease]: ' + $release.prerelease)
            # Write-DebugText('Both False: ' + ($release.draft -ne $true -and $release.prerelease -ne $true))

            if (!$release -or !($release | Get-Member tag_name)) {
                continue
            }

            if ($release.draft -or $release.prerelease) {
                continue
            }

            # But is it a real final release?
            # A final release shouldn't have a string attached to it, so exclude it
            $null = $release.tag_name -Match '(?-i)(?<major>\d+)\.(?<minor>\d+)\.(?<revision>\d+)\.(?<build>\d+)(?<string>[aA-zZ0-9_\.\-]*)'

            if ($Matches['string']) {
                continue
            }

            Write-DebugText('Found our first real release!')

            $lastReleaseEntry = $release
            break
        }


        Write-DebugText('Tag name of last release:  ' + $lastReleaseEntry.tag_name)

        $lastReleaseString = $lastReleaseEntry.tag_name

        $null = $lastReleaseString -Match '(?-i)(?<major>\d+)\.(?<minor>\d+)\.(?<revision>\d+)\.(?<build>\d+)'

        $lastRelease['major']    = $(if ($Matches['major'])    { $Matches['major'] }    else { 0 })
        $lastRelease['minor']    = $(if ($Matches['minor'])    { $Matches['minor'] }    else { 0 })
        $lastRelease['revision'] = $(if ($Matches['revision']) { $Matches['revision'] } else { 0 })
        $lastRelease['build']    = $(if ($Matches['build'])    { $Matches['build'] }    else { 0 })

        [UInt64] $lastReleaseInt = [UInt64] $lastRelease['major'] * 1000000000000 + [UInt64] $lastRelease['minor'] * 1000000000 + [UInt64] $lastRelease['revision'] * 1000000 + [UInt64] $lastRelease['build'] * 1000

        Write-DebugText('Int value of last release: ' + $lastReleaseInt)

        if ($lastReleaseInt -gt $currentVersionInt) {
            Write-DebugText('New Version found! ' + $lastReleaseString + ' - ' + $lastReleaseInt)

            $returnObj['isNew'] = $true
            $returnObj['url'] = $lastReleaseEntry.html_url
            $returnObj['version'] = $lastReleaseString
        }
        else {
            Write-DebugText('No new version found')
        }

        Write-DebugText('Writing the .updatecheck file')

        [System.IO.File]::WriteAllLines($updateCheckFile, [string]::Join([Environment]::NewLine, (Get-Date -UFormat %s -Millisecond 0), $lastReleaseInt, $lastReleaseString, $lastReleaseEntry.html_url))

        $endTime = Get-Date
        $runTime = $endTime - $startTime

        Write-DebugText('Background Job Started:             ' + $startTime.ToString('HH:mm:ss'))
        Write-DebugText('Background Job Ended:               ' + $endTime.ToString('HH:mm:ss'))
        Write-DebugText('Background Job Runtime:             ' + $runTime.TotalSeconds)

        $returnObj['messages'] = $messages
        return $returnObj
    } -ArgumentList $updateCheckUrl, $updateCheckFile, $version, $updateSettings

    return $updateCheckBackgroundJob
}



<#
.DESCRIPTION
    Checks if we can run the update job early, because the line "enableUpdateCheck = 1"
    appears in the config.ini file
.PARAMETER
    [Void]
.OUTPUTS
    [Hashtable] [Bool] 'enabled' True if the line appears, False if not
                [Decimal] 'frequency' The check frequency, if available
#>
function Get-InitialUpdateCheckSetting {
    Write-DebugText('Trying to get the initial update check settings')

    $returnObj = @{
        'enabled'   = $enableUpdateCheck
        'frequency' = $updateCheckFrequency
    }


    # Check if the config.ini file exists
    if (!(Test-Path $configUserPath -PathType Leaf)) {
        return $returnObj
    }


    $patternCustomConfig    = '^useConfigFile\s*=\s*([aA-zZ0-9\.\-_\\:/ ]+)$'
    $patternUpdateCheck     = '^enableUpdateCheck\s*=\s*\d+\s*$'
    $patternUpdateFrequency = '^updateCheckFrequency\s*=\s*(.+)\s*$'

    $configPath = $configUserPath

    # Check if there's a custom config file being used
    $foundCustomConfigLine = Select-String -Path $configPath -Pattern $patternCustomConfig | Select-Object -Property Line -Last 1

    # Set the path to the custom config file only if it's found
    if ($foundCustomConfigLine) {
        $foundCustomConfigFile = $foundCustomConfigLine.Line -Match '=\s*(.+)'

        if ($foundCustomConfigFile -and $Matches[1]) {
            $configPathTemp = $PSScriptRoot + '\' + $Matches[1].Trim(' ', '"', '''', [Char]0x09)
            Write-DebugText('Custom config file: ' + $configPathTemp)

            if (Test-Path $configPathTemp -PathType Leaf) {
                $configPath = $configPathTemp
            }
            else {
                Write-DebugText($configPathTemp + ' not found, using the values from the config.ini')
            }
        }
    }


    # Check for a enableUpdateCheck = n string
    $foundUpdateCheckLine = Select-String -Path $configPath -Pattern $patternUpdateCheck | Select-Object -Property Line -Last 1

    # Disable it only if the value was found and is 0
    if ($foundUpdateCheckLine) {
        $foundUpdateCheckMatch = $foundUpdateCheckLine.Line -Match '=\s*(\d+)\s*'

        if ($foundUpdateCheckMatch -and $Matches[1]) {
            $isEnabled = [Bool] [Int] $Matches[1].Trim(' ', '"', '''', [Char]0x09)    # This should only return false for 0
            $returnObj['enabled'] = $isEnabled
        }
    }


    # Also check for the update check frequency
    $foundFrequencyLine = Select-String -Path $configPath -Pattern $patternUpdateFrequency | Select-Object -Property Line -Last 1

    if ($foundFrequencyLine) {
        $foundFrequencyMatch = $foundFrequencyLine.Line -Match '=\s*(\d+\.?\d*)\s*'     # Allow decimal values

        if ($foundFrequencyMatch -and $Matches[1]) {
            $frequency = [Decimal] $Matches[1].Trim(' ', '"', '''', [Char]0x09)
            $returnObj['frequency'] = $frequency
        }
    }

    Write-DebugText('Initial Update Check Enabled:   ' + $returnObj['enabled'])
    Write-DebugText('Initial Update Check Frequency: ' + $returnObj['frequency'])

    return $returnObj
}



<#
.DESCRIPTION
    Parse the .automode file
.OUTPUTS
    [HashTable] The parsed content from the .automode file
#>
function Get-AutoModeFileContent {
    Write-DebugText('Parsing the .automode file')

    if (!(Test-Path $autoModeFile -PathType Leaf)) {
        throw('Could not find the .automode file!')
    }

    $reader = [System.IO.File]::OpenText($autoModeFile)
    $autoModeFileContentString = $reader.ReadToEnd().Trim()
    $reader.Close()


    try {
        $autoModeInfoFromJson = ConvertFrom-Json $autoModeFileContentString
    }
    catch {
        throw $_
    }


    # We have some required properties
    @('fileTimestamp', 'lastCoreTested', 'logFileCoreCycler', 'logFileStressTest', 'voltageValues', 'waitBeforeResume') | ForEach-Object {
        if (!($autoModeInfoFromJson -and ($autoModeInfoFromJson | Get-Member $_))) {
            throw('The .automode file is missing the entry "' + $_ + '"!')
        }
    }


    # ConvertFrom-Json creates a PSCustomObject, which is hard to iterate, so create a hashtable instead
    $autoModeInfo = @{
        'fileTimestamp'     = [UInt64] $autoModeInfoFromJson.fileTimestamp
        'lastCoreTested'    = [Int] $autoModeInfoFromJson.lastCoreTested
        'logFileCoreCycler' = [String] $autoModeInfoFromJson.logFileCoreCycler
        'logFileStressTest' = [String] $autoModeInfoFromJson.logFileStressTest
        'voltageValues'     = [Array] $autoModeInfoFromJson.voltageValues
        'waitBeforeResume'  = [Int] $autoModeInfoFromJson.waitBeforeResume
    }

    if ($autoModeInfo.lastCoreTested -ne $CoreFromAutoMode) {
        throw('The passed core does not match the core in the .automode file! (' + $autoModeInfo.lastCoreTested + ' vs. ' + $CoreFromAutoMode + ')')
    }

    return $autoModeInfo
}



<#
.DESCRIPTION
    Set/create the the .automode file
.PARAMETER coreNumber
    [Int] The currently started core
.OUTPUTS
    [Void]
#>
function Set-AutoModeFile {
    param(
        [Parameter(Mandatory=$true)] [Int] $coreNumber
    )

    Write-DebugText('Creating the .automode file')

    [UInt64] $curTimeStamp = Get-Date -UFormat %s -Millisecond 0


    # Remove the old file
    if (Test-Path $autoModeFile -PathType Leaf) {
        $null = Remove-Item -Path $autoModeFile -Force
    }


    $autoModeFileObject = @{
        'fileTimestamp'     = $curTimeStamp
        'lastCoreTested'    = $coreNumber
        'logFileCoreCycler' = $logFileFullPath
        'logFileStressTest' = $stressTestLogFilePath
        'voltageValues'     = $voltageCurrentValues
        'waitBeforeResume'  = $settings['AutomaticTestMode']['waitBeforeAutomaticResume']
    }

    # Convert to JSON
    $autoModeFileJson = ConvertTo-Json $autoModeFileObject


    # We save the file under a different name, and then rename it, which will hopefully trigger the file content flush to disk
    $null = New-Item $autoModeFileTemp -ItemType File -Force

    if (!(Test-Path $autoModeFileTemp -PathType Leaf)) {
        Exit-WithFatalError -text 'Could not create the .automode-temp file!'
    }

    [System.IO.File]::WriteAllLines($autoModeFileTemp, $autoModeFileJson)


    # Try to flush the cache to the disk, hopefully reducing the amount of corrupted files
    if ($canUseFlushToDisk) {
        Save-CachedDataToDisk
    }


    # Now rename the file
    $null = Rename-Item -Path $autoModeFileTemp -NewName $autoModeFile -Force

    if (!(Test-Path $autoModeFile -PathType Leaf)) {
        Exit-WithFatalError -text 'Could not create the .automode file!'
    }
}



<#
.DESCRIPTION
    Remove the .automode file
.OUTPUTS
    [Void]
#>
function Remove-AutoModeFile {
    Write-DebugText('Removing the .automode file')

    if (Test-Path $autoModeFile -PathType Leaf) {
        Remove-Item -Path $autoModeFile
    }
}



<#
.DESCRIPTION
    Adds the Automatic Mode scheduled task
    Requires administrator rights
.OUTPUTS
    [Void]
#>
function Add-AutoModeScheduledTask {
    Write-DebugText('Trying to add the Auto Mode startup task "' + $autoModeTaskPath + '\' + $autoModeTaskName + '"')

    if (!$areWeAdmin) {
        Write-DebugText('We are not admin, aborting')

        Write-ColorText('FATAL ERROR: Could not add the scheduled startup task for the Automatic Mode, aborting!') Red
        Exit-WithFatalError
        return
    }

    try {
        # If running when the user is not logged on, the account used might need Logon as Batch permission
        # To run without having logged in, you need to provide the password during creation, e.g. like this:
        # $cred = Get-Credential -Message "Enter Credentials"
        # $username = $cred.username
        # $password = $cred.getnetworkcredential().password
        #
        # $User = "Domain01\User01"
        # $PWord = Read-Host -Prompt 'Enter a Password' -AsSecureString
        # $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $PWord

        $user      = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-ExecutionPolicy Bypass -File "' + $autoModeStartupScriptFile + '"')
        $trigger   = New-ScheduledTaskTrigger -AtLogOn -User $user
        $principal = New-ScheduledTaskPrincipal -UserId $user -RunLevel Highest
        $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Priority 8
        $task      = New-ScheduledTask -Action $action -Principal $principal -Trigger $trigger -Settings $settings -Description $autoModeTaskDescription

        $null = Register-ScheduledTask -Force -TaskName $autoModeTaskName -TaskPath $autoModeTaskPath -InputObject $task
        $foundTask = Get-ScheduledTask -TaskName $autoModeTaskName -TaskPath $autoModeTaskPath -ErrorAction SilentlyContinue

        if (!$foundTask) {
            throw('Could not find the created task!')
        }


        # Issue 118
        # If the computer crashes right after creating the scheduled task, it will not be executed on the next boot
        # The registry is not immediately written to disk, so the reg key may be lost during the crash
        # See https://superuser.com/a/1331545/196649
        # See https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regflushkey
        # Computer\HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache
        $HKLM = 0x80000002     # HKEY_LOCAL_MACHINE
        $accessRights = 0x0001 # KEY_QUERY_VALUE
        $regSubPath = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache'
        $regHandle = [IntPtr]::Zero

        # Open
        $openResult = [RegistryFlusher]::RegOpenKeyExW($HKLM, $regSubPath, 0, $accessRights, [Ref] $regHandle)
        $errorCode  = [Runtime.InteropServices.Marshal]::GetLastWin32Error()

        if ($openResult -ne $ERROR_SUCCESS) {
            Write-DebugText('Failed to check the registry key for the scheduled task. (Result ' + $openResult + ')')

            if ($errorCode -gt 0) {
                Write-DebugText('Error Code: ' + $errorCode + ' - Line: ' + (Get-ScriptLineNumber))
                $errorResult = Get-DotNetErrorMessage $errorCode
                Write-DebugText($errorResult.errorMessage)
                throw('Failed to check the registry key for the scheduled task!' + [Environment]::NewLine + $errorResult.errorMessage)
            }
        }

        # Flush
        $flushResult = [RegistryFlusher]::RegFlushKey($regHandle)
        $errorCode   = [Runtime.InteropServices.Marshal]::GetLastWin32Error()

        if ($flushResult -ne $ERROR_SUCCESS) {
            Write-DebugText('Failed to flush the registry key for the scheduled task. (Result ' + $flushResult + ')')

            if ($errorCode -gt 0) {
                Write-DebugText('Error Code: ' + $errorCode + ' - Line: ' + (Get-ScriptLineNumber))
                $errorResult = Get-DotNetErrorMessage $errorCode
                Write-DebugText($errorResult.errorMessage)
                throw('Failed to flush the registry key for the scheduled task!' + [Environment]::NewLine + $errorResult.errorMessage)
            }
        }

        # Close
        $closeResult = [RegistryFlusher]::RegCloseKey($regHandle)
        $errorCode   = [Runtime.InteropServices.Marshal]::GetLastWin32Error()

        if ($closeResult -ne $ERROR_SUCCESS) {
            Write-DebugText('Failed to close the registry key for the scheduled task. (Result ' + $closeResult + ')')

            if ($errorCode -gt 0) {
                Write-DebugText('Error Code: ' + $errorCode + ' - Line: ' + (Get-ScriptLineNumber))
                $errorResult = Get-DotNetErrorMessage $errorCode
                Write-DebugText($errorResult.errorMessage)
                throw('Failed to close the registry key for the scheduled task!' + [Environment]::NewLine + $errorResult.errorMessage)
            }
        }

        Write-DebugText('Added the Automatic Test Mode startup task')
    }
    catch {
        Write-ColorText('FATAL ERROR: Could not add the scheduled startup task for the Automatic Mode, aborting!') Red
        Write-ColorText($_) Red
        Exit-WithFatalError
    }
}



<#
.DESCRIPTION
    Remove the Automatic Mode scheduled task
    Requires administrator rights
.OUTPUTS
    [Void]
#>
function Remove-AutoModeScheduledTask {
    Write-DebugText('Removing the startup task "' + $autoModeTaskPath + '\' + $autoModeTaskName + '"')

    # Do not throw an error if it doesn't exist or we aren't addmin
    Unregister-ScheduledTask -TaskName $autoModeTaskName -TaskPath $autoModeTaskPath -Confirm:$false -ErrorAction Ignore
}



<#
.DESCRIPTION
    Import the settings from a .ini file
.PARAMETER filePathOrDefault
    [String] The path to the file to parse, or DEFAULT for the default settings
.OUTPUTS
    [HashTable] A hashtable holding the settings
#>
function Import-Settings {
    param(
        [Parameter(Mandatory=$true)] $filePathOrDefault
    )

    # Certain setting values are strings
    $settingsWithStrings = @(
        'useConfigFile'
        'coreTestOrder'
        'stressTestProgram'
        'stressTestProgramPriority'
        'name'
        'version'
        'mode'
        'FFTSize'
        'tests'
        'memory'
        'modeToUseForSuspension'
    )

    # Certain setting values are decimals
    $settingsWithDecimals = @('updateCheckFrequency')

    # Lowercase for certain settings
    $settingsToLowercase = @(
        'stressTestProgram'
        'coreTestOrder'
        'startValues'
        'memory'
        'modeToUseForSuspension'
    )

    # Settings with arrays
    $settingsWithArrays = @(
        'coresToIgnore'
    )

    # Settings that are arrays but also can have a string value
    $settingsWithArrayOrString = @(
        #'coreTestOrder' # This is handled later
        'startValues'
    )

    # Check if the file exists
    if ($filePathOrDefault -ne 'DEFAULT' -and !(Test-Path $filePathOrDefault -PathType Leaf)) {
        Exit-WithFatalError -text ('Could not find ' + $filePathOrDefault + '!')
    }

    # Read the config file
    if ($filePathOrDefault -ne 'DEFAULT') {
        $file = Get-ChildItem -Path $filePathOrDefault
        $reader = [System.IO.File]::OpenText($file)
        $settingsString = $reader.ReadToEnd()
        $reader.Close()
    }

    # The default settings string
    else {
        $settingsString = $DEFAULT_SETTINGS_STRING
    }

    $settingsArray = $settingsString -Split '\r?\n'


    # This holds the parsed settings
    $ini = @{}

    #switch -Regex -File $filePathOrDefault {
    switch -Regex ($settingsArray) {
        # Comments start with: #
        '^#' {
            continue
        }

        # Sections are in brackets: []
        '^\[(.+)\]$' {
            # Remove any spaces, double quotes and single quotes around the section name
            $section = $Matches[1].ToString().Trim(' ', '"', '''', [Char]0x09)
            $ini[$section] = @{}
        }

        # Settings follow after: =
        '^(.+)\s?=\s?(.*)$' {
            $setting = $null
            $name, $value = $Matches[1..2]
            $name  = $name.ToString().Trim(' ', '"', '''', [Char]0x09)
            $value = $value.ToString().Trim(' ', '"', '''', [Char]0x09)


            # Treat a "#" as an inline comment and remove it and anything after from the value
            $value = $(if ($value.IndexOf('#') -gt -1) { $value.Split('#')[0].Trim(' ', '"', '''', [Char]0x09) } else { $value })


            # Settings that are regular arrays and can be empty
            if ($settingsWithArrays -contains $name) {
                $thisSetting = @()

                if ($null -ne $value -and ![String]::IsNullOrWhiteSpace($value)) {
                    # Split the string by comma or space and add each entry as an integer
                    $value -Split '\s*,\s*|\s+' | ForEach-Object {
                        if ($_.Length -gt 0) {
                            $thisSetting += [Int] $_
                        }
                    }

                    # Sort the array if it's coresToIgnore
                    if ($name -eq 'coresToIgnore') {
                        # We cannot use Sort here, as it would transform an array with only one entry into an integer!
                        $thisSetting::Sort($thisSetting)
                    }
                }

                $setting = $thisSetting
            }


            # Settings that can be arrays or a string value
            elseif ($settingsWithArrayOrString -contains $name) {
                $thisSetting = $null

                if ($null -ne $value -and ![String]::IsNullOrWhiteSpace($value)) {
                    if ($settingsToLowercase -contains $name) {
                        $thisSetting = ([String] $value).ToLowerInvariant()
                    }
                    else {
                        $thisSetting = [String] $value
                    }

                    # Try to split the string by comma, "|" or space
                    $splitString = @(@($thisSetting -Split '\s*[,\|]\s*|\s+') | Where-Object { $_.Length -gt 0 })

                    # Is there only one entry and is it not an integer?
                    if ($splitString.Count -eq 1 -and $splitString[0] -Match '^\-?\d+$') {
                        $thisSetting = $splitString[0]
                    }

                    # More than one entry, or the single entry is an integer
                    else {
                        $thisSetting = @($splitString | ForEach-Object { if ($_ -Match '^\-?\d+$')  { [Int] $_ } else { $_ } })
                    }
                }

                $setting = $thisSetting
            }


            # Special handling for y-cruncher tests
            # Split them into an array
            elseif ($section -eq 'yCruncher' -and $name -eq 'tests') {
                $thisSetting = @()

                # Empty value, use the default
                if ($null -eq $value -or [String]::IsNullOrWhiteSpace($value)) {
                    $value = $stressTestPrograms.ycruncher.defaultTests -Join ', '
                }

                # Split the string by comma or space
                $value -Split '\s*,\s*|\s+' | ForEach-Object {
                    if ($_.Length -gt 0) {
                        $thisSetting += $_.ToString().Trim(' ', '"', '''', [Char]0x09).ToUpperInvariant()
                    }
                }

                # The possible y-cruncher test values
                # Depends on the version of y-cruncher the user has selected
                # Hopefully we already have the [General] section parsed
                $possibleTests = $stressTestPrograms.ycruncher.availableTests
                $selectedTests = @()

                if ($ini['General']['stressTestProgram']) {
                    if ($ini['General']['stressTestProgram'] -eq 'ycruncher_old') {
                        $possibleTests = $stressTestPrograms.ycruncher_old.availableTests
                    }
                }

                # The [General] section is not available yet, merge both available tests
                else {
                    $possibleTests = @($possibleTests + $stressTestPrograms.ycruncher_old.availableTests) | Sort-Object | Get-Unique
                }

                # Filter for only the possible test values
                $thisSetting | ForEach-Object {
                    $foundKey = $possibleTests.ToUpperInvariant().IndexOf($_.ToUpperInvariant())

                    if ($foundKey -gt -1) {
                        $selectedTests += $possibleTests[$foundKey]
                    }
                }

                $setting = $selectedTests
            }


            # Special handling for the max Curve Optimizer / voltage offset values
            elseif ($section -eq 'AutomaticTestMode' -and $name -eq 'incrementBy') {
                $thisSetting = $null

                if ($value.ToLowerInvariant() -eq 'default') {
                    $cpuType = $(if ($isIntelProcessor) { 'INTEL' } else { 'AMD' })
                    $thisSetting = $defaultVoltageIncrementValues[$cpuType]
                }
                else {
                    $thisSetting = [Int] $value
                }

                $setting = $thisSetting
            }


            # Regular settings cannot be empty
            elseif ($value -and ![String]::IsNullOrWhiteSpace($value)) {
                $thisSetting = $null

                # For runtimePerCore, parse the string (seconds, minutes, hours)
                if ($name -eq 'runtimePerCore') {
                    $valueLower = $value.ToLowerInvariant()

                    # It can be set to "auto"
                    if ($valueLower -eq 'auto') {
                        $thisSetting = 'auto'
                    }

                    # Parse the hours, minutes, seconds
                    elseif ($valueLower.indexOf('h') -ge 0 -or $valueLower.indexOf('m') -ge 0 -or $valueLower.indexOf('s') -ge 0) {
                        $null = $valueLower -Match '(?-i)((?<hours>\d+(\.\d+)*)h)*\s*((?<minutes>\d+(\.\d+)*)m)*\s*((?<seconds>\d+(\.\d+)*)s)*'
                        $seconds = [Double] $Matches['hours'] * 60 * 60 + [Double] $Matches['minutes'] * 60 + [Double] $Matches['seconds']
                        $thisSetting = [Int] $seconds
                    }

                    # Treat the value as seconds
                    else {
                        $thisSetting = [Int] $value
                    }
                }


                # String values
                elseif ($settingsWithStrings -contains $name) {
                    # Convert some to lower case
                    if ($settingsToLowercase -contains $name) {
                        $thisSetting = ([String] $value).ToLowerInvariant()
                    }
                    else {
                        $thisSetting = [String] $value
                    }
                }


                # Decimal values
                elseif ($settingsWithDecimals -contains $name -and $value -and ![String]::IsNullOrWhiteSpace($value)) {
                    $thisSetting = [Decimal] $value
                }


                # Any not specially mentioned settings are integer values
                elseif ($value -and ![String]::IsNullOrWhiteSpace($value)) {
                    $thisSetting = [Int] $value
                }

                $setting = $thisSetting
            }

            # No [section] found, error
            if (!$section -or [String]::IsNullOrWhiteSpace($section)) {
                Write-ColorText('FATAL ERROR: Invalid config file "' + $filePath + '" detected!') Red
                Write-ColorText('Maybe your config file is still from an older version.') Red
                Write-ColorText('Please delete your config.ini file and try again.') Red
                Exit-WithFatalError
            }

            $ini[$section][$name] = $setting
        }
    }

    return $ini
}



<#
.DESCRIPTION
    Get the settings
.PARAMETER
    [Void]
.OUTPUTS
    [Void]
#>
function Get-Settings {
    Write-DebugText('Getting the settings')

    $logFilePrefix = 'CoreCycler'

    # Set the temporary name and path for the logfile
    # We need it because of the Exit-WithFatalError calls below
    # We don't have all the information yet though, so the name and path will be overwritten after all the user settings have been parsed
    $Script:logFileName     = $logFilePrefix + '_' + $scriptStartDateTime + '.log'
    $Script:logFileFullPath = $logFilePathAbsolute + $logFileName


    # Get the default config settings
    $defaultSettings = Import-Settings 'DEFAULT'

    # The log file prefix may have been overwritten in the settings
    $logFilePrefix = $(if (![String]::IsNullOrWhiteSpace($defaultSettings.Logging.name)) { $defaultSettings.Logging.name } else { $logFilePrefix })

    $Script:logFileName     = $logFilePrefix + '_' + $scriptStartDateTime + '.log'
    $Script:logFileFullPath = $logFilePathAbsolute + $logFileName


    # If no config.ini file exists, copy the default values to the config.ini
    if (!(Test-Path $configUserPath -PathType Leaf)) {
        [System.IO.File]::WriteAllLines($configUserPath, $DEFAULT_SETTINGS_STRING)

        if (!(Test-Path $configUserPath -PathType Leaf)) {
            Exit-WithFatalError -text 'Could not create the config.ini file!'
        }
    }


    # Read the config.ini file
    try {
        $userSettings = Import-Settings $configUserPath
    }

    # Couldn't get the a valid content from the config.ini, create the file with the default values
    catch {
        Write-DebugText('Error when reading the user settings')
        Write-ColorText('WARNING: config.ini corrupted, replacing with default values!') Yellow

        if (!(Test-Path $configDefaultPath -PathType Leaf)) {
            Exit-WithFatalError -text 'Neither config.ini nor default.config.ini found!'
        }

        [System.IO.File]::WriteAllLines($configUserPath, $DEFAULT_SETTINGS_STRING)
        $userSettings = Import-Settings $configUserPath
    }


    # Check if we should use a custom config file, and if the file exists
    if ($userSettings['General']['useConfigFile'] -and $userSettings['General']['useConfigFile'].ToString().Trim(' ', '"', '''', [Char]0x09).Length -gt 0) {
        $customConfigPath = $PSScriptRoot + '\' + $userSettings['General']['useConfigFile']

        Write-Text('A custom config file was provided:')
        Write-Text($customConfigPath)

        try {
            if (Test-Path $customConfigPath -PathType Leaf) {
                # Overwrite the already parsed settings
                $userSettings = Import-Settings $customConfigPath

                # Store the path in the global variable
                $Script:customConfigPath = $customConfigPath
            }
            else {
                Write-Text('Couldn''t find the custom config file, using the values from the config.ini!')
            }
        }

        # The custom config file existed, but couldn't be parsed correctly
        catch {
            Write-ColorText('WARNING: "' + $customConfigPath + '" is corrupted!') Yellow
            Write-ColorText('         Using the values from the config.ini instead') Yellow
            Write-Text('')
            Write-ColorText('Error: ' + $_) Yellow
        }
    }


    # Check if the config.ini contained valid setting
    # It may be corrupted if the computer immediately crashed when saving due to unstable settings
    try {
        foreach ($entry in $userSettings.GetEnumerator()) {
        }
    }

    # Couldn't get the a valid content from the config.ini, replace it with the default
    catch {
        Write-DebugText('Couldn''t get valid settings from config.ini')
        Write-ColorText('WARNING: config.ini corrupted, replacing with default values!') Yellow
        Write-ColorText($_) Yellow

        if (!(Test-Path $configDefaultPath -PathType Leaf)) {
            Exit-WithFatalError -text 'Neither config.ini nor default.config.ini found!'
        }

        [System.IO.File]::WriteAllLines($configUserPath, $DEFAULT_SETTINGS_STRING)
        $userSettings = Import-Settings $configUserPath
    }


    # Merge the user settings with the default settings
    $settings = $defaultSettings

    foreach ($sectionEntry in $userSettings.GetEnumerator()) {
        foreach ($userSetting in $sectionEntry.Value.GetEnumerator()) {
            # No empty values (except empty arrays)
            if (
                ($null -ne $userSetting.Value -and ![String]::IsNullOrWhiteSpace($userSetting.Value)) -or
                ($userSetting.Value -is [Array] -or $userSetting.Value -is [Hashtable])
            ) {
                # Allow both ycruncher and y-cruncher
                if ($userSetting.Name -eq 'stressTestProgram' -and $userSetting.Value.ToLowerInvariant() -eq 'y-cruncher') {
                    $userSetting.Value = 'ycruncher'
                }

                if (!$settings[$sectionEntry.Name]) {
                    throw('Found an unexpected section in the config: [' + $sectionEntry.Name + ']')
                }

                $settings[$sectionEntry.Name][$userSetting.Name] = $userSetting.Value
            }
            else {
                # Write-VerboseText('Setting is empty!')
                # Write-VerboseText('[' + $sectionEntry.Name + '][' + $userSetting.Name + ']: ' + $userSetting.Value)
            }
        }
    }


    # Limit the number of threads to 1 - 2
    $settings.General.numberOfThreads = [Math]::Max(1, [Math]::Min(2, $settings.General.numberOfThreads))
    $settings.General.numberOfThreads = $(if ($Script:isHyperthreadingEnabled) { $settings.General.numberOfThreads } else { 1 })

    if (!$Script:isHyperthreadingEnabled) {
        Write-Text('Hyperthreading is not enabled, setting the number of threads to use to 1')
    }


    # If the selected stress test program is not supported
    if (!$settings.General.stressTestProgram -or !($stressTestPrograms.Contains($settings.General.stressTestProgram))) {
        Exit-WithFatalError -text ('The selected stress test program "' + $settings.General.stressTestProgram + '" could not be found!')
    }


    # Set the correct flag
    $Script:isPrime95                 = $(if ($settings.General.stressTestProgram -eq 'prime95' -or $settings.General.stressTestProgram -eq 'prime95_dev') { $true } else { $false })
    $Script:isAida64                  = $(if ($settings.General.stressTestProgram -eq 'aida64') { $true } else { $false })
    $Script:isYCruncher               = $(if ($settings.General.stressTestProgram -eq 'ycruncher') { $true } else { $false })
    $Script:isYCruncherOld            = $(if ($settings.General.stressTestProgram -eq 'ycruncher_old') { $true } else { $false })
    $Script:isYCruncherWithLogging    = $(if (($isYCruncher -or $isYCruncherOld) -and $settings.yCruncher.enableYCruncherLoggingWrapper) { $true } else { $false })
    $Script:isLinpack                 = $(if ($settings.General.stressTestProgram -eq 'linpack') { $true } else { $false })


    # Set the general "mode" setting
    if ($isPrime95) {
        $settings.mode = $settings.Prime95.mode.ToUpperInvariant()
    }
    elseif ($isAida64) {
        $settings.mode = $settings.Aida64.mode.ToUpperInvariant()
    }
    elseif ($isYCruncher -or $isYCruncherOld) {
        $settings.mode = $settings.yCruncher.mode.ToUpperInvariant()
    }
    elseif ($isLinpack) {
        # The mode settings is really only available for 2018 and 2019, anything newer always uses FASTEST
        $settings.mode =  $(if ($settings.Linpack.version -eq '2018' -or $settings.Linpack.version -eq '2019') { $settings.Linpack.mode.ToUpperInvariant() } else { 'FASTEST' })
    }


    # The selected mode for y-cruncher = the binary to execute
    # Override the variables
    if ($isYCruncher -or $isYCruncherOld) {
        # Allow shortcuts for y-cruncher
        if (!($Script:stressTestPrograms[$settings.General.stressTestProgram]['testModes'] -contains $settings.mode)) {
            Write-VerboseText('The settings mode from the config.ini was not found: ' + $settings.mode)

            $testModes = $Script:stressTestPrograms[$settings.General.stressTestProgram]['testModes']

            if ($settings.mode.Length -ge 2) {
                $possibleMatchedMode = $testModes -Like $settings.mode + '*'

                # Override the mode
                # y-cruncher cannot have more than one entry, so we can also override the modeString here
                if ($possibleMatchedMode) {
                    Write-VerboseText('But have found the long form: ' + $possibleMatchedMode)

                    $settings.mode = $possibleMatchedMode.ToUpperInvariant()
                }
            }
        }


        $yCruncherBinary = $stressTestPrograms[$settings.General.stressTestProgram]['testModes'] | Where-Object -FilterScript { $_.ToLowerInvariant() -eq $settings.mode.ToLowerInvariant() }
        $Script:stressTestPrograms[$settings.General.stressTestProgram]['processName']        = $yCruncherBinary
        $Script:stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad'] = $yCruncherBinary
        $Script:stressTestPrograms[$settings.General.stressTestProgram]['fullPathToExe']      = $stressTestPrograms[$settings.General.stressTestProgram]['absolutePath'] + $yCruncherBinary
        $Script:stressTestPrograms[$settings.General.stressTestProgram]['fullPathToLoadExe']  = $stressTestPrograms[$settings.General.stressTestProgram]['absolutePath'] + $yCruncherBinary

        # Special handling if enableYCruncherLoggingWrapper is enabled
        if ($isYCruncherWithLogging) {
            $Script:stressTestPrograms[$settings.General.stressTestProgram]['processName']    = 'WriteConsoleToWriteFileWrapper'
            $Script:stressTestPrograms[$settings.General.stressTestProgram]['windowNames']    = @(
                '^.*WriteConsoleToWriteFileWrapper\.exe$'
                '^.*' + $yCruncherBinary + '\.exe$'
            )
        }
        else {
            $Script:stressTestPrograms[$settings.General.stressTestProgram]['windowNames']    = @('^.*' + $yCruncherBinary + '\.exe$')
        }
    }


    # Select the binary for Linpack, depending on the installed processor
    # Linpack is started via powershell, so that we can both see the output and create a log file
    if ($isLinpack) {
        # The version we're now using (linpack_patched.exe) is already patched to not check for the CPU manufacturer anymore
        # Hopefully this is enough
        # There are different versions available
        $versionsToPath = @{
            '2018' = '2018.0.3.1'
            '2019' = '2019.0.3.1'
            '2021' = '2021.4.1.0'
            '2024' = '2024.2.1.0'
        }

        # Get the version to use
        $linpackVersion = $settings.Linpack.version
        $linpackVersionPath = $versionsToPath[$linpackVersion]

        if (!$linpackVersionPath) {
            Exit-WithFatalError('Invalid version for Linpack selected! (' + $linpackVersion + ')')
        }

        $linpackBinary = $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad']
        $linpackPath   = $stressTestPrograms[$settings.General.stressTestProgram]['processPath'] + '\' + $linpackVersionPath

        $Script:stressTestPrograms[$settings.General.stressTestProgram]['processName']        = 'powershell'
        $Script:stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad'] = $linpackBinary
        $Script:stressTestPrograms[$settings.General.stressTestProgram]['processPath']        = $linpackPath
        $Script:stressTestPrograms[$settings.General.stressTestProgram]['installPath']        = $linpackPath
    }


    # Sanity check the selected test mode
    # For Aida64, you can set a comma separated list of multiple stress tests
    $modesArray = $settings.mode -Split '\s*,\s*' | Where-Object { $_.Length -gt 0 }
    $modeString = ($modesArray -Join '-').ToUpperInvariant()

    foreach ($mode in $modesArray) {
        if (!($Script:stressTestPrograms[$settings.General.stressTestProgram]['testModes'] -contains $mode)) {
            # Add a special error message if trying to run 00-x86 for the newer y-cruncher versions
            if (!$isYCruncherOld -and $mode.ToUpperInvariant() -eq '00-X86') {
                Write-ColorText('FATAL ERROR: Invalid "mode" setting detected!') Red
                Write-ColorText('Trying to run "00-x86", but y-cruncher doesn''t support this anymore!') Red
                Write-ColorText('To be able to use "00-x86", you will need to select "YCRUNCHER_OLD" as the stress test.') Red
                Write-ColorText('The newer versions of y-cruncher do not support this mode anymore.') Red
                Write-ColorText('The new minimum "mode" is now "04-P4P" instead.') Red
                Write-Text('')
                Write-ColorText('You will also need to adjust the "tests" setting accordingly, as these have changed as well.') Red
                Write-ColorText('See the comments in the config file for a more detailed explanation.') Red
                Exit-WithFatalError
            }

            # The regular error message
            Exit-WithFatalError -text ('The selected test mode "' + $mode + '" is not available for ' + $stressTestPrograms[$settings.General.stressTestProgram]['displayName'] + '!')
        }
    }

    # Add the version to the log file for Linpack
    if ($isLinpack) {
        $modeString = $settings.Linpack.version + '_' + $modeString
    }


    # Store in the global variable
    $Script:settings = $settings


    # If we're resuming the script, we want to re-use the same CoreCycler log file
    if ($settings['AutomaticTestMode']['enableAutomaticAdjustment'] -gt 0 -and $settings['AutomaticTestMode']['enableResumeAfterUnexpectedExit'] -gt 0 -and $CoreFromAutoMode -gt -1) {
        Write-DebugText('Automatic Test Mode with resume seems to be active, checking')

        try {
            $autoModeInfo = Get-AutoModeFileContent

            Write-DebugText('Setting the main log file to the one from the previous run:')
            Write-DebugText('logFileCoreCycler: ' + $autoModeInfo['logFileCoreCycler'])
            #Write-DebugText('logFileStressTest: ' + $autoModeInfo['logFileStressTest'])

            $Script:logFileName     = Split-Path -Path $autoModeInfo['logFileCoreCycler'] -Leaf
            $Script:logFileFullPath = $autoModeInfo['logFileCoreCycler']
            $Script:canUseLogFile   = $true
        }
        catch {
            # Some error with the .automode file, ignore at this point
            Write-DebugText('Could not re-use the previous log file:')
            Write-DebugText($_)
        }
    }


    # Regular method to set the logfile
    if (!$canUseLogFile) {
        # Set the final full path and name of the log file
        $logFilePrefix = $(if (![String]::IsNullOrWhiteSpace($settings.Logging.name)) { $settings.Logging.name } else { $logFilePrefix })

        $Script:logFileName     = $logFilePrefix + '_' + $scriptStartDateTime + '_' + $settings.General.stressTestProgram.ToUpperInvariant() + '_' + $modeString + '.log'
        $Script:logFileFullPath = $logFilePathAbsolute + $logFileName
        $Script:canUseLogFile   = $true
    }


    # Debug settings may override default settings
    $Script:disableCpuUtilizationCheck                     = $(if (![String]::IsNullOrWhiteSpace($settings.Debug.disableCpuUtilizationCheck))                     { $settings.Debug.disableCpuUtilizationCheck }                     else { $disableCpuUtilizationCheckDefault })
    $Script:useWindowsPerformanceCountersForCpuUtilization = $(if (![String]::IsNullOrWhiteSpace($settings.Debug.useWindowsPerformanceCountersForCpuUtilization)) { $settings.Debug.useWindowsPerformanceCountersForCpuUtilization } else { $useWindowsPerformanceCountersForCpuUtilizationDefault })
    $Script:enableCpuFrequencyCheck                        = $(if (![String]::IsNullOrWhiteSpace($settings.Debug.enableCpuFrequencyCheck))                        { $settings.Debug.enableCpuFrequencyCheck }                        else { $enableCpuFrequencyCheckDefault })
    $Script:tickInterval                                   = $(if (![String]::IsNullOrWhiteSpace($settings.Debug.tickInterval))                                   { $settings.Debug.tickInterval }                                   else { $tickIntervalDefault })
    $Script:delayFirstErrorCheck                           = $(if (![String]::IsNullOrWhiteSpace($settings.Debug.delayFirstErrorCheck))                           { $settings.Debug.delayFirstErrorCheck }                           else { $delayFirstErrorCheckDefault })
    $Script:stressTestProgramPriority                      = $(if (![String]::IsNullOrWhiteSpace($settings.Debug.stressTestProgramPriority))                      { $settings.Debug.stressTestProgramPriority }                      else { $stressTestProgramPriorityDefault })
    $Script:stressTestProgramWindowToForeground            = $(if (![String]::IsNullOrWhiteSpace($settings.Debug.stressTestProgramWindowToForeground))            { $settings.Debug.stressTestProgramWindowToForeground }            else { $stressTestProgramWindowToForegroundDefault })
    $Script:suspensionTime                                 = $(if (![String]::IsNullOrWhiteSpace($settings.Debug.suspensionTime))                                 { $settings.Debug.suspensionTime }                                 else { $suspensionTimeDefault })
    $Script:modeToUseForSuspension                         = $(if (![String]::IsNullOrWhiteSpace($settings.Debug.modeToUseForSuspension))                         { $settings.Debug.modeToUseForSuspension }                         else { $modeToUseForSuspensionDefault.ToLowerInvariant() })



    # If the selected stress test program requires the CPU usage to be checked to detect errors, but the debug setting to do so is disabled
    # (This is the default setting now)
    if ($settings.Debug.disableCpuUtilizationCheck -and $stressTestPrograms[$settings.General.stressTestProgram]['requiresCpuCheck']) {
        $Script:disableCpuUtilizationCheck = 0
        $Script:showNoteForDisableCpuUtilization = $true
    }

    $Script:enablePerformanceCounters = ((!$Script:disableCpuUtilizationCheck -and $Script:useWindowsPerformanceCountersForCpuUtilization) -or $Script:enableCpuFrequencyCheck)
    $Script:enableUpdateCheck = [Bool] $settings.Update.enableUpdateCheck


    # At this point the final log file is available, write the log buffer to it
    if ($logBuffer.Count -gt 0) {
        forEach ($logEntry in $logBuffer) {
            Write-LogEntry $logEntry
        }

        $logBuffer = $null
    }


    Write-DebugText('Settings parsed')
}



<#
.DESCRIPTION
    Export the default settings and writes the default.config.ini file
.PARAMETER
    [Void]
.OUTPUTS
    [Void] Writes the default.config.ini file
#>
function Export-DefaultSettings {
    $noticeLines = @(
        '# This is the default config file for CoreCycler',
        '# Rename this file to config.ini, copy it to the main CoreCycler directory'
        '# and change the settings accordingly',
        '# Do not change the settings inside this default.config.ini file directly,',
        '# as they will be reset to their default values on every start of CoreCycler',
        '',
        ''
    )

    [System.IO.File]::WriteAllLines($configDefaultPath, [string]::Join([Environment]::NewLine, ($noticeLines -Join [Environment]::NewLine), $DEFAULT_SETTINGS_STRING))
}



<#
.DESCRIPTION
    Check if the Automatic Test Mode feature was enabled and if yes, initialize it
.PARAMETER
    [Void]
.OUTPUTS
    [Void]
#>
function Initialize-AutomaticTestMode {
    # Not in automatic mode, remove the startup task and file
    if ($settings['AutomaticTestMode']['enableAutomaticAdjustment'] -lt 1) {
        Remove-AutoModeScheduledTask
        Remove-AutoModeFile
        return
    }

    Write-DebugText('Initializing Automatic Test Mode')

    # The Automatic Test Mode has been enabled, we require administrator privileges!
    Write-DebugText('Are we admin: ' + $areWeAdmin)


    if (!$areWeAdmin) {
        Write-Text('')
        Write-Text('')
        Write-ColorText('┌─────────────────────────────────┤ IMPORTANT ├────────────────────────────────┐') Yellow DarkRed
        Write-ColorText('│ ' + 'You have selected to use the Automatic Test Mode.'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + 'To be able to use this feature, the script needs to be run with'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + 'administrator privileges.'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + 'Trying to open a new window now.'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('└──────────────────────────────────────────────────────────────────────────────┘') Yellow DarkRed
        Write-Text('')
        Write-Text('')


        $title    = 'Open CoreCycler with administrator privileges?'
        $question = ' '
        $choices  = @(
            [System.Management.Automation.Host.ChoiceDescription]::new('&Yes', 'Open the script with admin rights')
            [System.Management.Automation.Host.ChoiceDescription]::new('&No', 'Abort')
        )
        $decision = $Host.UI.PromptForChoice($title, $question, $choices, 0)

        if ($decision -eq 0) {
            Write-Text('Trying to re-open in a new window with admin privileges')
            $newProcess = New-Object System.Diagnostics.ProcessStartInfo
            $newProcess.WorkingDirectory = $PSScriptRoot
            $newProcess.FileName = 'cmd'
            $newProcess.Arguments = '/K pushd "' + $PSScriptRoot + '" && "Run CoreCycler.bat" '
            $newProcess.Verb = 'runas'

            [Void] [System.Diagnostics.Process]::Start($newProcess)

            # Close this window, the new window should be opened
            [Void] $SendMessage::SendMessage($parentMainWindowHandle, $SendMessage::WM_CLOSE, 0, 0)
            exit
        }
        else {
            Write-ColorText('You did not select to open the script with administrator rights, but the') Red
            Write-ColorText('Automatic Test Mode feature requires it') Red
            Write-ColorText('Aborting') Red
            Exit-Script
        }
    }
    else {
        Write-DebugText('We have admin rights, proceeding')
    }


    # This is the array for the starting voltage values
    $voltageStartValuesArray  = $null

    $modeDescription = $(if ($isIntelProcessor) { 'voltage offset' } else { 'Curve Optimizer' })


    # This flag indicates that the .automode file existed and the startup scheduled task was run
    # So we had a crash while the script was running
    if (-not [String]::IsNullOrWhiteSpace($CoreFromAutoMode) -and [Int]$CoreFromAutoMode -gt -1) {
        Write-DebugText('The CoreFromAutoMode variable was passed from the command line: ' + $CoreFromAutoMode)

        # The setting for the automatic resume must also be activated
        if ($settings.AutomaticTestMode.enableResumeAfterUnexpectedExit -lt 1) {
            Write-DebugText('However the automatic resume test process setting is not active (anymore?)')
        }

        # We are in Automatic Test Mode with automatic resume after unexpected exit
        # So we're going to use the voltage values from the .automode file
        else {
            Write-DebugText('We''ll try to resume the test process with the voltage values from the .automode file')

            $Script:CoreFromAutoMode = [Int] $CoreFromAutoMode

            # Get the last used voltage settings
            # And increase the voltage value for the core that has thrown an error
            $autoModeInfo = Get-AutoModeFileContent

            # The value(s) from the .automode file
            $voltageStartValuesArray = $autoModeInfo['voltageValues']

            Write-DebugText('The Automatic Test Mode starting values from the .automode file:')
            Write-DebugText('We will increase this value because of the crash')
            Write-DebugText($voltageStartValuesArray)
        }
    }


    # The Automatic Test Mode without resuming from a reboot
    # Get the Automatic Test Mode starting values from the settings
    if (!$voltageStartValuesArray) {
        $voltageStartValuesString = $settings['AutomaticTestMode']['startValues']

        Write-DebugText('The Automatic Test Mode starting values from the settings:')
        Write-DebugText($voltageStartValuesString)

        # For Curve Optimizer, this setting has all the CO values for each core (or a single value for all)
        # For Intel, this has most likely only one entry, but can also contain one entry for each core (which should all be the same value though)
        # We do not yet have the ability to set the voltage on a per-core basis for Intel
        $voltageStartValuesArray = @($voltageStartValuesString -Split '\s+')
    }


    # An empty value or "default" should use the currently assigned voltage values, so get them
    if ($voltageStartValuesArray.Count -eq 0 -or $voltageStartValuesArray[0].ToString().ToLowerInvariant() -eq 'default') {
        if ($isIntelProcessor) {
            # Get the currently applied Intel voltage offset values
            $voltageStartValuesArray = Get-IntelVoltageOffset
        }
        else {
            # Get the currently applied Curve Optimizer values
            $voltageStartValuesArray = Get-CurveOptimizerValues
        }
    }


    # The number of settings must equal the number of cores or be exactly one value
    if ($voltageStartValuesArray.Count -ne $numPhysCores) {
        # If it's only a single value, apply this value to each core
        if ($voltageStartValuesArray.Count -eq 1 -and $voltageStartValuesArray[0] -Match '^\s*\-\d+\s*$') {
            $valueForAllCores = [Int] $voltageStartValuesArray[0]
            $voltageStartValuesArray = @($valueForAllCores) * $numPhysCores
        }
        else {
            $msg  = 'The number of ' + $modeDescription + ' starting values needs to match the number of cores'
            $msg += [Environment]::NewLine + 'or be a single value for all cores!'
            $msg += [Environment]::NewLine + '(' + $numPhysCores + ' cores found, but ' + $(if ($voltageStartValuesArray.Count -le $numPhysCores) { 'only ' } else { '' }) + $voltageStartValuesArray.Count + ' starting values)'

            Exit-WithFatalError -text $msg
        }
    }


    # We can have only integer values at this point
    $voltageStartValuesArray = $voltageStartValuesArray | ForEach-Object { [Int] $_ }


    # Curve Optimizer has a limit
    if (!$isIntelProcessor) {
        if (@($voltageStartValuesArray | Where-Object { [Math]::Abs($_) -gt $limitForCoValues }).Count -gt 0) {
            Exit-WithFatalError -text ('Found invalid values (either higher or lower than +-' + $limitForCoValues + ')' + [Environment]::NewLine + $voltageStartValuesArray)
        }
    }


    $Script:voltageStartingValues          = $voltageStartValuesArray.Clone()
    $Script:voltageCurrentValues           = $voltageStartValuesArray.Clone()
    $Script:useCurveOptimizer              = !$isIntelProcessor
    $Script:useIntelVoltageAdjustment      = $isIntelProcessor
    $Script:useAutomaticTestMode           = $true
    $Script:useAutomaticTestModeWithResume = ($settings.AutomaticTestMode.enableResumeAfterUnexpectedExit -gt 0)
    $Script:setVoltageOnlyForTestedCore    = ($settings.AutomaticTestMode.setVoltageOnlyForTestedCore -gt 0)


    if ($useAutomaticTestModeWithResume) {
        Write-VerboseText('Automatic Test Mode with resuming after unexpected exit enabled')

        # Add the Scheduled Task that will restart the script after an unexpected exit and on the following reboot (resp. login)
        Add-AutoModeScheduledTask
    }
    else {
        Write-VerboseText('Automatic Test Mode enabled')

        # But not the automatic resume, so remove the scheduled task and file
        Remove-AutoModeScheduledTask
        Remove-AutoModeFile
    }


    # Apply the starting values
    # Do these after the startup task has been created
    # But only if not settint the voltage just for the currently tested core
    if (!$setVoltageOnlyForTestedCore) {
        Set-NewVoltageValues
    }


    Write-VerboseText('The starting value(s):')
    Write-VerboseText($voltageStartValuesArray)
}



<#
.DESCRIPTION
    Get the currently applied Curve Optimizer values
.PARAMETER IgnoreCoreCount
    [Switch] (optional) If set, will not check if the returned array matches the number of physical cores (i.e. when the second CCD is disabled)
.PARAMETER IgnoreInvalidValues
    [Switch] (optional) If set, will not check if the returned array contains reasonable values (i.e. when the second CCD is disabled)
.OUTPUTS
    [Array] The Curve Optimizer values
#>
function Get-CurveOptimizerValues {
    param(
        [Parameter(Mandatory=$false)] [Switch] $IgnoreCoreCount,
        [Parameter(Mandatory=$false)] [Switch] $IgnoreInvalidValues
    )

    try {
        Write-DebugText('Trying to query for the Curve Optimizer values')

        $getCoValuesProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
        $getCoValuesProcessInfo.FileName = $pboCliTool
        $getCoValuesProcessInfo.Arguments = '--get-offsets-terse'
        $getCoValuesProcessInfo.Verb = 'runas'
        $getCoValuesProcessInfo.RedirectStandardError = $true
        $getCoValuesProcessInfo.RedirectStandardOutput = $true
        $getCoValuesProcessInfo.UseShellExecute = $false

        $getCoValuesProcess = New-Object System.Diagnostics.Process
        $getCoValuesProcess.StartInfo = $getCoValuesProcessInfo
        $null = $getCoValuesProcess.Start()

        $stdOut = $getCoValuesProcess.StandardOutput.ReadToEnd()
        $stdErr = $getCoValuesProcess.StandardError.ReadToEnd()

        if (!$getCoValuesProcess.WaitForExit(5000)) {
            $getCoValuesProcess.Kill()
            $getCoValuesProcess.Close()
            $getCoValuesProcess.Dispose()

            throw('Program didn''t exit within five seconds!')
        }

        $exitCode = $getCoValuesProcess.ExitCode

        $getCoValuesProcess.Close()
        $getCoValuesProcess.Dispose()


        if ($exitCode -ne 0) {
            $msg = 'Program terminated unexpectedly. Exit Code: ' + $exitCode

            if ($stdErr) {
                $msg += [Environment]::NewLine + $stdErr
            }

            if ($stdOut) {
                $msg += [Environment]::NewLine + $stdOut
            }

            throw($msg)
        }

        if ($stdErr -and $stdErr.Length -gt 0) {
            throw('Error message returned: ' + $stdErr)
        }

        if (!$stdOut -or $stdOut -eq '') {
            throw('Returned value was empty')
        }

        # Double trim to also remove any new lines
        $stdOut = $stdOut.Trim().Trim(' ', '"', '''', [Char]0x09)

        if (!$stdOut -or $stdOut -eq '') {
            throw('Returned value was empty')
        }

        $outputLines = @($stdOut -Split '\r?\n')

        Write-DebugText('Returned output:')

        $outputLines | ForEach-Object {
            Write-DebugText($_)
        }

        # Try to parse the the CO values
        # Multiple lines output:
        # > [maybe stuff]
        # > Current PBO offsets:
        # > -1,-1,-1,-1,-1,-1
        # > (empty line)
        $coArray = @(($outputLines[$outputLines.Count-1] -Split ',') | Where-Object { $_ -Match '\-?\d+' } | ForEach-Object { [Int] $_ } )

        Write-DebugText('The queried and parsed Curve Optimizer values:')
        Write-DebugText($coArray)

        if (!$IgnoreCoreCount.IsPresent) {
            if ($coArray.Count -ne $numPhysCores) {
                throw('Found ' + $coArray.Count + ' entries instead of the expected ' + $numPhysCores + ':' + [Environment]::NewLine + $coArray)
            }
        }

        # Only reasonable values
        if (!$IgnoreInvalidValues.IsPresent) {
            if (@($coArray | Where-Object { [Math]::Abs($_) -gt $limitForCoValues }).Count -gt 0) {
                throw('Found invalid values (either higher or lower than +-' + $limitForCoValues + ')' + [Environment]::NewLine + $coArray)
            }
        }

        return $coArray
    }
    catch {
        throw('Could not get the current Curve Optimizer values!' + [Environment]::NewLine + 'Reason: ' + $_)
    }
}



<#
.DESCRIPTION
    Set the new Curve Optimizer values
.PARAMETER
    [Void]
.OUTPUTS
    [Void]
#>
function Set-CurveOptimizerValues {
    Write-VerboseText('Trying to set the Curve Optimizer values')

    try {
        if ($voltageCurrentValues.Count -gt $numPhysCores) {
            Write-VerboseText('The amount of cores we''re trying to set is larger than the amount of physical cores!')
        }


        # If we only want to set the currently tested core, set the others to max(0, currentvalue)
        if ($setVoltageOnlyForTestedCore) {
            Write-DebugText('The flag to only set the voltage for the currently tested core is enabled')
            Write-DebugText('Currently tested core: ' + $Script:currentlyTestedCore)
            Write-DebugText('The original values:')
            Write-DebugText($voltageCurrentValues)

            if ([String]::IsNullOrWhiteSpace($Script:currentlyTestedCore)) {
                Write-DebugText('Core testing hasn''t started yet, resetting all cores')
            }

            $voltageValuesToUse = @()

            for ($i = 0; $i -lt $voltageCurrentValues.Count; $i++) {
                if ($i -eq $Script:currentlyTestedCore) {
                    $voltageValuesToUse += [Int] $voltageCurrentValues[$i]
                }
                else {
                    # We may have allowed higher values than 0
                    $voltageValuesToUse += [Math]::Max(0, $voltageCurrentValues[$i])
                }
            }

            Write-DebugText('The modified values:')
            Write-DebugText($voltageValuesToUse)
        }
        else {
            $voltageValuesToUse = $voltageCurrentValues.Clone()
        }

        $coString = $voltageValuesToUse -Join ','


        Write-VerboseText('The values to set:')
        Write-VerboseText($coString)

        $argumentString = '--offset ' + $coString

        $setCoValuesProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
        $setCoValuesProcessInfo.FileName = $pboCliTool
        $setCoValuesProcessInfo.Arguments = $argumentString
        $setCoValuesProcessInfo.Verb = 'runas'
        $setCoValuesProcessInfo.RedirectStandardError = $true
        $setCoValuesProcessInfo.RedirectStandardOutput = $true
        $setCoValuesProcessInfo.UseShellExecute = $false

        $setCoValuesProcess = New-Object System.Diagnostics.Process
        $setCoValuesProcess.StartInfo = $setCoValuesProcessInfo
        $null = $setCoValuesProcess.Start()

        $stdOut = $setCoValuesProcess.StandardOutput.ReadToEnd()
        $stdErr = $setCoValuesProcess.StandardError.ReadToEnd()

        if (!$setCoValuesProcess.WaitForExit(5000)) {
            $setCoValuesProcess.Kill()
            $setCoValuesProcess.Close()
            $setCoValuesProcess.Dispose()

            throw('Program didn''t exit within five seconds!')
        }

        $exitCode = $setCoValuesProcess.ExitCode
        $setCoValuesProcess.Close()
        $setCoValuesProcess.Dispose()


        if ($exitCode -ne 0) {
            $msg = 'Program terminated unexpectedly. Exit Code: ' + $exitCode

            if ($stdErr) {
                $msg += [Environment]::NewLine + $stdErr
            }

            if ($stdOut) {
                $msg += [Environment]::NewLine + $stdOut
            }

            throw($msg)
        }

        if ($stdErr -and $stdErr.Length -gt 0) {
            throw('Error message returned: ' + $stdErr)
        }

        # On success this returns the values that have been set
        if (!$stdOut -or $stdOut -eq '') {
            throw('Returned value was empty')
        }

        # Double trim to also remove any new lines
        $stdOut = $stdOut.Trim().Trim(' ', '"', '''', [Char]0x09)

        if ($stdOut -eq '') {
            throw('Returned value was empty')
        }

        Write-DebugText('Curve Optimizer values successfuly set:')

        $stdOutLines = @($stdOut -Split '\r?\n')
        $stdOutLines | ForEach-Object {
            Write-DebugText($_)
        }
    }
    catch {
        throw('Could not set the Curve Optimizer values!' + [Environment]::NewLine + 'Reason: ' + $_)
    }
}



<#
.DESCRIPTION
    Get the currently applied Intel voltage offset
.PARAMETER
    [Void]
.OUTPUTS
    [Int] The voltage offset
#>
function Get-IntelVoltageOffset {
    try {
        Write-DebugText('Trying to query for the Intel voltage offset values')

        $getIntelOffsetValuesProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
        $getIntelOffsetValuesProcessInfo.FileName = $intelCliTool
        $getIntelOffsetValuesProcessInfo.Arguments = 'show'
        $getIntelOffsetValuesProcessInfo.Verb = 'runas'
        $getIntelOffsetValuesProcessInfo.RedirectStandardError = $true
        $getIntelOffsetValuesProcessInfo.RedirectStandardOutput = $true
        $getIntelOffsetValuesProcessInfo.UseShellExecute = $false


        $getIntelOffsetValuesProcess = New-Object System.Diagnostics.Process
        $getIntelOffsetValuesProcess.StartInfo = $getIntelOffsetValuesProcessInfo
        $null = $getIntelOffsetValuesProcess.Start()


        $stdOut = $getIntelOffsetValuesProcess.StandardOutput.ReadToEnd()
        $stdErr = $getIntelOffsetValuesProcess.StandardError.ReadToEnd()

        if (!$getIntelOffsetValuesProcess.WaitForExit(5000)) {
            $getIntelOffsetValuesProcess.Kill()
            $getIntelOffsetValuesProcess.Close()
            $getIntelOffsetValuesProcess.Dispose()

            throw('Program didn''t exit within five seconds!')
        }

        $exitCode = $getIntelOffsetValuesProcess.ExitCode
        $getIntelOffsetValuesProcess.Close()
        $getIntelOffsetValuesProcess.Dispose()


        if ($exitCode -ne 0) {
            $msg = 'Program terminated unexpectedly. Exit Code: ' + $exitCode

            if ($stdErr) {
                $msg += [Environment]::NewLine + $stdErr
            }

            if ($stdOut) {
                $msg += [Environment]::NewLine + $stdOut
            }

            throw($msg)
        }

        if ($stdErr -and $stdErr.Length -gt 0) {
            throw('Error message returned: ' + $stdErr)
        }

        if (!$stdOut -or $stdOut -eq '') {
            throw('Returned value was empty')
        }


        # Try to parse the the voltage offset values
        # We're only interested in the "Plane 0", which is the CPU core voltage
        $coreVoltage = ($stdOut -Split '\r?\n') | Where-Object { $_ -Match 'Plane 0: (\-?\d+\.?\d*)' } | ForEach-Object { [Int][Math]::Round($Matches[1]) }

        Write-DebugText('The queried and parsed Intel voltage offset value:')
        Write-DebugText($coreVoltage)

        # Create an array for each core, maybe in the future we can set the voltage offset individually
        return @($coreVoltage) * $numPhysCores
    }
    catch {
        throw('Could not get the current Intel voltage offset value!' + [Environment]::NewLine + 'Reason: ' + $_)
    }
}



<#
.DESCRIPTION
    Set the new Intel voltage offset value
.PARAMETER
    [Void]
.OUTPUTS
    [Void]
#>
function Set-IntelVoltageOffset {
    try {
        Write-DebugText('Trying to set the Intel voltage offset value:')

        # 0 = Core voltage offset
        # 2 = CPU Cache voltage offset
        # Both values need to be set and need to be the same value
        $argumentString = 'set --allow-overvolt --commit 0 ' + $voltageCurrentValues[0] + ' 2 ' + $voltageCurrentValues[0]

        Write-VerboseText($argumentString)

        $setIntelOffsetValuesProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
        $setIntelOffsetValuesProcessInfo.FileName = $intelCliTool
        $setIntelOffsetValuesProcessInfo.Arguments = $argumentString
        $setIntelOffsetValuesProcessInfo.Verb = 'runas'
        $setIntelOffsetValuesProcessInfo.RedirectStandardError = $true
        $setIntelOffsetValuesProcessInfo.RedirectStandardOutput = $true
        $setIntelOffsetValuesProcessInfo.UseShellExecute = $false


        $setIntelOffsetValuesProcess = New-Object System.Diagnostics.Process
        $setIntelOffsetValuesProcess.StartInfo = $setIntelOffsetValuesProcessInfo
        $null = $setIntelOffsetValuesProcess.Start()


        $stdOut = $setIntelOffsetValuesProcess.StandardOutput.ReadToEnd()
        $stdErr = $setIntelOffsetValuesProcess.StandardError.ReadToEnd()

        if (!$setIntelOffsetValuesProcess.WaitForExit(5000)) {
            $setIntelOffsetValuesProcess.Kill()
            $setIntelOffsetValuesProcess.Close()
            $setIntelOffsetValuesProcess.Dispose()

            throw('Program didn''t exit within five seconds!')
        }

        $exitCode = $setIntelOffsetValuesProcess.ExitCode
        $setIntelOffsetValuesProcess.Close()
        $setIntelOffsetValuesProcess.Dispose()



        if ($exitCode -ne 0) {
            $msg = 'Program terminated unexpectedly. Exit Code: ' + $exitCode

            if ($stdErr) {
                $msg += [Environment]::NewLine + $stdErr
            }

            if ($stdOut) {
                $msg += [Environment]::NewLine + $stdOut
            }

            throw($msg)
        }

        if ($stdErr -and $stdErr.Length -gt 0) {
            throw('Error message returned: ' + $stdErr)
        }

        # On success this returns the values that have been set
        if (!$stdOut -or $stdOut -eq '') {
            throw('Returned value was empty')
        }

        # Double trim to also remove any new lines
        $stdOut = @($stdOut.Trim().Trim(' ', '"', '''', [Char]0x09) -Split '\r?\n') -Join ', '

        if ($stdOut -eq '') {
            throw('Returned value was empty')
        }

        Write-DebugText('Intel voltage offset values successfuly set:')
        Write-DebugText('"' + $stdOut + '"')
    }
    catch {
        throw('Could not set the Intel voltage offset values!' + [Environment]::NewLine + 'Reason: ' + $_)
    }
}



<#
.DESCRIPTION
    Sets the new Curve Optimizer / voltage offset values
#>
function Set-NewVoltageValues {
    if ($useCurveOptimizer) {
        Set-CurveOptimizerValues
    }
    elseif ($useIntelVoltageAdjustment) {
        Set-IntelVoltageOffset
    }
}



<#
.DESCRIPTION
    Get the formatted runtime per core string
.PARAMETER seconds
    Mixed. Either [Int] The runtime in seconds or [String] If set to "auto"
.OUTPUTS
    [String] The formatted runtime string
#>
function Get-FormattedRuntimePerCoreString {
    param (
        $seconds
    )

    if ($seconds.ToString().ToLowerInvariant() -eq 'auto') {
        if ($isAida64 -or $isLinpack) {
            $returnString = [Math]::Round($runtimePerCore/60, 2).ToString() + ' minutes (Auto-Mode)'
        }
        elseif (($isYCruncher -or $isYCruncherOld) -and !$isYCruncherWithLogging) {
            $returnString = $runtimePerCore.ToString() + ' seconds (' + [Math]::Round($runtimePerCore/60, 2).ToString() + ' minutes) (Auto-Mode)'
        }
        else {
            $returnString = 'AUTOMATIC'
        }

        return $returnString
    }


    $runtimePerCoreStringArray = @()
    $timeSpan = [TimeSpan]::FromSeconds($seconds)

    if ($timeSpan.Hours -ge 1) {
        $thisString = [String] $timeSpan.Hours + ' hour'

        if ($timeSpan.Hours -gt 1) {
            $thisString += 's'
        }

        $runtimePerCoreStringArray += $thisString
    }

    if ($timeSpan.Minutes -ge 1) {
        $thisString = [String] $timeSpan.Minutes + ' minute'

        if ($timeSpan.Minutes -gt 1) {
            $thisString += 's'
        }

        $runtimePerCoreStringArray += $thisString
    }


    if ($timeSpan.Seconds -ge 1) {
        $thisString = [String] $timeSpan.Seconds + ' second'

        if ($timeSpan.Seconds -gt 1) {
            $thisString += 's'
        }

        $runtimePerCoreStringArray += $thisString
    }

    return ($runtimePerCoreStringArray -Join ', ')
}



<#
.DESCRIPTION
    Get the estimated runtime per core for the y-cruncher "auto" setting
.PARAMETER
    [Void]
.OUTPUTS
    [Int] The runtime in seconds
#>
function Get-EstimatedYCruncherRuntimePerCore {
    # Selected tests * duration of test + time in suspension + buffer
    $oneRunLength  = $settings.yCruncher.tests.Count * $settings.yCruncher.testDuration
    $suspendedTime = ($settings.General.suspendPeriodically * $oneRunLength / $settings.Debug.tickInterval * (1000 / $settings.Debug.suspensionTime))
    $bufferTime    = $oneRunLength * 0.05 # Some extra buffer (5% of runtime per test)
    $estimatedTime = $oneRunLength + $suspendedTime + $bufferTime
    $estimatedTime = [Math]::Ceiling($estimatedTime)

    return $estimatedTime
}



<#
.DESCRIPTION
    Get the correct TortureWeak setting for the selected CPU settings
.PARAMETER
    [Void]
.OUTPUTS
    [Int] The calculated TortureWeak value
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
    - AVX512 is never available on Ryzen <= 5000
    - AVX512 is available beginning with Ryzen 7000
    - TODO: Need a way to detect if AVX512 is available or not
            There doesn't seem to be a good way to check this from inside PowerShell
            Prime95 will just crash if it is started with AVX-512 support on a not supported CPU
            As does Y-Cruncher

    All enabled:
    0

    AVX512 disabled:
    1048576   --> CPU_AVX512F

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
    $FMA3   = [Int]![Int]$prime95CPUSettings[$settings.mode].CpuSupportsFMA3
    $AVX    = [Int]![Int]$prime95CPUSettings[$settings.mode].CpuSupportsAVX
    $AVX512 = [Int]![Int]$prime95CPUSettings[$settings.mode].CpuSupportsAVX512

    # Add the various flag values if a feature is disabled
    $tortureWeakValue = ($AVX512 * 1048576) + ($FMA3 * 32768) + ($AVX * 16384)

    return $tortureWeakValue
}



<#
.DESCRIPTION
    Send a Start, Stop or Dismiss signal to Aida64
.PARAMETER command
    [String] The command to execute (Start, Stop, Dismiss, Clear)
.OUTPUTS
    [Void]
#>
function Send-CommandToAida64 {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseConsistentWhitespace', '')]  # The $SendMessage::PostMessage lines cause a "Use space after a comma" error if using MORE than one space...
    param(
        [Parameter(Mandatory=$true)] [String] $command
    )

    # No windowProcessMainWindowHandle? No good!
    if (!$windowProcessMainWindowHandle -or [String]::IsNullOrWhiteSpace($windowProcessMainWindowHandle)) {
        Write-VerboseText('Could not get the windowProcessMainWindowHandle!')
        return
    }

    $timestamp = Get-Date -Format HH:mm:ss
    Write-VerboseText($timestamp + ' - Trying to send the "' + $command + '" command to Aida64')

    if ($command.ToLowerInvariant() -eq 'start') {
        $KEY = $SendMessage::KEY_S
    }
    elseif ($command.ToLowerInvariant() -eq 'stop') {
        $KEY = $SendMessage::KEY_T
    }
    elseif ($command.ToLowerInvariant() -eq 'dismiss') {
        $KEY = $SendMessage::KEY_D
    }
    elseif ($command.ToLowerInvariant() -eq 'clear') {
        $KEY = $SendMessage::KEY_E
    }

    # This sends an ALT + KEY keystroke to the Aida64 main window
    [Void] $SendMessage::PostMessage($windowProcessMainWindowHandle, $SendMessage::WM_SYSKEYDOWN, $SendMessage::KEY_MENU, $SendMessage::GetLParam(1, $SendMessage::KEY_MENU, 0, 1, 0, 0))
    [Void] $SendMessage::PostMessage($windowProcessMainWindowHandle, $SendMessage::WM_SYSKEYDOWN, $KEY,                   $SendMessage::GetLParam(1, $KEY, 0, 1, 0, 0))
    [Void] $SendMessage::PostMessage($windowProcessMainWindowHandle, $SendMessage::KEY_UP,        $SendMessage::KEY_MENU, $SendMessage::GetLParam(1, $SendMessage::KEY_MENU, 0, 0, 1, 1))
    [Void] $SendMessage::PostMessage($windowProcessMainWindowHandle, $SendMessage::KEY_UP,        $KEY,                   $SendMessage::GetLParam(1, $KEY, 0, 0, 1, 1))


    # DEBUG
    # Just to be able to see the entries in Spy++ more easily
    #[Void] $SendMessage::PostMessage($windowProcessMainWindowHandle, $SendMessage::KEY_UP, 0, $SendMessage::GetLParam(0, 0, 0, 0, 0, 0))
    #[Void] $SendMessage::PostMessage($windowProcessMainWindowHandle, $SendMessage::KEY_UP, 0, $SendMessage::GetLParam(0, 0, 0, 0, 0, 0))
    #[Void] $SendMessage::PostMessage($windowProcessMainWindowHandle, $SendMessage::KEY_UP, 0, $SendMessage::GetLParam(0, 0, 0, 0, 0, 0))
    #[Void] $SendMessage::PostMessage($windowProcessMainWindowHandle, $SendMessage::KEY_UP, 0, $SendMessage::GetLParam(0, 0, 0, 0, 0, 0))
    #[Void] $SendMessage::PostMessage($windowProcessMainWindowHandle, $SendMessage::KEY_UP, 0, $SendMessage::GetLParam(0, 0, 0, 0, 0, 0))
}



<#
.DESCRIPTION
    Get the main window and stress test processes, as well as the main window handle, even if minimized to the tray
    Also get the ids of the threads that are running the stress test
    This will set global variables
.PARAMETER stopOnStressTestProcessNotFound
    [Bool] If set to false, will not throw an error if the stress test process was not found
.PARAMETER overrideNumberOfThreads
    [Int] If set, use this information to get the expected number of threads for the stress test program
.OUTPUTS
    [Void]
#>
function Get-StressTestProcessInformation {
    param(
        [Parameter(Mandatory=$false)] [Bool] $stopOnStressTestProcessNotFound = $true,
        [Parameter(Mandatory=$false)] $overrideNumberOfThreads
    )

    $windowObj                     = $null
    $filteredWindowObj             = $null
    $checkProcess                  = $null
    $thisStressTestProcess         = $null
    $thisStressTestProcessId       = $null
    $thisStressTestThreads         = @()
    $thisStressTestThreadIds       = @()
    $thisWindowProcess             = $null


    # Reset the global variables that are being assigned later
    $Script:windowProcess                 = $null
    $Script:windowProcessId               = $null
    $Script:windowProcessMainWindowHandle = $null
    $Script:stressTestProcess             = $null
    $Script:stressTestProcessId           = $null
    $Script:stressTestThreads             = @()
    $Script:stressTestThreadIds           = $null


    Write-VerboseText('Trying to get the stress test program main window handle')
    Write-VerboseText('Looking for these window names:')
    Write-VerboseText(($stressTestPrograms[$settings.General.stressTestProgram]['windowNames'] -Join ', '))

    # Try to to get the window and the stress test
    for ($i = 1; $i -le 30; $i++) {
        Start-Sleep -Milliseconds 250
        $timestamp = Get-Date -Format HH:mm:ss

        # This is the window object for the main window
        $windowObj = [GetWindows.Main]::GetWindows() | Where-Object {
            $_.WinTitle -Match ($stressTestPrograms[$settings.General.stressTestProgram]['windowNames'] -Join '|')
        }

        if ($windowObj -and ($windowObj | Get-Member WinTitle)) {
            Start-Sleep -Milliseconds 250
            Write-VerboseText($timestamp + ' - Window found')

            # This is the process object for the stress test. They may be the same, but not necessarily (e.g. Aida64)
            $thisStressTestProcess = Get-Process $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad'] -ErrorAction Ignore
            break
        }
        else {
            Write-VerboseText($timestamp + ' - ... no window found for these names...')
        }
    }


    # Still no main window found
    if (!($windowObj -and ($windowObj | Get-Member WinTitle))) {
        Write-VerboseText('Window not found by title, looking process name instead:')
        Write-VerboseText($stressTestPrograms[$settings.General.stressTestProgram]['processName'])

        # Check if the process for the main window exists
        $checkProcess = Get-Process $stressTestPrograms[$settings.General.stressTestProgram]['processName'] -ErrorAction Ignore

        # We found the main window process, one last check to get the main window object
        if ($checkProcess) {
            $windowObj = [GetWindows.Main]::GetWindows() | Where-Object {
                $_.WinTitle -Match ($stressTestPrograms[$settings.General.stressTestProgram]['windowNames'] -Join '|')
            }
        }
    }


    # Yeah, we can't find anything, throw that error
    if (!($windowObj -and ($windowObj | Get-Member WinTitle))) {
        if ($stopOnStressTestProcessNotFound) {
            # I could dump all of the window names here, but I'd rather not due to privacy reasons
            Write-ColorText('FATAL ERROR: Could not find a window instance for the stress test program!') Red
            Write-ColorText('Was looking for these window names:') Red
            Write-ColorText(($stressTestPrograms[$settings.General.stressTestProgram]['windowNames'] -Join ', ')) Yellow

            if ($checkProcess) {
                Write-ColorText('However, found a process with the process name "' + $stressTestPrograms[$settings.General.stressTestProgram]['processName'] + '":') Red

                $checkProcess | ForEach-Object {
                    Write-ColorText(' - ProcessName:  ' + $_.ProcessName) Yellow
                    Write-ColorText('   Process Path: ' + $_.Path) Yellow
                    Write-ColorText('   Process Id:   ' + $_.Id) Yellow
                    Write-ColorText('   Window Title: ' + $_.MainWindowTitle) Yellow
                }
            }

            Exit-WithFatalError -lineNumber (Get-ScriptLineNumber)
        }
        else {
            Write-VerboseText('Could not find the window instance for the stress test program!')

            Write-VerboseText('Was looking for these window names:')
            Write-VerboseText(($stressTestPrograms[$settings.General.stressTestProgram]['windowNames'] -Join ', '))

            if ($checkProcess) {
                Write-VerboseText('However, found a process with the process name "' + $stressTestPrograms[$settings.General.stressTestProgram]['processName'] + '":')

                $checkProcess | ForEach-Object {
                    Write-VerboseText(' - ProcessName:  ' + $_.ProcessName)
                    Write-VerboseText('   Process Path: ' + $_.Path)
                    Write-VerboseText('   Process Id:   ' + $_.Id)
                    Write-VerboseText('   Window Title: ' + $_.MainWindowTitle)
                }
            }
        }
    }


    Write-VerboseText('Found the following window(s) with these names:')

    $windowObj | ForEach-Object {
        $path = (Get-Process -Id $_.ProcessId -ErrorAction Ignore).Path
        Write-VerboseText(' - WinTitle:          ' + $_.WinTitle)
        Write-VerboseText('   MainWindowHandle:  ' + $_.MainWindowHandle)
        Write-VerboseText('   ProcessId:         ' + $_.ProcessId)
        Write-VerboseText('   Process Path:      ' + $_.ProcessPath)
        Write-VerboseText('   Process Path (PS): ' + $path)
    }


    # There might be another window open with the same name as the stress test program (e.g. an Explorer window)
    # Select the correct one
    $searchForProcess = ('.*' + $stressTestPrograms[$settings.General.stressTestProgram]['processName'] + '\.' + $stressTestPrograms[$settings.General.stressTestProgram]['processNameExt'] + '$')

    # If we're running the wrapper for y-cruncher to capture the output, we need to check the commandline
    if ($isYCruncherWithLogging) {
        Write-VerboseText('enableYCruncherLoggingWrapper has been set, special handling')

        $searchForProcess = '*"' + $stressTestPrograms[$settings.General.stressTestProgram]['fullPathToLoadExe'] + '.' + $stressTestPrograms[$settings.General.stressTestProgram]['processNameExt'] + '"*'

        Write-VerboseText('Filtering the windows for "' + $searchForProcess + '":')

        $filteredWindowObj = $windowObj | Where-Object {
            $commandLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.ProcessId)" | Select-Object CommandLine).CommandLine
            $hasMatch = $commandLine -like $searchForProcess

            Write-VerboseText(' - ProcessId:         ' + $_.ProcessId)
            Write-VerboseText('   searchForProcess:  ' + $searchForProcess)
            Write-VerboseText('   CommandLine:       ' + $commandLine)
            Write-VerboseText('   hasMatch:          ' + $hasMatch)

            # Return true if the window was identified successfully, so that filteredWindowObj will be the current object
            return $hasMatch
        }
    }

    # Also for Linpack we need to check the command line
    elseif ($isLinpack) {
        Write-VerboseText('Linpack has been selected, special handling')

        $searchForProcess = '*"' + $stressTestPrograms[$settings.General.stressTestProgram]['fullPathToLoadExe'] + '.' + $stressTestPrograms[$settings.General.stressTestProgram]['processNameExt'] + '"*'

        Write-VerboseText('Filtering the windows for "' + $searchForProcess + '":')

        $filteredWindowObj = $windowObj | Where-Object {
            $cimProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $($_.ProcessId)"
            $commandLine = ($cimProcess | Select-Object CommandLine).CommandLine
            $hasMatch = $commandLine -like $searchForProcess

            Write-VerboseText(' - ProcessId:         ' + $_.ProcessId)
            Write-VerboseText('   searchForProcess:  ' + $searchForProcess)
            Write-VerboseText('   CommandLine:       ' + $commandLine)
            Write-VerboseText('   hasMatch:          ' + $hasMatch)

            # Return true if the window was identified successfully, so that filteredWindowObj will be the current object
            return $hasMatch
        }
    }

    # Regular y-cruncher or other stress test programs
    else {
        Write-VerboseText('Filtering the windows for "' + $searchForProcess + '":')

        $filteredWindowObj = $windowObj | Where-Object {
            #(Get-Process -Id $_.ProcessId -ErrorAction Ignore).Path -Match $searchForProcess
            $_.ProcessPath -Match $searchForProcess
        }
    }


    # We haven't found the window for the stress test. It may be buried inside the Windows Terminal
    # If Windows Terminal is installed and the default, we cannot search for the window name directly, as Windows Terminal is hijacking it
    # I.e. the WindowsTerminal.exe will be the found window, and not the powershell.exe that's running inside it
    # Therefore, search through all the processes that have the original windowObj as their parent and search their command line
    # There's apparently no way to get this window by its name then
    # Search for the executable and select it's parent window instead
    if (!$filteredWindowObj) {
        Write-DebugText('Couldn''t find the window process, it may be buried inside the Windows Terminal')
        Write-DebugText('Looking for the stress test process instead...')

        # Look for any instances of that process that are run from the CoreCycler directory
        # Need to escape the backslashes
        $searchForProcessWql = ($stressTestPrograms[$settings.General.stressTestProgram]['fullPathToLoadExe'] + '.' + $stressTestPrograms[$settings.General.stressTestProgram]['processNameExt']).Replace('\', '\\')

        Write-DebugText('Looking for the process where the ExecutablePath is:')
        Write-DebugText($searchForProcessWql)

        $cimStressTestProcesses = Get-CimInstance Win32_Process -Filter "ExecutablePath = '$searchForProcessWql'"

        # This should really be just one process now, with one parent process
        # Also, we have our stress test process now, and wouldn't need to get it again below, but oh well
        foreach ($currentProcess in $cimStressTestProcesses) {
            # Get the parent process for the stress test process
            $parentProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $($currentProcess.ParentProcessId)"

            # We need to filter our main windows again for this found process, otherwise we won't have a MainWindowHandle
            # The WinTitle may stay empty though
            $filteredWindowObj = [GetWindows.Main]::GetWindows() | Where-Object {
                $hasMatch = $_.ProcessId -eq $parentProcess.ProcessId

                if ($hasMatch) {
                    Write-VerboseText('Found a matching main window:')
                    Write-VerboseText(' - ProcessId:         ' + $_.ProcessId)
                    Write-VerboseText('   Process Path:      ' + $_.ProcessPath)
                    Write-VerboseText('   WinTitle:          ' + $_.WinTitle)
                    Write-VerboseText('   MainWindowHandle:  ' + $_.MainWindowHandle)
                }

                return $hasMatch
            }

            # Break if the window was identified successfully, so that filteredWindowObj will be the current process object
            if ($filteredWindowObj) {
                break
            }
        }
    }


    Write-DebugText('Found the following windows:')

    $filteredWindowObj | ForEach-Object {
        $path = (Get-Process -Id $_.ProcessId -ErrorAction Ignore).Path
        Write-VerboseText(' - WinTitle:          ' + $_.WinTitle)
        Write-VerboseText('   MainWindowHandle:  ' + $_.MainWindowHandle)
        Write-VerboseText('   ProcessId:         ' + $_.ProcessId)
        Write-VerboseText('   Process Path:      ' + $_.ProcessPath)
        Write-VerboseText('   Process Path (PS): ' + $path)
    }


    # No window found!
    if (!$filteredWindowObj) {
        if ($stopOnStressTestProcessNotFound) {
            Write-ColorText('FATAL ERROR: Could not find the correct stress test window!') Red
            Write-ColorText('No window found that matches "' + $searchForProcess + '"') Red
            Exit-WithFatalError
        }

        # Not found anything, just return if the flag to not stop is set
        else {
            return
        }
    }




    # Multiple processes found with the same name AND process name
    # Abort and let the user close these programs
    if ($filteredWindowObj -is [Array]) {
        Write-ColorText('FATAL ERROR: Could not find the correct stress test window!') Red
        Write-ColorText('There exist multiple windows with the same name as the stress test program:') Red

        $filteredWindowObj | ForEach-Object {
            #$path = (Get-Process -Id $_.ProcessId -ErrorAction Ignore).Path
            Write-ColorText(' - Windows Title: ' + $_.WinTitle) Yellow
            #Write-ColorText('   Process Path:  ' + $path) Yellow
            Write-ColorText('   Process Path:  ' + $_.ProcessPath) Yellow
            Write-ColorText('   Process Id:    ' + $_.ProcessId) Yellow
        }

        Write-ColorText('Please close these windows and try again.') Red
        Exit-WithFatalError
    }


    # We've now found our main window object, get the corresponding PowerShell process object for it
    $thisWindowProcess = Get-Process -Id $filteredWindowObj.ProcessId -ErrorAction Ignore


    # Also, the process performing the stress test can actually be different to the main window of the stress test program
    # If so, search for it as well
    if ($stressTestPrograms[$settings.General.stressTestProgram]['processName'] -ne $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad']) {
        Write-VerboseText('The process performing the stress test is NOT the same as the main window!')
        Write-VerboseText('Searching for process "' + $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad'] + '"...')


        for ($i = 1; $i -le 30; $i++) {
            $timestamp = Get-Date -Format HH:mm:ss
            $thisStressTestProcess = Get-Process $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad'] -ErrorAction Ignore

            if ($thisStressTestProcess) {
                $thisStressTestProcessId = $thisStressTestProcess.Id
                Write-VerboseText($timestamp + ' - Found with ID: ' + $thisStressTestProcessId)

                break
            }
            else {
                Write-VerboseText($timestamp + ' - ... not found')
            }

            Start-Sleep -Milliseconds 250
        }


        if (!$thisStressTestProcessId) {
            $message = 'Could not determine the stress test program process ID! (looking for ' + $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad'] + ')'

            # Only throw an error if the flag to do so was set
            # It may be possible that e.g. the main window of Aida64 was started, but no stress test is currently running
            if ($stopOnStressTestProcessNotFound) {
                Exit-WithFatalError -text $message
            }
            else {
                Write-VerboseText($message)
            }
        }
    }

    # The stress test and the main window are the same process
    else {
        Write-VerboseText('The process performing the stress test is the same as the main window')

        $thisStressTestProcess   = $thisWindowProcess
        $thisStressTestProcessId = $thisWindowProcess.Id
    }

    Write-DebugText('The stress test process id: ' + $thisStressTestProcessId)


    # Try to get the threads of the stress test process that are actually responsible for the CPU load
    # The number of threads for the stress test process should be equal to $numberOfThreads
    [Int] $defaultNumberOfThreads = $settings.General.numberOfThreads

    # The number of worker threads also depend on if we're starting on a core that supports only one thread (-> $overrideNumberOfThreads)
    [Int] $expectedNumberOfThreads = $(if ($overrideNumberOfThreads -gt 0) { $overrideNumberOfThreads } else { $defaultNumberOfThreads })


    # Expect for Aida64, which spawns different amount of worker threads for different tests
    # Also, Aida64 doesn't seem to always immediately start all the stress tests
    # The amount of threads depends on the selected test mode
    #                                        │Threads per test
    #                                        │ 1 Test                  │ 2 Tests                                 │ 3 Tests                     │ All 4 │
    #                                        │ CACHE │     │     │     │ CACHE │ CACHE │ CACHE │     │     │     │ CACHE │ CACHE │ CACHE │     │ CACHE │
    # CPUMask                                │       │ CPU │     │     │  CPU  │       │       │ CPU │ CPU │     │  CPU  │  CPU  │       │ CPU │  CPU  │
    #                                        │       │     │ FPU │     │       │  FPU  │       │ FPU │     │ FPU │  FPU  │       │  FPU  │ FPU │  FPU  │
    #                                        │       │     │     │ RAM │       │       │  RAM  │     │ RAM │ RAM │       │  RAM  │  RAM  │ RAM │  RAM  │
    # ───────────────────────────────────────┼───────┼─────┼─────┼─────┼───────┼───────┼───────┼─────┼─────┼─────┼───────┼───────┼───────┼─────┼───────┤
    # 0x00000004 [decimal  4, CPU 2]         │   4   │  1  │  2  │  2  │   4   │   5   │   5   │  2  │  2  │  3  │   5   │   5   │   6   │  3  │   6   │
    # 0x0000000C [decimal 12, CPU 2 & 3]     │   7   │  2  │  3  │  3  │   8   │   9   │   9   │  4  │  4  │  5  │  10   │   8   │  11   │  6  │  12   │
    # 0x0000001C [decimal 28, CPU 2 & 3 & 4] │  10   │     │     │     │       │       │       │     │     │     │       │       │       │     │       │
    #
    # CACHE                     4, 7 -> numberOfThreads * 3 + 1
    #         CPU               1, 2 -> numberOfThreads
    #               FPU         2, 3 -> numberOfThreads + 1
    #                     RAM   2, 3 -> numberOfThreads + 1
    #
    # CACHE + CPU               4, 8 -> numberOfThreads * 3 + numberOfThreads
    # CACHE       + FPU         5, 9 -> numberOfThreads * 3 + numberOfThreads + 1
    #         CPU + FPU         2, 4 -> numberOfThreads + numberOfThreads
    #         CPU       + RAM   2, 4 -> numberOfThreads + numberOfThreads
    #               FPU + RAM   3, 5 -> numberOfThreads + numberOfThreads + 1
    #
    # CACHE + CPU + FPU         5,10 -> numberOfThreads * 3 + numberOfThreads + numberOfThreads
    # CACHE + CPU       + RAM   5, 8 -> I can't make any sense of it
    # CACHE       + FPU + RAM   6,11 ->
    #         CPU + FPU + RAM   3, 6 ->
    #
    # CACHE + CPU + FPU + RAM   6,12 ->

    # Use the observed amount of threads, hopefully they're always the same
    # TODO: figure out the algorithm that determines the number of worker threads being deployed
    $threadsForAida64 = @{
        'CACHE'             = @(4, 7)
        'CPU'               = @(1, 2)
        'FPU'               = @(2, 3)
        'RAM'               = @(2, 3)

        'CACHE,CPU'         = @(4, 8)
        'CACHE,FPU'         = @(5, 9)
        'CPU,FPU'           = @(2, 4)
        'CPU,RAM'           = @(2, 4)
        'FPU,RAM'           = @(3, 5)

        'CACHE,CPU,FPU'     = @(5, 10)
        'CACHE,CPU,RAM'     = @(5, 8)
        'CACHE,FPU,RAM'     = @(6, 11)
        'CPU,FPU,RAM'       = @(3, 6)

        'CACHE,CPU,FPU,RAM' = @(6, 12)
    }

    if ($isAida64) {
        Write-DebugText('Aida64 has been selected, using lookup table for the amount of worker threads')
        $modeString = (($settings.Aida64.mode -Split '\s*,\s*' | Where-Object { $_.Length -gt 0 } | Sort-Object) -Join ',').ToUpperInvariant()

        Write-DebugText('The mode string: ' + $modeString)

        $defaultIndex = $(if ($settings.General.numberOfThreads -eq 1) { 0 } else { 1 })
        $index = $(if ($overrideNumberOfThreads -gt 0) { $(if ($overrideNumberOfThreads -eq 1) { 0 } else { 1 }) } else { $defaultIndex })

        Write-DebugText('The default index: ' + $defaultIndex)
        Write-DebugText('The final index:   ' + $index)

        $expectedNumberOfThreads = $threadsForAida64[$modeString][$index]
    }


    Write-DebugText('The expected number of threads to find: ' + $expectedNumberOfThreads)

    if ($expectedNumberOfThreads -lt 1) {
        Write-DebugText('Not looking for the threads (because -1)')
    }


    # Only execute this if we actually expect threads to find
    if ($expectedNumberOfThreads -gt 0 -and $overrideNumberOfThreads -ne -1) {
        # Get the threads that are running the stress test
        Write-DebugText('Trying to get the threads that are running the stress test')

        # We assume that these are threads with the ThreadState = "Running" and are using CPU power
        # This is not always true however, Aida64 spawns 4 threads, of which two are "Running" and two are "Ready"
        # For Prime95 and y-cruncher, this should either be one or two threads
        # For Aida64, we will have to deal with four threads
        # And actually for Aida64, we cannot guarantee that all the threads are using CPU time already
        # Also it's using a dedicated stress test process, so we're just going to use all of the threads
        $maxLoops = 5
        $maxIterationsPerLoop = 10

        :LoopGetThreads for ($loop = 0; $loop -le $maxLoops; $loop++) {
            $loopTimestamp = Get-Date -Format 'HH:mm:ss'

            if ($loop -gt 0) {
                Write-Text($loopTimestamp + ' - Stress test process threads not found yet, trying again... (' + $loop + ' of ' + $maxLoops + ')')
            }

            for ($i=1; $i -le $maxIterationsPerLoop; $i++) {
                Write-DebugText('Trying to get the threads (loop: ' + $loop + ' - iteration: ' + $i + ')')

                # There seems to be some caching involved, which sometimes prevents this from getting the correct thread states
                # So we're using a job to get around this issue
                $thisStressTestThreads = Start-Job -ScriptBlock {
                    # Can't use the process directly, it fails
                    $thisProcess = Get-Process -Id $args[0] -ErrorAction Ignore

                    # The process doesn't exist anymore
                    if (!$thisProcess) {
                        return 999
                    }

                    $thisProcess.Threads | Where-Object {
                        ($_ | Get-Member TotalProcessorTime) -and
                        $null -ne $_.TotalProcessorTime -and
                        $_.TotalProcessorTime.Ticks -ne 0 -and
                        $_.ThreadState -match '^Running$|^Ready$'
                    } | Sort-Object -Property Id
                } -ArgumentList $thisStressTestProcess.Id | Wait-Job | Receive-Job

                if ($thisStressTestThreads -eq 999) {
                    Exit-WithFatalError('Could not find the stress test process while checking for its threads!')
                }

                $thisStressTestThreads = @($thisStressTestThreads)  # Cast to an array, so that .Count is always available
                $numFound = $thisStressTestThreads.Count

                if ($numFound -ne $expectedNumberOfThreads) {
                    Write-DebugText('Incorrect number of threads found (' + $numFound + ' instead of ' + $expectedNumberOfThreads + '), trying again [' + $i + ']')
                    Start-Sleep -Milliseconds 500
                }
                else {
                    Write-DebugText('Found the expected number of threads (' + $numFound + ' = ' + $expectedNumberOfThreads + ')')
                    break LoopGetThreads
                }
            }


            $thisStressTestThreadIds = $thisStressTestThreads | ForEach-Object { $_.Id }

            Write-VerboseText('Thread IDs found that are running the stress test: ' + $thisStressTestThreadIds)

            # Aida64 needs special treatment :x
            # Some of the threads seem to be in a "Wait" state even if it's running?
            if ($thisStressTestThreads.Count -ne $expectedNumberOfThreads -and $isAida64) {
                Write-DebugText('Loop ' + $loop + ' unsuccessful, waiting a bit for the next')
                Start-Sleep -Milliseconds 2000
            }
        }


        if ($thisStressTestThreads.Count -ne $expectedNumberOfThreads) {
            # Issue #111
            # This may happen when the stress test immediately throws an error after being started, but before the check for the threads happens
            # So check for new log file entries
            # It's hard to debug
            <#
            try {
                # TODO: Somehow get the actual core number
                Test-StressTestProgrammIsRunning -coreNumber $actualCoreNumber -coreStartDate $startDateThisCore
            }

            # Some error happened in or with the stress test program
            catch {
                $params = @{
                    'checkType'          = 'TICK'
                    'actualCoreNumber'   = $actualCoreNumber
                    'coreTestOrderArray' = $coreTestOrderArray
                    'coreIndex'          = [Ref] $coreIndex
                    'ExceptionObj'       = $_
                    'ErrorObj'           = $Error
                }

                Resolve-StressTestProgrammIsRunningError @params

                # TODO: Somehow proceed to the next core
            }
            #>




            Write-ColorText('FATAL ERROR: Incorrect number of threads found that could be running the stress test!') Red
            Write-ColorText('             Found ' + $thisStressTestThreads.Count + ' threads, but expected ' + $expectedNumberOfThreads) Red

            Write-DebugText('The process id:                      ' + $thisStressTestProcess.Id)

            if ($thisStressTestProcess -and $thisStressTestProcess.Threads -and @($thisStressTestProcess.Threads).Count -gt 0) {
                $threads       = $thisStressTestProcess.Threads | Sort-Object -Property Id
                $threadIds     = ($threads | Select-Object -Property Id).Id -Join ', '
                $threadsString = $threads | Format-Table 'Id', 'ThreadState', 'TotalProcessorTime', 'WaitReason', 'ProcessorAffinity' | Out-String
                $possibleStressTestThreadsIds    = @()
                $possibleStressTestThreadsString = ''

                # We need this always to be an array
                $possibleStressTestThreads = @(
                    $thisStressTestProcess.Threads | Where-Object {
                        ($_ | Get-Member TotalProcessorTime) -and
                        $null -ne $_.TotalProcessorTime -and
                        $_.TotalProcessorTime.Ticks -ne 0 -and
                        $_.ThreadState -match '^Running$|^Ready$'
                    }
                )

                if ($possibleStressTestThreads.Count -gt 0) {
                    $possibleStressTestThreads       = $possibleStressTestThreads | Sort-Object -Property Id
                    $possibleStressTestThreadsIds    = ($possibleStressTestThreads | Select-Object -Property Id).Id -Join ', '
                    $possibleStressTestThreadsString = $possibleStressTestThreads | Format-Table 'Id', 'ThreadState', 'TotalProcessorTime', 'WaitReason', 'ProcessorAffinity' | Out-String
                }

                Write-DebugText('The stress test thread ids:          ' + $threadIds)
                Write-DebugText('The possible stress test thread ids: ' + $possibleStressTestThreadsIds)

                Write-DebugText('All of the threads of the process:')
                Write-DebugText($threadsString)

                Write-DebugText('All of the possible stress test threads of the process:')
                Write-DebugText($possibleStressTestThreadsString)
            }

            Exit-WithFatalError
        }
    }


    # Override the global script variables
    $Script:windowProcess                 = $thisWindowProcess
    $Script:windowProcessId               = $filteredWindowObj.ProcessId
    $Script:windowProcessMainWindowHandle = $filteredWindowObj.MainWindowHandle
    $Script:stressTestProcess             = $thisStressTestProcess
    $Script:stressTestProcessId           = $thisStressTestProcessId
    $Script:stressTestThreads             = $thisStressTestThreads
    $Script:stressTestThreadIds           = $thisStressTestThreadIds

    Write-VerboseText('Main window handle:       ' + $Script:windowProcessMainWindowHandle)
    Write-VerboseText('Main window process name: ' + $Script:windowProcess.ProcessName)
    Write-VerboseText('Main window process ID:   ' + $Script:windowProcessId)

    if ($Script:stressTestProcess) {
        Write-VerboseText('Stress test process name: ' + $Script:stressTestProcess.ProcessName)
        Write-VerboseText('Stress test process ID:   ' + $Script:stressTestProcessId)
        Write-VerboseText('Stress test thread IDs:   ' + $Script:stressTestThreadIds)
    }
    else {
        Write-VerboseText('Stress test process:      Not found (but flag is set to ignore)')
    }
}



<#
.DESCRIPTION
    Check if Prime95 exists
.PARAMETER
    [Void]
.OUTPUTS
    [Void]
#>
function Test-Prime95 {
    # This may be prime95 or prime95_dev
    $p95Type = $settings.General.stressTestProgram

    # Check if the prime95.exe exists
    Write-VerboseText('Checking if prime95.exe exists at:')
    Write-VerboseText($stressTestPrograms[$p95Type]['fullPathToExe'] + '.' + $stressTestPrograms[$p95Type]['processNameExt'])

    if (!(Test-Path ($stressTestPrograms[$p95Type]['fullPathToExe'] + '.' + $stressTestPrograms[$p95Type]['processNameExt']) -PathType Leaf)) {
        Write-ColorText('FATAL ERROR: Could not find Prime95!') Red
        Write-ColorText('Make sure to download and extract Prime95 into the following directory:') Red
        Write-ColorText($stressTestPrograms[$p95Type]['absoluteInstallPath']) Yellow
        Write-Text ''
        Write-ColorText('You can download Prime95 from:') Red
        Write-ColorText('https://www.mersenne.org/download/') Cyan
        Exit-WithFatalError
    }
}



<#
.DESCRIPTION
    Get the version info for Prime95
.PARAMETER
    [Void]
.OUTPUTS
    [Array] An array representing the version number (e.g. 30.8.0 -> [30, 8, 0])
#>
function Get-Prime95Version {
    # This may be prime95 or prime95_dev
    $p95Type = $settings.General.stressTestProgram
    Write-VerboseText('Checking the Prime95 version...')
    $itemVersionInfo = (Get-Item ($stressTestPrograms[$p95Type]['fullPathToExe'] + '.' + $stressTestPrograms[$p95Type]['processNameExt'])).VersionInfo

    $p95Version = $(
        $itemVersionInfo.ProductMajorPart,
        $itemVersionInfo.ProductMinorPart,
        $itemVersionInfo.ProductBuildPart
    )

    Write-VerboseText('Prime95 Version:')
    Write-VerboseText($p95Version)

    return $p95Version
}



<#
.DESCRIPTION
    Create the Prime95 config files (local.txt & prime.txt)
    This depends on the $settings.mode variable
    And also on the Prime95 version
.PARAMETER
    [Void]
.PARAMETER overrideNumberOfThreads
    [Int] If this is set, use this value instead of $settings.General.numberOfThreads
.OUTPUTS
    [Void]
#>
function Initialize-Prime95 {
    param(
        [Parameter(Mandatory=$false)] $overrideNumberOfThreads
    )

    # This may be prime95 or prime95_dev
    $p95Type = $settings.General.stressTestProgram

    # Get the Prime95 version, settings have changed after 30.6, and again for 30.10
    $prime95Version = Get-Prime95Version
    $isMaxPrime95_30_6  = $false
    $isMaxPrime95_30_9  = $false
    $isMaxPrime95_30_19 = $false
    $isNewerPrime95     = $false    # When the user has added a new prime version that we didn't test
    $useOnlyPrimeTxt    = $false

    if ($prime95Version[0] -le 30 -and $prime95Version[1] -le 6) {
        $isMaxPrime95_30_6 = $true
    }
    if ($prime95Version[0] -eq 30 -and $prime95Version[1] -le 9) {
        $isMaxPrime95_30_9 = $true
    }
    if ($prime95Version[0] -eq 30 -and $prime95Version[1] -le 19) {
        $isMaxPrime95_30_19 = $true
    }
    if (($prime95Version[0] -eq 30 -and $prime95Version[1] -ge 20) -or $prime95Version[0] -gt 30) {
        $isNewerPrime95  = $true
        $Script:showPrime95NewWarning = $true       # Inform the user that this version of Prime95 has not yet been tested with CoreCycler
    }
    if ($isNewerPrime95 -or $isMaxPrime95_30_19 -and !$isMaxPrime95_30_9) {
        $useOnlyPrimeTxt = $true
    }


    Write-DebugText('isMaxPrime95_30_6:  ' + $isMaxPrime95_30_6)
    Write-DebugText('isMaxPrime95_30_9:  ' + $isMaxPrime95_30_9)
    Write-DebugText('isMaxPrime95_30_19: ' + $isMaxPrime95_30_19)
    Write-DebugText('isNewerPrime95:     ' + $isNewerPrime95)
    Write-DebugText('useOnlyPrimeTxt:    ' + $useOnlyPrimeTxt)


    # Set various global variables we need for Prime95
    $Script:prime95CPUSettings = @{
        SSE    = @{
            CpuSupportsSSE    = 1
            CpuSupportsSSE2   = 1
            CpuSupportsAVX    = 0
            CpuSupportsAVX2   = 0
            CpuSupportsFMA3   = 0
            CpuSupportsAVX512 = 0
        }

        AVX    = @{
            CpuSupportsSSE    = 1
            CpuSupportsSSE2   = 1
            CpuSupportsAVX    = 1
            CpuSupportsAVX2   = 0
            CpuSupportsFMA3   = 0
            CpuSupportsAVX512 = 0
        }

        AVX2   = @{
            CpuSupportsSSE    = 1
            CpuSupportsSSE2   = 1
            CpuSupportsAVX    = 1
            CpuSupportsAVX2   = 1
            CpuSupportsFMA3   = 1
            CpuSupportsAVX512 = 0
        }

        AVX512 = @{
            CpuSupportsSSE    = 1
            CpuSupportsSSE2   = 1
            CpuSupportsAVX    = 1
            CpuSupportsAVX2   = 1
            CpuSupportsFMA3   = 1
            CpuSupportsAVX512 = 1
        }

        CUSTOM = @{
            CpuSupportsSSE    = 1
            CpuSupportsSSE2   = 1
            CpuSupportsAVX    = $settings.Prime95Custom.CpuSupportsAVX
            CpuSupportsAVX2   = $settings.Prime95Custom.CpuSupportsAVX2
            CpuSupportsFMA3   = $settings.Prime95Custom.CpuSupportsFMA3
            CpuSupportsAVX512 = $settings.Prime95Custom.CpuSupportsAVX512
        }
    }


    # The various FFT sizes for Prime95
    # Used to determine where an error likely happened
    # Note: These are different depending on the selected mode (SSE, AVX, AVX2)!
    # Note: These are Int/Int32 numbers, you will not find a number cast to Int64 in this array (with e.g. [Array]::indexOf)!
    # SSE:    4, 5, 6, 8, 10, 12, 14, 16,     20,     24,     28,     32,         40, 48, 56,     64, 72, 80, 84, 96,      112,      128,      144, 160,      192,      224, 240, 256,      288, 320, 336, 384, 400, 448, 480, 512, 560, 576, 640, 672, 720, 768, 800,      896, 960, 1024, 1120, 1152, 1200, 1280, 1344, 1440, 1536, 1600, 1680, 1728, 1792, 1920, 2048, 2240, 2304, 2400, 2560, 2688, 2800, 2880, 3072, 3200, 3360, 3456, 3584, 3840,       4096, 4480, 4608, 4800, 5120, 5376, 5600, 5760, 6144, 6400, 6720, 6912, 7168, 7680, 8000,       8192, 8960, 9216, 9600, 10240, 10752, 11200, 11520, 12288, 12800, 13440, 13824, 14336, 15360, 16000,        16384, 17920, 18432, 19200, 20480, 21504, 22400, 23040, 24576, 25600, 26880, 27648, 28672, 30720, 32000, 32768
    # AVX:    4, 5, 6, 8, 10, 12, 15, 16, 18, 20, 21, 24, 25, 28,     32, 35, 36, 40, 48, 50, 60, 64, 72, 80, 84, 96, 100, 112, 120, 128, 140, 144, 160, 168, 192, 200, 224, 240, 256,      288, 320, 336, 384, 400, 448, 480, 512, 560, 576, 640, 672, 720, 768, 800, 864, 896, 960, 1024,       1152,       1280, 1344, 1440, 1536, 1600, 1680, 1728, 1792, 1920, 2048,       2304, 2400, 2560, 2688,       2880, 3072, 3200, 3360, 3456, 3584, 3840, 4032, 4096, 4480, 4608, 4800, 5120, 5376,       5760, 6144, 6400, 6720, 6912, 7168, 7680, 8000,       8192, 8960, 9216, 9600, 10240, 10752,        11520, 12288, 12800, 13440, 13824, 14336, 15360, 16000, 16128, 16384, 17920, 18432, 19200, 20480, 21504, 22400, 23040, 24576, 25600, 26880,        28672, 30720, 32000, 32768
    # AVX2:   4, 5, 6, 8, 10, 12, 15, 16, 18, 20, 21, 24, 25, 28, 30, 32, 35, 36, 40, 48, 50, 60, 64, 72, 80, 84, 96, 100, 112, 120, 128,      144, 160, 168, 192, 200, 224, 240, 256, 280, 288, 320, 336, 384, 400, 448, 480, 512, 560,      640, 672,      768, 800,      896, 960, 1024, 1120, 1152,       1280, 1344, 1440, 1536, 1600, 1680,       1792, 1920, 2048, 2240, 2304, 2400, 2560, 2688, 2800, 2880, 3072, 3200, 3360,       3584, 3840,       4096, 4480, 4608, 4800, 5120, 5376, 5600, 5760, 6144, 6400, 6720,       7168, 7680, 8000, 8064, 8192, 8960, 9216, 9600, 10240, 10752, 11200, 11520, 12288, 12800, 13440, 13824, 14336, 15360, 16000, 16128, 16384, 17920, 18432, 19200, 20480, 21504, 22400, 23040, 24576, 25600, 26880,        28672, 30720, 32000, 32768, 35840, 38400, 40960, 44800, 51200
    # AVX512: 4608, 5K, 6K, 7K, 7680, 8K, 9K, 10K, 10752, 12K, 12800, 16K, 18K, 20K, 24K, 25K, 32K, 40K, 48K, 56K, 60K, 64K, 72K, 80K, 84K, 96K, 120K, 128K, 144K, 192K, 200K, 240K, 280K, 288K, 300K, 320K, 336K, 360K, 384K, 392K, 400K, 420K, 432K, 448K, 480K, 504K, 512K, 560K, 576K, 588K, 600K, 640K, 672K, 720K, 768K, 800K, 840K, 864K, 896K, 960K, 1000K, 1008K, 1024K, 1152K, 1200K, 1280K, 1344K, 1400K, 1440K, 1500K, 1536K, 1600K, 1680K, 1728K, 1800K, 1920K, 1960K, 2048K, 2100K, 2160K, 2240K, 2304K, 2400K, 2520K, 2560K, 2592K, 2688K, 2880K, 2940K, 3000K, 3072K, 3136K, 3200K, 3360K, 3456K, 3600K, 3840K, 3920K, 4032K, 4200K, 4320K, 4480K, 4608K, 4704K, 4800K, 5040K, 5120K, 5184K, 5376K, 5760K, 6048K, 6144K, 6272K, 6400K, 6720K, 7056K, 7168K, 7200K, 7680K, 8064K, 8400K, 8640K, 8960K, 9600K, 10240K, 10368K, 11200K, 11520K, 12288K, 12800K, 13440K, 14400K, 15360K, 15680K, 16128K, 16384K, 16800K, 17280K, 17920K, 18432K, 18816K, 19200K, 20160K, 20480K, 20736K, 21504K, 21952K, 22400K, 23520K, 24192K, 24576K, 25088K, 25600K, 26880K, 27648K, 28224K, 28800K, 30720K, 31360K, 32256K, 32928K, 34560K, 36864K, 37632K, 38400K, 40320K, 40960K, 41472K, 43008K, 46080K, 47040K, 48384K, 49152K, 50176K, 53760K, 55296K, 56448K, 57344K, 61440K, 65536K

    # Note: We're using "expanded" values here, e.g. instead of the "K" values, we multiply the FFT size by 1024 to get the full value
    # Prime95 normally lists "K" values in its log files, however if the FFT size is not divisible by 1024, it will instead print the full value as well without an appended "K"
    # Examples: 4608, 7680, 10752, 12800
    # This only happens when AVX-512 is selected, but we need to have a uniform way to detect the FFT sizes, so all of the modes are set up this way
    #
    # Also note that the Smalles, Small, Large Presets seem to have changed in Prime 30.8, but for the time being we're keeping the old values
    # This is maybe a TODO
    $Script:FFTSizes = @{
        SSE    = @(
            # Smallest FFT
            4096, 5120, 6144, 8192, 10240, 12288, 14336, 16384, 20480,

            # Not used in Prime95 presets
            24576, 28672, 32768,

            # Small FFT
            40960, 49152, 57344, 65536, 73728, 81920, 86016, 98304, 114688, 131072, 147456, 163840, 196608, 229376, 245760,

            # Not used in Prime95 presets
            262144, 294912, 327680, 344064, 393216, 409600,

            # Large FFT
            458752, 491520, 524288, 573440, 589824, 655360, 688128, 737280, 786432, 819200, 917504, 983040, 1048576, 1146880, 1179648, 1228800, 1310720,
            1376256, 1474560, 1572864, 1638400, 1720320, 1769472, 1835008, 1966080, 2097152, 2293760, 2359296, 2457600, 2621440, 2752512, 2867200, 2949120,
            3145728, 3276800, 3440640, 3538944, 3670016, 3932160, 4194304, 4587520, 4718592, 4915200, 5242880, 5505024, 5734400, 5898240, 6291456, 6553600,
            6881280, 7077888, 7340032, 7864320, 8192000, 8388608,

            # Not used in Prime95 presets
            # Now custom labeled "Huge"
            # 32768K = 33554432 seems to be the maximum FFT size possible for SSE
            9175040, 9437184, 9830400, 10485760, 11010048, 11468800, 11796480, 12582912, 13107200, 13762560, 14155776, 14680064, 15728640, 16384000, 16777216,
            18350080, 18874368, 19660800, 20971520, 22020096, 22937600, 23592960, 25165824, 26214400, 27525120, 28311552, 29360128, 31457280, 32768000, 33554432
        )

        AVX    = @(
            # Smallest FFT
            4096, 5120, 6144, 8192, 10240, 12288, 15360, 16384, 18432, 20480, 21504,

            # Not used in Prime95 presets
            24576, 25600, 28672, 32768, 35840,

            # Small FFT
            36864, 40960, 49152, 51200, 61440, 65536, 73728, 81920, 86016, 98304, 102400, 114688, 122880, 131072, 143360, 147456, 163840, 172032, 196608, 204800, 229376, 245760,

            # Not used in Prime95 presets
            262144, 294912, 327680, 344064, 393216, 409600,

            # Large FFT
            458752, 491520, 524288, 573440, 589824, 655360, 688128, 737280, 786432, 819200, 884736, 917504, 983040, 1048576, 1179648, 1310720, 1376256, 1474560, 1572864, 1638400,
            1720320, 1769472, 1835008, 1966080, 2097152, 2359296, 2457600, 2621440, 2752512, 2949120, 3145728, 3276800, 3440640, 3538944, 3670016, 3932160, 4128768, 4194304,
            4587520, 4718592, 4915200, 5242880, 5505024, 5898240, 6291456, 6553600, 6881280, 7077888, 7340032, 7864320, 8192000, 8388608,

            # Not used in Prime95 presets
            # Now custom labeled "Huge"
            # 32768K = 33554432 seems to be the maximum FFT size possible for SSE
            9175040, 9437184, 9830400, 10485760, 11010048, 11796480, 12582912, 13107200, 13762560, 14155776, 14680064, 15728640, 16384000, 16515072, 16777216, 18350080,
            18874368, 19660800, 20971520, 22020096, 22937600, 23592960, 25165824, 26214400, 27525120, 29360128, 31457280, 32768000, 33554432
        )

        AVX2   = @(
            # Smallest FFT
            4096, 5120, 6144, 8192, 10240, 12288, 15360, 16384, 18432, 20480, 21504,

            # Not used in Prime95 presets
            24576, 25600, 28672, 30720, 32768, 35840,

            # Small FFT
            36864, 40960, 49152, 51200, 61440, 65536, 73728, 81920, 86016, 98304, 102400, 114688, 122880, 131072, 147456, 163840, 172032, 196608, 204800, 229376, 245760,

            # Not used in Prime95 presets
            262144, 286720, 294912, 327680, 344064, 393216, 409600,

            # Large FFT
            458752, 491520, 524288, 573440, 655360, 688128, 786432, 819200, 917504, 983040, 1048576, 1146880, 1179648, 1310720, 1376256, 1474560, 1572864, 1638400,
            1720320, 1835008, 1966080, 2097152, 2293760, 2359296, 2457600, 2621440, 2752512, 2867200, 2949120, 3145728, 3276800, 3440640, 3670016, 3932160, 4194304,
            4587520, 4718592, 4915200, 5242880, 5505024, 5734400, 5898240, 6291456, 6553600, 6881280, 7340032, 7864320, 8192000, 8257536, 8388608,

            # Not used in Prime95 presets
            # Now custom labeled "Huge"
            # 51200K = 52428800 seems to be the maximum FFT size possible for AVX2
            9175040, 9437184, 9830400, 10485760, 11010048, 11468800, 11796480, 12582912, 13107200, 13762560, 14155776, 14680064, 15728640, 16384000, 16515072, 16777216,
            18350080, 18874368, 19660800, 20971520, 22020096, 22937600, 23592960, 25165824, 26214400, 27525120, 29360128, 31457280, 32768000, 33554432, 36700160, 39321600,
            41943040, 45875200, 52428800
        )

        AVX512 = @(
            # Smallest FFT
            4608, 5120, 6144, 7168, 7680, 8192, 9216, 10240, 10752, 12288, 12800, 16384, 18432, 20480,

            # Not used in Prime95 presets
            24576, 25600, 32768,

            # Small FFT
            40960, 49152, 57344, 61440, 65536, 73728, 81920, 86016, 98304, 122880, 131072, 147456, 196608, 204800, 245760,

            # Not used in Prime95 presets
            286720, 294912, 307200, 327680, 344064, 368640, 393216, 401408, 409600,

            # Large FFT
            430080, 442368, 458752, 491520, 516096, 524288, 573440, 589824, 602112, 614400, 655360, 688128, 737280, 786432, 819200, 860160, 884736,
            917504, 983040, 1024000, 1032192, 1048576, 1179648, 1228800, 1310720, 1376256, 1433600, 1474560, 1536000, 1572864, 1638400, 1720320,
            1769472, 1843200, 1966080, 2007040, 2097152, 2150400, 2211840, 2293760, 2359296, 2457600, 2580480, 2621440, 2654208, 2752512, 2949120,
            3010560, 3072000, 3145728, 3211264, 3276800, 3440640, 3538944, 3686400, 3932160, 4014080, 4128768, 4300800, 4423680, 4587520, 4718592,
            4816896, 4915200, 5160960, 5242880, 5308416, 5505024, 5898240, 6193152, 6291456, 6422528, 6553600, 6881280, 7225344, 7340032, 7372800,
            7864320, 8257536,

            # Not used in Prime95 presets
            # Now custom labeled "Huge"
            # 65536K = 67108864 seems to be the maximum FFT size possible for AVX512
            8601600, 8847360, 9175040, 9830400, 10485760, 10616832, 11468800, 11796480, 12582912, 13107200, 13762560, 14745600, 15728640, 16056320,
            16515072, 16777216, 17203200, 17694720, 18350080, 18874368, 19267584, 19660800, 20643840, 20971520, 21233664, 22020096, 22478848, 22937600,
            24084480, 24772608, 25165824, 25690112, 26214400, 27525120, 28311552, 28901376, 29491200, 31457280, 32112640, 33030144, 33718272, 35389440,
            37748736, 38535168, 39321600, 41287680, 41943040, 42467328, 44040192, 47185920, 48168960, 49545216, 50331648, 51380224, 55050240, 56623104,
            57802752, 58720256, 62914560, 67108864
        )
    }


    # The min and max values for the various presets
    # Note that the actually tested sizes differ from the originally provided min and max values
    # depending on the selected test mode (SSE, AVX, AVX2, AVX512)
    $Script:FFTMinMaxValues = @{
        SSE    = @{
            SMALLEST   = @{ Min =    4096; Max =    20480; }  # Originally   4 ...   21
            SMALL      = @{ Min =   40960; Max =   245760; }  # Originally  36 ...  248
            LARGE      = @{ Min =  458752; Max =  8388608; }  # Originally 426 ... 8192
            HUGE       = @{ Min = 9175040; Max = 33554432; }  # New addition
            ALL        = @{ Min =    4096; Max = 33554432; }
            MODERATE   = @{ Min = 1376256; Max =  4194304; }
            HEAVY      = @{ Min =    4096; Max =  1376256; }
            HEAVYSHORT = @{ Min =    4096; Max =   163840; }
        }

        AVX    = @{
            SMALLEST   = @{ Min =    4096; Max =    21504; }  # Originally   4 ...   21
            SMALL      = @{ Min =   36864; Max =   245760; }  # Originally  36 ...  248
            LARGE      = @{ Min =  458752; Max =  8388608; }  # Originally 426 ... 8192
            HUGE       = @{ Min = 9175040; Max = 33554432; }  # New addition
            ALL        = @{ Min =    4096; Max = 33554432; }
            MODERATE   = @{ Min = 1376256; Max =  4194304; }
            HEAVY      = @{ Min =    4096; Max =  1376256; }
            HEAVYSHORT = @{ Min =    4096; Max =   163840; }
        }

        AVX2   = @{
            SMALLEST   = @{ Min =    4096; Max =    21504; }  # Originally   4 ...   21
            SMALL      = @{ Min =   36864; Max =   245760; }  # Originally  36 ...  248
            LARGE      = @{ Min =  458752; Max =  8388608; }  # Originally 426 ... 8192
            HUGE       = @{ Min = 9175040; Max = 52428800; }  # New addition
            ALL        = @{ Min =    4096; Max = 52428800; }
            MODERATE   = @{ Min = 1376256; Max =  4194304; }
            HEAVY      = @{ Min =    4096; Max =  1376256; }
            HEAVYSHORT = @{ Min =    4096; Max =   163840; }
        }

        AVX512 = @{
            SMALLEST   = @{ Min =    4608; Max =    21504; }  # Originally   4 ...   21
            SMALL      = @{ Min =   40960; Max =   245760; }  # Originally  36 ...  248
            LARGE      = @{ Min =  430080; Max =  8388608; }  # Originally 426 ... 8192
            HUGE       = @{ Min = 8601600; Max = 67108864; }  # New addition
            ALL        = @{ Min =    4608; Max = 67108864; }
            MODERATE   = @{ Min = 1376256; Max =  4194304; }
            HEAVY      = @{ Min =    4608; Max =  1376256; }
            HEAVYSHORT = @{ Min =    4608; Max =   163840; }
        }

        # The limits have changed for Prime95 30.8
        <#
        AVX512 = @{
            SMALLEST   = @{ Min =    4; Max =    42; }  # Originally   4 ...   42
            SMALL      = @{ Min =   73; Max =   455; }  # Originally  73 ...  455
            LARGE      = @{ Min =  780; Max =  8192; }  # Originally 780 ... 8192
            HUGE       = @{ Min = 8400; Max = 65536; }  # New addition
            ALL        = @{ Min =    4; Max = 65536; }
            MODERATE   = @{ Min = 1344; Max =  4096; }
            HEAVY      = @{ Min =    4; Max =  1344; }
            HEAVYSHORT = @{ Min =    4; Max =   160; }
        }
        #>
    }


    # Get the correct min and max values for the selected FFT settings
    if ($settings.mode -eq 'CUSTOM') {
        $Script:minFFTSize = [Int] $settings.Prime95Custom.MinTortureFFT * 1024
        $Script:maxFFTSize = [Int] $settings.Prime95Custom.MaxTortureFFT * 1024
    }

    # Custom preset (xxx-yyy)
    elseif ($settings.Prime95.FFTSize -Match '(\d+)\s*\-\s*(\d+)') {
        $Script:minFFTSize = [Int] [Math]::Min($Matches[1], $Matches[2]) * 1024
        $Script:maxFFTSize = [Int] [Math]::Max($Matches[1], $Matches[2]) * 1024
    }

    # Regular preset
    elseif ($FFTMinMaxValues[$settings.mode].Contains($settings.Prime95.FFTSize.ToUpperInvariant())) {
        $Script:minFFTSize = [Int] $FFTMinMaxValues[$settings.mode.ToUpperInvariant()][$settings.Prime95.FFTSize.ToUpperInvariant()].Min
        $Script:maxFFTSize = [Int] $FFTMinMaxValues[$settings.mode.ToUpperInvariant()][$settings.Prime95.FFTSize.ToUpperInvariant()].Max
    }

    # Something failed
    else {
        Exit-WithFatalError -text ('Could not find the min and max FFT sizes for the provided FFTSize setting "' + $settings.Prime95.FFTSize + '"!')
    }


    # Get the test mode, even if $settings.mode is set to CUSTOM
    $Script:cpuTestMode = $settings.mode

    # If we're in CUSTOM mode, try to determine which setting preset it is
    if ($settings.mode -eq 'CUSTOM') {
        $Script:cpuTestMode = 'SSE'

        if ($settings.Prime95Custom.CpuSupportsAVX -eq 1) {
            if ($settings.Prime95Custom.CpuSupportsAVX2 -eq 1 -and $settings.Prime95Custom.CpuSupportsFMA3 -eq 1) {
                $Script:cpuTestMode = 'AVX2'
            }
            else {
                $Script:cpuTestMode = 'AVX'
            }
        }
    }


    # The provided FFT sizes may not exist in the FFT test array, so we look for the next (min) or previous (max) FFT size
    if (!($FFTSizes[$cpuTestMode] -contains $minFFTSize)) {
        Write-ColorText('WARNING: The selected minimum FFT size (' + $minFFTSize/1024 + 'K) does not exist for the selected mode!') Yellow
        Write-VerboseText('The FFTSizes array does not include the current min FFT size, searching for the next size')

        $Script:minFFTSize = $FFTSizes[$cpuTestMode] | ForEach-Object {
            if ($_ -gt $minFFTSize) {
                $_
            }
        } | Select-Object -First 1

        # The value can return empty if no next value could be found, i.e. the entered value was higher than the highest available value
        if (!$Script:minFFTSize) {
            $Script:minFFTSize = ($FFTSizes[$cpuTestMode] | Select-Object -Last 1)
        }


        Write-VerboseText('Found the new min FFT size: ' + $Script:minFFTSize)
        Write-ColorText('Trying to find the next possible value... set to ' + $Script:minFFTSize/1024 + 'K') Yellow
        Write-ColorText('') Yellow
    }

    if (!($FFTSizes[$cpuTestMode] -contains $maxFFTSize)) {
        Write-ColorText('WARNING: The selected maximum FFT size (' + $maxFFTSize/1024 + 'K) does not exist for the selected mode!') Yellow
        Write-VerboseText('The FFTSizes array does not include the current max FFT size, searching for the previous size')

        $Script:maxFFTSize = ($FFTSizes[$cpuTestMode] | Sort-Object -Descending) | ForEach-Object {
            if ($maxFFTSize -gt $_) {
                $_
            }
        } | Select-Object -First 1


        # The max size cannot be smaller then the min size
        if ($Script:maxFFTSize -lt $Script:minFFTSize) {
            Write-VerboseText('The maximum FFT size cannot be smaller than the mimimum size, setting it to the same value')
            Write-VerboseText('-> ' + $Script:maxFFTSize/1024 + 'K to ' + $Script:minFFTSize/1024 + 'K')
            $Script:maxFFTSize = $Script:minFFTSize
        }

        Write-VerboseText('Found the new max FFT size: ' + $Script:maxFFTSize)
        Write-ColorText('Trying to find the previous possible value... set to ' + $Script:maxFFTSize/1024 + 'K') Yellow
        Write-ColorText('') Yellow
    }


    # Get the sub array for the selected FFT preset
    $startKey = [Array]::indexOf($FFTSizes[$cpuTestMode], $minFFTSize)
    $endKey   = [Array]::indexOf($FFTSizes[$cpuTestMode], $maxFFTSize)
    $Script:fftSubarray = $FFTSizes[$cpuTestMode][$startKey..$endKey]


    $modeString = $settings.mode
    $FFTSizeString = $settings.Prime95.FFTSize.ToUpperInvariant() -Replace '\s', ''


    Write-DebugText('')
    Write-DebugText('Checking the FFT Sizes to test:')
    Write-DebugText('FFTSizeString: ' + $FFTSizeString)
    Write-DebugText('cpuTestMode:   ' + $cpuTestMode)
    Write-DebugText('minFFTSize:    ' + $minFFTSize)
    Write-DebugText('maxFFTSize:    ' + $maxFFTSize)
    Write-DebugText('startKey:      ' + $startKey)
    Write-DebugText('endKey:        ' + $endKey)
    Write-DebugText('The selected fftSubarray to test:')
    Write-DebugText($Script:fftSubarray)


    # The Prime95 results.txt file name and path for this run
    $Script:stressTestLogFileName = 'Prime95_' + $scriptStartDateTime + '_' + $modeString + '_' + $FFTSizeString + '_FFT_' + [Math]::Floor($minFFTSize/1024) + 'K-' + [Math]::Ceiling($maxFFTSize/1024) + 'K.log'
    $Script:stressTestLogFilePath = $logFilePathAbsolute + $stressTestLogFileName


    # Starting with 30.10, we only have a prime.txt for the config
    if ($useOnlyPrimeTxt) {
        $configFile1 = $stressTestPrograms[$p95Type]['absolutePath'] + 'prime.txt'
        $configFile2 = $stressTestPrograms[$p95Type]['absolutePath'] + 'prime.txt'

        # Create the local.txt and overwrite if necessary
        $null = New-Item $configFile1 -ItemType File -Force

        # Check if the file exists
        if (!(Test-Path $configFile1 -PathType Leaf)) {
            Exit-WithFatalError -text ('Could not create the config file at ' + $configFile1 + '!')
        }
    }

    # Before 30.10, there were two config files, local.txt and prime.txt
    else {
        $configFile1 = $stressTestPrograms[$p95Type]['absolutePath'] + 'local.txt'
        $configFile2 = $stressTestPrograms[$p95Type]['absolutePath'] + 'prime.txt'

        # Create the local.txt and overwrite if necessary
        $null = New-Item $configFile1 -ItemType File -Force

        # Check if the file exists
        if (!(Test-Path $configFile1 -PathType Leaf)) {
            Exit-WithFatalError -text ('Could not create the config file at ' + $configFile1 + '!')
        }

        # Create the prime.txt and overwrite if necessary
        $null = New-Item $configFile2 -ItemType File -Force

        # Check if the file exists
        if (!(Test-Path $configFile2 -PathType Leaf)) {
            Exit-WithFatalError -text ('Could not create the config file at ' + $configFile2 + '!')
        }
    }

    # If the parameter is provided, use it, instead use the setting value
    $numberOfThreads = $(if ($overrideNumberOfThreads -gt 0) { $overrideNumberOfThreads } else { $settings.General.numberOfThreads })

    $output1 = [System.Collections.ArrayList] @(
        'RollingAverageIsFromV27=1'

        'CpuSupportsSSE='     + $prime95CPUSettings[$modeString].CpuSupportsSSE
        'CpuSupportsSSE2='    + $prime95CPUSettings[$modeString].CpuSupportsSSE2
        'CpuSupportsAVX='     + $prime95CPUSettings[$modeString].CpuSupportsAVX
        'CpuSupportsAVX2='    + $prime95CPUSettings[$modeString].CpuSupportsAVX2
        'CpuSupportsFMA3='    + $prime95CPUSettings[$modeString].CpuSupportsFMA3
        'CpuSupportsAVX512F=' + $prime95CPUSettings[$modeString].CpuSupportsAVX512
    )


    # Limit the load to the selected number of threads
    if ($isMaxPrime95_30_9) {
        [Void] $output1.Add('NumCPUs=1')                                # If this is not set, Prime95 will create 1 worker thread for each Core/Thread, seriously slowing down the computer!
        # In Prime95 30.7+, there's a new setting "NumCores", which seems to do the same as NumCPUs. The old setting may deprecate at some point
    }

    # Up to Prime95 30.6
    if ($isMaxPrime95_30_6) {
        [Void] $output1.Add('CpuNumHyperthreads=' + $numberOfThreads)   # If this is not set, Prime95 will create two worker threads in 30.6
        [Void] $output1.Add('WorkerThreads='      + $numberOfThreads)
    }

    # Beginning with Prime95 30.7 and up to 30.9
    elseif ($isMaxPrime95_30_9) {
        # If this is not set, Prime95 will create #numCores worker threads in 30.7+
        [Void] $output1.Add('NumThreads='    + $numberOfThreads)        # This has been renamed from CpuNumHyperthreads
        [Void] $output1.Add('WorkerThreads=' + $numberOfThreads)

        # If we're using TortureHyperthreading in prime.txt, these settings need to stay at 1, even if we're using 2 threads
        # TortureHyperthreading introduces inconsistencies with the log format for two threads, so we won't use it
        # [Void] $output1.Add('NumThreads=1')
        # [Void] $output1.Add('WorkerThreads=1')
    }

    # Beginning with Prime95 30.10 and up to 30.19
    # We haven't tested any new version, but we're using it for those anyway for now
    elseif ($isMaxPrime95_30_19 -or $isNewerPrime95) {
        [Void] $output1.Add('NumWorkers=1')                             # Apparently this isn't used for anything, but is still always added to the config (and always with =1)
        [Void] $output1.Add('NumCores='  + $numberOfThreads)            # This is now what is controlling the number of worker threads
    }

    # We only want one core per test, i.e. don't spread it around
    # TODO: Maybe change this for assignBothVirtualCoresForSingleThread?
    #       It doesn't seem to affect wich CPU does the work though, at least in Win10
    [Void] $output1.Add('CoresPerTest=1')



    # Output 2 is either the local.txt or it also goes into the prime.txt, depending on the Prime95 version
    $output2 = [System.Collections.ArrayList]::new()


    # In 30.4 there's an 80 character limit for the ini settings, so we're using an ugly workaround to put the log file into the /logs/ directory:
    # - set the working directory to the directory where the CoreCycler script is located
    # - then set the paths to the prime.txt and local.txt relative to that working directory
    # This should keep us below 80 characters
    [Void] $output2.Add('WorkingDir='  + $PSScriptRoot)
    [Void] $output2.Add('prime.ini='   + $stressTestPrograms[$p95Type]['processPath'] + '\prime.txt')

    if (!$useOnlyPrimeTxt) {
        [Void] $output2.Add('local.ini='   + $stressTestPrograms[$p95Type]['processPath'] + '\local.txt')
    }


    # Set the custom results.txt file name
    [Void] $output2.Add('results.txt=' + $logFilePath + '\' + $stressTestLogFileName)


    # New in Prime95 30.7
    # TortureHyperthreading=0/1
    # Goes into the prime.txt ($configFile2)
    # If we set this here, we need to use NumThreads=1 in local.txt
    # However, TortureHyperthreading introduces inconsistencies with the log format for two threads, so we won't use it
    # Instead, we're using the "old" mechanic of running two worker threads (as in 30.6 and before)
    if (!$isMaxPrime95_30_6) {
        #[Void] $output2.Add('TortureHyperthreading=' + ($numberOfThreads - 1))   # Number of Threads = 2 -> Setting = 1 / Number of Threads = 1 -> Setting = 0
        [Void] $output2.Add('TortureHyperthreading=0')
    }


    # Custom settings
    if ($modeString -eq 'CUSTOM') {
        [Void] $output2.Add('TortureMem='  + $settings.Prime95Custom.TortureMem)
        [Void] $output2.Add('TortureTime=' + $settings.Prime95Custom.TortureTime)
    }

    # Default settings
    else {
        [Void] $output2.Add('TortureMem=0')                   # No memory testing ("In-Place")
        [Void] $output2.Add('TortureTime=1')                  # 1 minute per FFT size
    }


    # Set the FFT sizes
    [Void] $output2.Add('MinTortureFFT=' + [Math]::Floor($minFFTSize/1024))       # The minimum FFT size to test
    [Void] $output2.Add('MaxTortureFFT=' + [Math]::Ceiling($maxFFTSize/1024))     # The maximum FFT size to test


    # Get the correct TortureWeak setting
    [Void] $output2.Add('TortureWeak=' + $(Get-TortureWeakValue))

    [Void] $output2.Add('V24OptionsConverted=1')              # Flag that the options were already converted from an older version (v24)
    [Void] $output2.Add('V30OptionsConverted=1')              # Flag that the options were already converted from an older version (v29)
    [Void] $output2.Add('ExitOnX=1')                          # No minimizing to the tray on close (x)
    [Void] $output2.Add('ResultsFileTimestampInterval=60')    # Write to the results.txt every 60 seconds
    [Void] $output2.Add('EnableSetAffinity=0')                # Don't let Prime automatically assign the CPU affinty, we're doing this on our own
    [Void] $output2.Add('EnableSetPriority=0')                # Don't let Prime automatically assign the CPU priority, we're setting it to "High"

    # No PrimeNet functionality, just stress testing
    [Void] $output2.Add('StressTester=1')
    [Void] $output2.Add('UsePrimenet=0')

    #[Void] $output2.Add('WGUID_version=2')                   # The algorithm used to generate the Windows GUID. Not important
    #[Void] $output2.Add('WorkPreference=0')                  # This seems to be a PrimeNet only setting

    #[Void] $output2.Add('[PrimeNet]')                        # Settings for uploading Prime results, not required
    #[Void] $output2.Add('Debug=0')


    # If only the prime.txt should be used, add the entries of the originally local.txt to it
    if ($useOnlyPrimeTxt) {
        [Void] $output1.AddRange($output2)
    }

    # Write the settings to the prime.txt file
    [System.IO.File]::WriteAllLines($configFile1, $output1)

    # Check if the file exists
    if (!(Test-Path $configFile1 -PathType Leaf)) {
        Exit-WithFatalError -text ('Could not create the config file at ' + $configFile1 + '!')
    }


    # If we're also using the local.txt in addition to the prime.txt
    if (!$useOnlyPrimeTxt) {
        [System.IO.File]::WriteAllLines($configFile2, $output2)

        # Check if the file exists
        if (!(Test-Path $configFile2 -PathType Leaf)) {
            Exit-WithFatalError -text ('Could not create the config file at ' + $configFile2 + '!')
        }
    }
}



<#
.DESCRIPTION
    Open Prime95 and set global script variables
.PARAMETER overrideNumberOfThreads
    [Int] If this is set, use this value instead of $settings.General.numberOfThreads for the expected number of threads
.OUTPUTS
    [Void]
#>
function Start-Prime95 {
    param(
        [Parameter(Mandatory=$false)] $overrideNumberOfThreads
    )

    Write-VerboseText('Starting Prime95')

    # Minimized to the tray
    #$processId = Start-Process -FilePath $stressTestPrograms['prime95']['fullPathToExe'] -ArgumentList '-t' -PassThru -WindowStyle Hidden

    # Minimized to the task bar
    # This steals the focus
    #$processId = Start-Process -FilePath $stressTestPrograms['prime95']['fullPathToExe'] -ArgumentList '-t' -PassThru -WindowStyle Minimized

    # This doesn't steal the focus
    $command         = $stressTestPrograms[$settings.General.stressTestProgram]['command']
    $windowBehaviour = $stressTestPrograms[$settings.General.stressTestProgram]['windowBehaviour']
    $windowBehaviour = $(if ($stressTestProgramWindowToForeground) { 1 } else { $windowBehaviour })

    Write-DebugText('Trying to start the stress test with the command:')
    Write-DebugText($command)

    $processId = [Microsoft.VisualBasic.Interaction]::Shell($command, $windowBehaviour)


    # This might be necessary to correctly read the process. Or not
    Start-Sleep -Milliseconds 500

    # Get the main window and stress test processes, as well as the main window handle
    # This also works for windows minimized to the tray
    Get-StressTestProcessInformation $true $overrideNumberOfThreads

    # This is to find the exact counter path, as you might have multiple processes with the same name
    if ($enablePerformanceCounters) {
        try {
            # Start a background job to get around the cached Get-Counter value
            $Script:processCounterPathId = Start-Job -ScriptBlock {
                $counterPathName = $args[0].'FullName'
                $processId = $args[1]
                ((Get-Counter $counterPathName -ErrorAction Ignore).CounterSamples | Where-Object { $_.RawValue -eq $processId }).Path
            } -ArgumentList $counterNames, $stressTestProcessId | Wait-Job | Receive-Job

            if (!$processCounterPathId) {
                Exit-WithFatalError -text ('Could not find the counter path for the Prime95 instance!')
            }

            $Script:processCounterPathTime = $processCounterPathId -Replace $counterNames['SearchString'], $counterNames['ReplaceString']

            Write-VerboseText('The Performance Process Counter Path for the ID:')
            Write-VerboseText($processCounterPathId)
            Write-VerboseText('The Performance Process Counter Path for the Time:')
            Write-VerboseText($processCounterPathTime)
        }
        catch {
            Write-DebugText('Could not query the process path')
            Write-DebugText('Error: ' + $_)
        }
    }
}



<#
.DESCRIPTION
    Close Prime95
.PARAMETER
    [Void]
.OUTPUTS
    [Void]
#>
function Close-Prime95 {
    Write-VerboseText('Trying to close Prime95')

    # If there is no windowProcessMainWindowHandle id
    # Try to get it
    if (!$windowProcessMainWindowHandle) {
        Get-StressTestProcessInformation $false -1   # Don't exit the script when the process or threads are not found
    }

    # If we now have a windowProcessMainWindowHandle, try to close the window
    if ($windowProcessMainWindowHandle) {
        $windowProcess = Get-Process -Id $windowProcessId -ErrorAction Ignore

        if (!$windowProcess) {
            Write-VerboseText('The window process wasn''t found, no need to close it')
        }
        else {
            # The process may be suspended
            $null = Resume-Process -process $windowProcess -ignoreError $true

            Write-VerboseText('Trying to gracefully close Prime95')
            Write-DebugText('The window process main window handle: ' + $windowProcessMainWindowHandle)

            # Send the message to close the main window
            # The window may still be blocked from the stress test process being closed, so repeat if necessary
            try {
                for ($i = 1; $i -le 5; $i++) {
                    Write-DebugText('Try ' + $i)
                    [Void] $SendMessage::SendMessage($windowProcessMainWindowHandle, $SendMessage::WM_CLOSE, 0, 0)

                    # We've send the close request, let's wait a second for it to actually exit
                    if ($windowProcess -and !$windowProcess.HasExited) {
                        $timestamp = Get-Date -Format HH:mm:ss
                        Write-VerboseText($timestamp + ' - Sent the close message, waiting for Prime95 to exit')
                        $null = $windowProcess.WaitForExit(1000)
                    }

                    $hasExited = $windowProcess.HasExited
                    Write-VerboseText('         - ... has exited: ' + $hasExited)

                    if ($windowProcess.HasExited) {
                        Write-VerboseText('The main window has exited')

                        # But is the process still there?
                        $windowProcess = Get-Process -Id $windowProcessId -ErrorAction Ignore

                        if (!$windowProcess) {
                            Write-VerboseText('The main window has truly exited')
                            break
                        }
                        else {
                            Write-VerboseText('The main window is still there, trying again')
                        }
                    }
                }
            }
            catch {
                Write-VerboseText('Could not gracefully close Prime95, proceeding to kill the process')
                Write-DebugText('Error: ' + $_)
            }
        }
    }


    # If the window is still here at this point, just kill the process
    $windowProcess = Get-Process $processName -ErrorAction Ignore

    if ($windowProcess) {
        Write-VerboseText('Could not gracefully close Prime95, killing the process')

        #'The process is still there, killing it'
        # Unfortunately this will leave any tray icons behind
        Stop-Process $windowProcess.Id -Force -ErrorAction Ignore
    }
    else {
        Write-VerboseText('Prime95 closed')
    }
}



<#
.DESCRIPTION
    Initialize Aida64
.PARAMETER
    [Void]
.OUTPUTS
    [Void]
#>
function Initialize-Aida64 {
    # Check if the aida64.exe exists
    Write-VerboseText('Checking if aida64.exe exists at:')
    Write-VerboseText($stressTestPrograms['aida64']['fullPathToExe'] + '.' + $stressTestPrograms['aida64']['processNameExt'])

    if (!(Test-Path ($stressTestPrograms['aida64']['fullPathToExe'] + '.' + $stressTestPrograms['aida64']['processNameExt']) -PathType Leaf)) {
        Write-ColorText('FATAL ERROR: Could not find Aida64!') Red
        Write-ColorText('Make sure to download and extract the PORTABLE ENGINEER(!) version of Aida64 into the following directory:') Red
        Write-ColorText($stressTestPrograms['aida64']['absoluteInstallPath']) Yellow
        Write-Text ''
        Write-ColorText('You can download the PORTABLE ENGINEER(!) version of Aida64 from:') Red
        Write-ColorText('https://www.aida64.com/downloads') Cyan
        Exit-WithFatalError
    }


    $modesArray = $settings.mode -Split '\s*,\s*|\s+' | Where-Object { $_.Length -gt 0 }
    $modeString = ($modesArray -Join '-').ToUpperInvariant()

    # TODO: Do we want to offer a way to start Aida64 with admin rights?
    $hasAdminRights = $false


    # Rename the aida64.exe.manifest to aida64.exe.manifest.bak so that we can start as a regular user
    # By default AIDA64 requires admin rights for additional sensory information, which we don't need here
    # TODO: Do we still need this with the /SAFEST command line flag?
    $pathManifest = $stressTestPrograms['aida64']['processPath'] + '\aida64.exe.manifest'
    $pathBackup   = $stressTestPrograms['aida64']['processPath'] + '\aida64.exe.manifest.bak'

    if ((Test-Path $pathManifest -PathType Leaf)) {
        Write-VerboseText('Trying to rename the aida64.exe.manifest file so that we can start AIDA64 as a regular user')

        if (!(Move-Item -Path $pathManifest -Destination $pathBackup -PassThru)) {
            Exit-WithFatalError -text ('Could not rename the aida64.exe.manifest file!')
        }

        Write-VerboseText('Successfully renamed to aida64.exe.manifest.bak')
    }

    # The Aida64 log file name and path for this run
    $Script:stressTestLogFileName = 'Aida64_' + $scriptStartDateTime + '_' + $modeString + '.csv'
    $Script:stressTestLogFilePath = $logFilePathAbsolute + $stressTestLogFileName

    # The aida64.ini and aida64.sst.ini
    $configFile1 = $stressTestPrograms['aida64']['absolutePath'] + 'aida64.ini'
    $configFile2 = $stressTestPrograms['aida64']['absolutePath'] + 'aida64.sst.ini'


    # Create the aida64.ini and overwrite if necessary
    $null = New-Item $configFile1 -ItemType File -Force

    # Check if the file exists
    if (!(Test-Path $configFile1 -PathType Leaf)) {
        Exit-WithFatalError -text ('Could not create the config file at ' + $configFile1 + '!')
    }


    $output1 = [System.Collections.ArrayList] @(
        '[Generic]'
        'NoGUI=0'
        'LoadWithWindows=0'
        'SplashScreen=0'
        'MinimizeToTray=0'
        'Language=en'
        'ReportHeader=0'
        'ReportFooter=0'
        'ReportMenu=0'
        'ReportDebugInfo=0'
        'ReportDebugInfoCSV=0'
        'ReportHostInFPC=0'
        'HWMonLogToHTM=0'
        'HWMonLogToCSV=1'
        'HWMonLogProcesses=0'
        'HWMonPersistentLog=1'
        'HWMonLogFileOpenFreq=24'
        'HWMonHTMLogFile='
        'HWMonCSVLogFile=' + $stressTestLogFilePath
    )


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

    [Void] $output1.Add('HWMonLogItems=' + ($csvEntriesArr -Join ' '))

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

    $output2 = [System.Collections.ArrayList] @(
        # We want to set our own CPU affinity mask
        'CPUMaskAuto=0'

        # Set the affinity to either one or two CPUs
        ('CPUMask=' + $(if ($settings.General.numberOfThreads -gt 1) { '0x0000000C' } else { '0x00000004' }))

        # Use AVX?
        ('UseAVX=' + $settings.Aida64.useAVX)
        ('UseAVX512=' + $settings.Aida64.useAVX)

        # Set the maximum amount of memory during the RAM stress test
        ('MemAlloc=' + $settings.Aida64.maxMemory)
    )


    [System.IO.File]::WriteAllLines($configFile1, $output1)

    # Check if the file exists
    if (!(Test-Path $configFile1 -PathType Leaf)) {
        Exit-WithFatalError -text ('Could not create the config file at ' + $configFile1 + '!')
    }


    [System.IO.File]::WriteAllLines($configFile2, $output2)

    # Check if the file exists
    if (!(Test-Path $configFile2 -PathType Leaf)) {
        Exit-WithFatalError -text ('Could not create the config file at ' + $configFile2 + '!')
    }
}



<#
.DESCRIPTION
    Open Aida64
.PARAMETER startOnlyStressTestProcess
    [Bool] If this is set, it will only start the stress test process and not the whole program
           Aida64 uses a dedicated DLL to perform the stress test (aida_bench32.dll or aida_bench64.dll)
.PARAMETER overrideNumberOfThreads
    [Int] If this is set, use this value instead of $settings.General.numberOfThreads for the expected number of threads
.OUTPUTS
    [Void]
#>
function Start-Aida64 {
    param(
        [Parameter(Mandatory=$false)] [Bool] $startOnlyStressTestProcess = $false,
        [Parameter(Mandatory=$false)] $overrideNumberOfThreads
    )

    Write-VerboseText('Starting Aida64')
    Write-VerboseText('The flag to only start the stress test process is: ' + $startOnlyStressTestProcess)

    # Check if the main window process exists
    $checkWindowProcess = Get-Process $stressTestPrograms[$settings.General.stressTestProgram]['processName'] -ErrorAction Ignore

    if ($checkWindowProcess) {
        Write-DebugText('The main window for Aida64 still exists')
    }
    else {
        Write-DebugText('The main window for Aida64 doesn''t exist')
    }


    if ($startOnlyStressTestProcess -and $checkWindowProcess) {
        Write-VerboseText('The flag to only start the stress test process was set, and the main window still exists')
        Write-VerboseText('Only trying to re-start the stress test')
    }


    # When the flag to only start the stress test process was NOT set, i.e. the whole program should be restarted,
    # but the main Aida64 application is still open
    # We have two choices:
    # a) Set the flag to only start the test process, and hope we're still on the correct tab in the main application
    # b) Close the application and re-start it
    if (!$startOnlyStressTestProcess -and $checkWindowProcess) {
        Write-VerboseText('The flag to only start the stress test process was not set, but the main window still exists!')

        # Let's go with simply trying to start the stress test, this is faster
        # Also, we don't need to reload the config, as the number of stress test threads stays the same for both 1 and 2 threads
        # Because Aida64 launches 4 threads anyway
        Write-VerboseText('We''ll try to restart the stress test process using the existing main window.')
        Write-DebugText('Setting the startOnlyStressTestProcess flag to $true to try to start the stress test process')
        $startOnlyStressTestProcess = $true
    }


    # Start Aida64's main window process if $startOnlyStressTestProcess is not set, or if the main window process wasn't found
    if (!$startOnlyStressTestProcess -or !$checkWindowProcess) {
        if ($startOnlyStressTestProcess -and !$checkWindowProcess) {
            Write-VerboseText('The flag to only start the stress test process was set, but couldn''t find the main window!')
            Write-VerboseText('Starting the main window process')
        }

        # This doesn't steal the focus
        $command         = $stressTestPrograms[$settings.General.stressTestProgram]['command']
        $windowBehaviour = $stressTestPrograms[$settings.General.stressTestProgram]['windowBehaviour']
        $windowBehaviour = $(if ($stressTestProgramWindowToForeground) { 1 } else { $windowBehaviour })

        Write-DebugText('Trying to start the stress test with the command:')
        Write-DebugText($command)

        $processId = [Microsoft.VisualBasic.Interaction]::Shell($command, $windowBehaviour)

        $checkWindowProcess = Get-Process -Id $processId -ErrorAction Ignore

        # /SST          = Directly starts the System Stability Test (available tests: Cache, RAM, CPU, FPU, Disk, GPU)
        # /SILENT       = No tray icon, which can stay behind if the main window process is killed
        # /HIDETRAYMENU = Disables the right click menu on the tray icon. Doesn't seem to work though
        # /SAFE         = No low-level PCI, SMBus and sensor scanning
        # /SAFEST       = No kernel drivers are loaded

        #aida64.exe /SAFEST /SILENT /SST CACHE
        #aida64.exe /SAFEST /HIDETRAYMENU /SST CACHE

        # Don't start only the stress test process further below
        $startOnlyStressTestProcess = $false
    }


    # Aida64 takes some additional time to load
    # Check for the stress test process, if it's loaded, we're ready to go
    $timestamp = Get-Date -Format HH:mm:ss
    Write-Text($timestamp + ' - Waiting for Aida64 to load the stress test (' + $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad'] + ')...')

    # Repeat the whole process up to 6 times, i.e. 6x10x0,5 = 30 seconds total runtime before it errors out
    :LoopStartProcess for ($i = 1; $i -le 6; $i++) {
        if ($startOnlyStressTestProcess) {
            # Send a keyboard command to the Aida64 window to start the stress test process
            Send-CommandToAida64 'stop'
            Start-Sleep -Milliseconds 1000
            Send-CommandToAida64 'start'
        }

        # Repeat the check every 500ms
        for ($j = 0; $j -lt 10; $j++) {
            $stressTestProcess = Get-Process $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad'] -ErrorAction Ignore

            $timestamp = Get-Date -Format HH:mm:ss

            if ($stressTestProcess) {
                Write-VerboseText($timestamp + ' - ... stress test process found')
                Write-Text($timestamp + ' - Aida64 started')
                break LoopStartProcess
            }
            else {
                Write-VerboseText($timestamp + ' - ... stress test process not found yet')
            }

            Start-Sleep -Milliseconds 250
        }
    }

    # Either the main window or the stress test process wasn't found
    if (!$checkWindowProcess -or !$stressTestProcess) {
        # If $startOnlyStressTestProcess was set, try again without the flag
        if ($startOnlyStressTestProcess) {
            Write-VerboseText('Couldn''t start the main window or stress test process')
            Write-VerboseText('Close all processes and try again from scratch')
            Close-Aida64
            Start-Aida64 $false $overrideNumberOfThreads
            return
        }

        Exit-WithFatalError -text ('Could not start the process "' + $stressTestPrograms['aida64']['processName'] + '"!')
    }

    # Get the main window and stress test processes, as well as the main window handle
    # This also works for windows minimized to the tray
    Get-StressTestProcessInformation $true $overrideNumberOfThreads

    # This is to find the exact counter path, as you might have multiple processes with the same name
    if ($enablePerformanceCounters) {
        try {
            # Start a background job to get around the cached Get-Counter value
            $Script:processCounterPathId = Start-Job -ScriptBlock {
                $counterPathName = $args[0].'FullName'
                $processId = $args[1]
                ((Get-Counter $counterPathName -ErrorAction Ignore).CounterSamples | Where-Object { $_.RawValue -eq $processId }).Path
            } -ArgumentList $counterNames, $stressTestProcessId | Wait-Job | Receive-Job

            if (!$processCounterPathId) {
                Exit-WithFatalError -text ('Could not find the counter path for the Aida64 stress test instance!')
            }

            $Script:processCounterPathTime = $processCounterPathId -Replace $counterNames['SearchString'], $counterNames['ReplaceString']

            Write-VerboseText('The Performance Process Counter Path for the ID:')
            Write-VerboseText($processCounterPathId)
            Write-VerboseText('The Performance Process Counter Path for the Time:')
            Write-VerboseText($processCounterPathTime)
        }
        catch {
            Write-DebugText('Could not query the process path')
            Write-DebugText('Error: ' + $_)
        }
    }
}



<#
.DESCRIPTION
    Close Aida64
.PARAMETER closeOnlyStressTest
    [Bool] If set to true, will try to only stop the stress test process and not the whole program
.OUTPUTS
    [Void]
#>
function Close-Aida64 {
    param(
        [Parameter(Mandatory=$false)] [Bool] $closeOnlyStressTest = $false
    )

    if ($settings.General.restartTestProgramForEachCore) {
        if ($closeOnlyStressTest) {
            Write-Text('           Trying to stop Aida64')
        }
        else {
            Write-Text('           Trying to close Aida64')
        }
    }
    else {
        Write-VerboseText('Trying to close Aida64')
    }

    Write-VerboseText('The flag to only close the Aida64 stress test process is: ' + $closeOnlyStressTest)

    if (!$closeOnlyStressTest) {
        Write-DebugText('Trying to close the whole Aida64 program')
    }


    $thisStressTestProcess = $null
    $success = $false

    # If there is no windowProcessMainWindowHandle id
    # Try to get it
    if (!$windowProcessMainWindowHandle) {
        # Set the flag to not stop if the stress test process wasn't found
        # It may not be running
        Get-StressTestProcessInformation $false -1   # Don't exit the script when the process or threads are not found
    }

    # The stress test window cannot be closed gracefully, as it has no main window
    # We could just kill it, but this leaves behind a tray icon and an error message the next time Aida is opened
    # Instead, we send a keystroke command to the Aida64 window. Funky!
    if ($stressTestProcessId) {
        Write-VerboseText('The Aida64 stress test process id is set, assuming the process exists as well')

        $thisStressTestProcess = Get-Process -Id $stressTestProcessId -ErrorAction Ignore

        # The process may be suspended
        if ($thisStressTestProcess) {
            $null = Resume-Process -process $thisStressTestProcess -ignoreError $true
        }
        else {
            Write-VerboseText('The Aida64 adstress test process id is set, but no stress test process was found!')
        }

        # We can only send a keyboard command if the main window also still exists
        if ($thisStressTestProcess -and $windowProcessMainWindowHandle) {
            Write-VerboseText('The Aida64 stress test and the main window process exist')

            # Repeat the whole process up to 3 times, i.e. 3x10x0,5 = 15 seconds total runtime before it errors out
            :LoopStopProcess for ($i = 1; $i -le 3; $i++) {
                # Send a keyboard command to the Aida64 window to stop the stress test process
                Send-CommandToAida64 'stop'

                # Repeat the check every 500ms
                for ($j = 0; $j -lt 10; $j++) {
                    $thisStressTestProcess = Get-Process $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad'] -ErrorAction Ignore

                    $timestamp = Get-Date -Format HH:mm:ss

                    if ($thisStressTestProcess) {
                        Write-VerboseText($timestamp + ' - ... the Aida64 stress test process still exists')
                    }
                    else {
                        Write-VerboseText($timestamp + ' - The Aida64 stress test process has successfully closed')
                        $success = $true
                        break LoopStopProcess
                    }

                    Start-Sleep -Milliseconds 500
                }
            }
        }
    }


    # No windowProcessMainWindowHandle was found
    if ($thisStressTestProcess -and !$windowProcessMainWindowHandle) {
        Write-VerboseText('Apparently there''s no Aida64 main window, but the stress test is still running!')
    }

    # If the stress test process couldn't be closed gracefully
    # We need to kill the whole program including the main window, or we may not be able to start the stress test again
    if ($closeOnlyStressTest -and $thisStressTestProcess) {
        Write-VerboseText('The Aida64 stress test process couldn''t be stopped, we need to kill both the stress test and the main window process')

        # Set the flag to also close the main window at this point
        $closeOnlyStressTest = $false
    }


    # Fallback to killing the process, with all its side effects
    if ($thisStressTestProcess -and !$success) {
        Write-VerboseText('Killing the Aida64 stress test program process')
        Stop-Process $thisStressTestProcess.Id -Force -ErrorAction Ignore
    }


    # If we now have a windowProcessMainWindowHandle, first try to close the main window gracefully
    # But only if $closeOnlyStressTest is false
    if (!$closeOnlyStressTest) {
        if ($windowProcessMainWindowHandle) {
            Write-VerboseText('Trying to gracefully close Aida64')
            Write-VerboseText('windowProcessId: ' + $windowProcessId)
            Write-DebugText('The window process main window handle: ' + $windowProcessMainWindowHandle)

            $windowProcess = Get-Process -Id $windowProcessId -ErrorAction Ignore

            if (!$windowProcess) {
                Write-VerboseText('The window process wasn''t found, no need to close it')
            }
            else {
                # The process may be suspended
                Write-VerboseText('The process may be suspended, resuming')
                $null = Resume-Process -process $windowProcess -ignoreError $true

                Write-VerboseText('Sending the close message to the main window')

                # Send the message to close the main window
                # The window may still be blocked from the stress test process being closed, so repeat if necessary
                try {
                    for ($i = 1; $i -le 5; $i++) {
                        Write-DebugText('Try ' + $i)
                        [Void] $SendMessage::SendMessage($windowProcessMainWindowHandle, $SendMessage::WM_CLOSE, 0, 0)

                        # We've send the close request, let's wait a second for it to actually exit
                        if ($windowProcess -and !$windowProcess.HasExited) {
                            $timestamp = Get-Date -Format HH:mm:ss
                            Write-VerboseText($timestamp + ' - Sent the close message, waiting for Aida64 to exit')
                            $null = $windowProcess.WaitForExit(1000)
                        }

                        $hasExited = $windowProcess.HasExited
                        Write-VerboseText('         - ... has exited: ' + $hasExited)

                        if ($windowProcess.HasExited) {
                            Write-VerboseText('The main window has exited')

                            # But is the process still there?
                            $windowProcess = Get-Process -Id $windowProcessId -ErrorAction Ignore

                            if (!$windowProcess) {
                                Write-VerboseText('The main window has truly exited')
                                break
                            }
                            else {
                                Write-VerboseText('The main window is still there, trying again')
                            }
                        }
                    }
                }
                catch {
                    Write-VerboseText('Could not gracefully close Aida64, proceeding to kill the process')
                    Write-DebugText('Error: ' + $_)
                }
            }
        }

        $timestamp = Get-Date -Format HH:mm:ss
        Write-VerboseText($timestamp + ' - Checking if the main window process still exists:')

        # If the window is still here at this point, just kill the process
        $windowProcess = Get-Process $stressTestPrograms['aida64']['processName'] -ErrorAction Ignore

        if ($windowProcess) {
            Write-VerboseText('Still there, could not gracefully close Aida64, forcefully killing the process')

            # Unfortunately this will leave any tray icons behind
            Stop-Process $windowProcess.Id -Force -ErrorAction Ignore
        }

        # Check if both processes are gone
        $checkWindowProcess     = Get-Process $stressTestPrograms['aida64']['processName'] -ErrorAction Ignore
        $checkStressTestProcess = Get-Process $stressTestPrograms['aida64']['processNameForLoad'] -ErrorAction Ignore

        if (!$checkWindowProcess -and !$checkStressTestProcess) {
            Write-VerboseText('Aida64 closed')
        }
        else {
            if ($checkWindowProcess) {
                Write-VerboseText('The main window process still exists')
            }

            if ($checkStressTestProcess) {
                Write-VerboseText('The stress test process still exists')
            }

            Write-VerboseText('Could not close Aida64 successfully. Actually this is weird and should not happen.')
        }
    }

    # Aida64 seems to create a "sst-is-running.txt" file in the %TEMP% directory
    # Is this something we can utilize?
}



<#
.DESCRIPTION
    Create the y-cruncher config file
    This depends on the $settings.mode variable
.PARAMETER overrideNumberOfThreads
    [Int] If this is set, use this value instead of $settings.General.numberOfThreads
.OUTPUTS
    [Void]
#>
function Initialize-yCruncher {
    param(
        [Parameter(Mandatory=$false)] $overrideNumberOfThreads
    )

    $fullPathToExe = $stressTestPrograms[$settings.General.stressTestProgram]['fullPathToExe']

    if ($isYCruncherWithLogging) {
        $fullPathToExe = $stressTestPrograms[$settings.General.stressTestProgram]['fullPathToLoadExe']
    }

    $binaryToRun = $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad'] + '.' + $stressTestPrograms[$settings.General.stressTestProgram]['processNameExt']
    $binaryWithPathToRun = $fullPathToExe + '.' + $stressTestPrograms[$settings.General.stressTestProgram]['processNameExt']

    # Check if the selected binary exists
    Write-VerboseText('Checking if ' + $binaryToRun + ' exists at:')
    Write-VerboseText($binaryWithPathToRun)

    if (!(Test-Path ($binaryWithPathToRun) -PathType Leaf)) {
        Write-ColorText('FATAL ERROR: Could not find y-cruncher!') Red
        Write-ColorText('             Trying to run "' + $binaryWithPathToRun + '"') Red
        Write-ColorText('Make sure to download and extract y-cruncher into the following directory:') Red
        Write-ColorText($stressTestPrograms[$settings.General.stressTestProgram]['absoluteInstallPath']) Yellow
        Write-Text ''
        Write-ColorText('You can download y-cruncher from:') Red
        Write-ColorText('http://www.numberworld.org/y-cruncher/#Download') Cyan
        Exit-WithFatalError
    }

    $modeString    = $settings.mode
    $configFile    = $stressTestPrograms[$settings.General.stressTestProgram]['configFilePath']
    $selectedTests = $settings.yCruncher.tests

    # If the parameter is provided, use it, instead use the setting value
    $numberOfThreads = $(if ($overrideNumberOfThreads -gt 0) { $overrideNumberOfThreads } else { $settings.General.numberOfThreads })

    # Check the memory
    $memorySizeString = $settings.yCruncher.memory

    if ($memorySizeString -eq 'default' ) {
        $memory = $(if ($numberOfThreads -gt 1) { 26567600 } else { 13418572 })
    }
    else {
        $memory = Get-ByteValueFromString -string $memorySizeString
    }


    # Too much memory!
    if ($memory -gt $freeMemory) {
        $errorText  = 'You have selected too much memory!'
        $errorText += [Environment]::NewLine + '             Selected Memory: ' + [Math]::Round($memory / 1GB, 1)     + ' GB (' + $memory     + ' bytes) ("memory = ' + $memorySizeString + '")'
        $errorText += [Environment]::NewLine + '             Free Memory:     ' + [Math]::Round($freeMemory / 1GB, 1) + ' GB (' + $freeMemory + ' bytes)'
        Exit-WithFatalError -text $errorText
    }


    # The "C17" test only works with "13-HSW ~ Airi" and above
    # Let's use the first two digits to determine this (so 00 to 22)
    if ($selectedTests.Contains('C17')) {
        $modeNum = [Int] $modeString.Substring(0, 2)

        if ($modeNum -lt 13) {
            Exit-WithFatalError -text ('Test "C17" is present in the "tests" setting, but the selected y-cruncher mode "' + $modeString + '" does not support it! Aborting!')
        }
    }


    # TODO
    # Check if any of the new tests have a mimimum requirement

    $coresLine      = '        LogicalCores : [2]'
    $memoryLine     = '        TotalMemory : ' + $memory
    $stopOnError    = '        StopOnError : "true"'
    $secondsPerTest = 60


    if ($numberOfThreads -gt 1) {
        $coresLine  = '        LogicalCores : [2 3]'
    }

    # Stop on error or not
    if ($settings.yCruncher.enableYCruncherLoggingWrapper -eq 1 -and $settings.General.stopOnError -eq 0) {
        $stopOnError = '        StopOnError : "false"'
    }

    # No stopOnError if the automatic test mode is enabled
    if ($settings.yCruncher.enableYCruncherLoggingWrapper -eq 1 -and $settings.General.stopOnError -gt 0 -and $settings.AutomaticTestMode.enableAutomaticAdjustment -gt 0) {
        $stopOnError = '        StopOnError : "false"'
    }

    # The tests to run
    $testsToRun = $selectedTests | ForEach-Object { -Join('            "', $_, '"') }

    # The duration per test
    if ($settings.yCruncher.testDuration -gt 0) {
        $secondsPerTest = $settings.yCruncher.testDuration
    }


    $configEntries = @(
        '{'
        '    Action : "StressTest"'
        '    StressTest : {'
        '        AllocateLocally : "true"'
        $coresLine
        $memoryLine
        '        SecondsPerTest : ' + $secondsPerTest
        '        SecondsTotal : 0'
        $stopOnError
        '        Tests : ['
        $testsToRun
        '        ]'
        '    }'
        '}'
    )


    [System.IO.File]::WriteAllLines($configFile, $configEntries)

    # Check if the file exists
    if (!(Test-Path $configFile -PathType Leaf)) {
        Exit-WithFatalError -text ('Could not create the config file at ' + $configFile + '!')
    }
}



<#
.DESCRIPTION
    Open y-cruncher and set global script variables
.PARAMETER overrideNumberOfThreads
    [Int] If this is set, use this value instead of $settings.General.numberOfThreads for the expected number of threads
.OUTPUTS
    [Void]
#>
function Start-yCruncher {
    param(
        [Parameter(Mandatory=$false)] $overrideNumberOfThreads
    )

    Write-VerboseText('Starting y-cruncher')

    # Minimized to the tray
    #$processId = Start-Process -FilePath $stressTestPrograms[$settings.General.stressTestProgram]['fullPathToExe'] -ArgumentList ('config "' + $stressTestConfigFilePath + '"') -PassThru -WindowStyle Hidden

    # Minimized to the task bar
    # This steals the focus
    #$processId = Start-Process -FilePath $stressTestPrograms[$settings.General.stressTestProgram]['fullPathToExe'] -ArgumentList ('config "' + $stressTestConfigFilePath + '"') -PassThru -WindowStyle Minimized
    #$processId = Start-Process -FilePath $stressTestPrograms[$settings.General.stressTestProgram]['fullPathToExe'] -ArgumentList ('config "' + $stressTestConfigFilePath + '"') -PassThru

    # This doesn't steal the focus
    # We need to use conhost, otherwise the output would be inside the current console window
    # Caution, calling conhost here will also return the process id of the conhost.exe file, not the one for the y-cruncher binary!
    # The escape character in Visual Basic for double quotes seems to be... a double quote!
    # So a triple double quote is actually interpreted as a single double quote here
    #$processId = [Microsoft.VisualBasic.Interaction]::Shell(("conhost.exe """ + $stressTestPrograms[$settings.General.stressTestProgram]['fullPathToExe'] + """ config """ + $stressTestConfigFilePath + """"), 6) # 6 = MinimizedNoFocus

    # 0 = Hide
    # Apparently on some computers (not mine) the windows title is not set to the binary path, so the Get-StressTestProcessInformation function doesn't work
    # Therefore we're now using "cmd /C start" to be able to set a window title...

    $command         = $stressTestPrograms[$settings.General.stressTestProgram]['command']
    $command         = $(if ($stressTestProgramWindowToForeground) { $command.Replace('/MIN ', '') } else { $command })   # Remove the /MIN so that the window isn't placed in the background
    $windowBehaviour = $stressTestPrograms[$settings.General.stressTestProgram]['windowBehaviour']
    $windowBehaviour = $(if ($stressTestProgramWindowToForeground) { 1 } else { $windowBehaviour })

    Write-DebugText('Trying to start the stress test with the command:')
    Write-DebugText($command)

    $processId = [Microsoft.VisualBasic.Interaction]::Shell($command, $windowBehaviour)


    # This might be necessary to correctly read the process. Or not
    Start-Sleep -Milliseconds 500

    # Get the main window and stress test processes, as well as the main window handle
    # This also works for windows minimized to the tray
    Get-StressTestProcessInformation $true $overrideNumberOfThreads

    # This is to find the exact counter path, as you might have multiple processes with the same name
    if ($enablePerformanceCounters) {
        try {
            # Start a background job to get around the cached Get-Counter value
            $Script:processCounterPathId = Start-Job -ScriptBlock {
                $counterPathName = $args[0].'FullName'
                $processId = $args[1]
                ((Get-Counter $counterPathName -ErrorAction Ignore).CounterSamples | Where-Object { $_.RawValue -eq $processId }).Path
            } -ArgumentList $counterNames, $stressTestProcessId | Wait-Job | Receive-Job

            if (!$processCounterPathId) {
                Exit-WithFatalError -text ('Could not find the counter path for the y-cruncher instance!')
            }

            $Script:processCounterPathTime = $processCounterPathId -Replace $counterNames['SearchString'], $counterNames['ReplaceString']

            Write-VerboseText('The Performance Process Counter Path for the ID:')
            Write-VerboseText($processCounterPathId)
            Write-VerboseText('The Performance Process Counter Path for the Time:')
            Write-VerboseText($processCounterPathTime)
        }
        catch {
            Write-DebugText('Could not query the process path')
            Write-DebugText('Error: ' + $_)
        }
    }
}



<#
.DESCRIPTION
    Close y-cruncher
.PARAMETER
    [Void]
.OUTPUTS
    [Void]
#>
function Close-yCruncher {
    Write-VerboseText('Trying to close y-cruncher')

    $windowProcess = $null
    $stressTestProcess = $null


    # If there is no windowProcessMainWindowHandle id
    # Try to get it
    if (!$windowProcessMainWindowHandle) {
        Write-DebugText('No main window process handle found, trying to get it')
        Get-StressTestProcessInformation $false -1   # Don't exit the script when the process or threads are not found
    }

    # If we now have a windowProcessMainWindowHandle, try to close the window
    if ($windowProcessMainWindowHandle) {
        $windowProcess = Get-Process -Id $windowProcessId -ErrorAction Ignore

        # y-cruncher may be run with or without the wrapper
        if ($isYCruncherWithLogging) {
            # Close both the wrapper and the stress test binary
            $stressTestProcess = Get-Process -Id $stressTestProcessId -ErrorAction Ignore
        }


        if ($isYCruncherWithLogging -and !$stressTestProcess) {
            Write-VerboseText('The stress test process wasn''t found, no need to close it')
        }
        elseif ($isYCruncherWithLogging -and $stressTestProcess) {
            # The process may be suspended, but we don't care, since we're just killing it
            Write-VerboseText('Killing y-cruncher''s stress test process')
            Stop-Process -InputObject $stressTestProcess -Force -ErrorAction Ignore
        }


        # This is executed for both cases
        # If not run with the wrapper, this will be the regular y-cruncher process anyway
        if (!$windowProcess) {
            Write-VerboseText('The window process wasn''t found, no need to close it')
        }
        else {
            # The process may be suspended (only if the wrapper is NOT being used)
            if (!$isYCruncherWithLogging) {
                $null = Resume-Process -process $windowProcess -ignoreError $true

                Write-VerboseText('Trying to gracefully close y-cruncher')
            }
            else {
                Write-VerboseText('Trying to gracefully close y-cruncher''s wrapper (the main window)')
            }

            Write-DebugText('The window process main window handle: ' + $windowProcessMainWindowHandle)

            # Send the message to close the main window
            # The window may still be blocked from the stress test process being closed, so repeat if necessary
            try {
                for ($i = 1; $i -le 5; $i++) {
                    Write-DebugText('Try ' + $i)
                    [Void] $SendMessage::SendMessage($windowProcessMainWindowHandle, $SendMessage::WM_CLOSE, 0, 0)

                    # This seems to make powershell / .Net crash
                    #[Void] $SendMessage::SendMessageTimeout($windowProcessMainWindowHandle, $SendMessage::WM_CLOSE, 0, 0, $SendMessage::SMTO_ABORTIFHUNG, 1000)


                    # We've send the close request, let's wait a second for it to actually exit
                    if ($windowProcess -and !$windowProcess.HasExited) {
                        $timestamp = Get-Date -Format HH:mm:ss
                        Write-VerboseText($timestamp + ' - Sent the close message, waiting for Y-Cruncher to exit')
                        $null = $windowProcess.WaitForExit(1000)
                    }

                    $hasExited = $windowProcess.HasExited
                    Write-VerboseText('         - ... has exited: ' + $hasExited)

                    if ($windowProcess.HasExited) {
                        Write-VerboseText('The main window has exited')

                        # But is the process still there?
                        $windowProcess = Get-Process -Id $windowProcessId -ErrorAction Ignore

                        if (!$windowProcess) {
                            Write-VerboseText('The main window has truly exited')
                            break
                        }
                        else {
                            Write-VerboseText('The main window is still there, trying again')
                        }
                    }
                }
            }
            catch {
                Write-VerboseText('Could not gracefully close y-cruncher, proceeding to kill the process')
                Write-DebugText('Error: ' + $_)
            }
        }
    }


    # If the window is still here at this point, just kill the process
    $windowProcess = Get-Process $processName -ErrorAction Ignore

    if ($windowProcess) {
        Write-VerboseText('Could not gracefully close y-cruncher, killing the process')

        #'The process is still there, killing it'
        # Unfortunately this will leave any tray icons behind
        Stop-Process $windowProcess.Id -Force -ErrorAction Ignore
    }
    else {
        Write-VerboseText('y-cruncher closed')
    }
}



<#
.DESCRIPTION
    Create the config file for Linpack
    Also inserts the correct environment variables into the command string
.PARAMETER overrideNumberOfThreads
    [Int] If this is set, use this value instead of $settings.General.numberOfThreads
.OUTPUTS
    [Void]
#>
function Initialize-Linpack {
    param(
        [Parameter(Mandatory=$false)] $overrideNumberOfThreads
    )

    # Linpack uses environment variables to determine certain settings
    # OMP_NUM_THREADS:    The number of threads to use
    # MKL_NUM_THREADS:    The number of threads to use. Takes precedence over OMP_NUM_THREADS
    # MKL_DEBUG_CPU_TYPE: Up to Intel MKL 2020.x, allows to switch between SSE (0-3), AVX (4) and AVX2 (5) instructions. AVX512 could be 7.
    # OMP_PLACES:         Best set to CORES. It's meaning is "implementation defined": https://www.openmp.org/spec-html/5.0/openmpse53.html
    # OMP_PROC_BIND:      Was set to SPREAD. Maybe FALSE would also work. https://www.openmp.org/spec-html/5.0/openmpse52.html
    # MKL_DYNAMIC:        If TRUE, allows MKL to dynamically change the number of threads (i.e. it will set it to 12 threads if run on a 24 virtual core CPU, instead of all 24). Defaults to TRUE. Should be set to FALSE

    Write-DebugText('Initializing Linpack')

    $fullPathToExe = $stressTestPrograms[$settings.General.stressTestProgram]['fullPathToLoadExe']
    $binaryToRun = $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad'] + '.' + $stressTestPrograms[$settings.General.stressTestProgram]['processNameExt']
    $binaryWithPathToRun = $fullPathToExe + '.' + $stressTestPrograms[$settings.General.stressTestProgram]['processNameExt']


    # Check if the selected binary exists
    Write-VerboseText('Checking if ' + $binaryToRun + ' exists at:')
    Write-VerboseText($binaryWithPathToRun)

    if (!(Test-Path ($binaryWithPathToRun) -PathType Leaf)) {
        Write-ColorText('FATAL ERROR: Could not find Linpack!') Red
        Write-ColorText('             Trying to run "' + $binaryWithPathToRun + '"') Red

        <#
        Write-ColorText('Make sure to download and extract Linpack Xtreme into the following directory:') Red
        Write-ColorText($stressTestPrograms[$settings.General.stressTestProgram]['absoluteInstallPath']) Yellow
        Write-Text ''
        Write-ColorText('You can download Linpack Xtreme from:') Red
        Write-ColorText('https://www.ngohq.com/linpack-xtreme.html') Cyan
        #>

        Exit-WithFatalError
    }

    $configFile = $stressTestPrograms[$settings.General.stressTestProgram]['configFilePath']

    # The memory sizes
    # Problem Size = Number of Equations = sqrt(GB * 1000 * 1000 * 1000 / 8)
    # http://web.archive.org/web/20240303214716/https://www.netlib.org/utk/people/JackDongarra/faq-linpack.html#_For_HPL_What_problem%20size%20N%20should%20
    #
    # From Intel's Linpack help:
    # "just to store the matrix requires at least 8*(leading dimension)*(number of equations) bytes"
    #
    # The values in Linpack Xtreme don't quite match this formula though
    # sqrt(      100 * 1000 * 1000 / 8) =  3535.5
    # sqrt(      250 * 1000 * 1000 / 8) =  5590.2
    # sqrt(      500 * 1000 * 1000 / 8) =  7905.7
    # sqrt(      750 * 1000 * 1000 / 8) =  9682.5
    # sqrt( 1 * 1000 * 1000 * 1000 / 8) = 11180.3
    # sqrt( 2 * 1000 * 1000 * 1000 / 8) = 15811.4  vs  15825  ->  15825/15811.4= 1.00086013888713206927
    # sqrt( 4 * 1000 * 1000 * 1000 / 8) = 22360.7  vs  22611  ->  22611/22360.7= 1.01119374617073705206
    # sqrt( 6 * 1000 * 1000 * 1000 / 8) = 27386.1  vs  27818  ->  27818/27386.1= 1.01577077422488050507
    # sqrt( 8 * 1000 * 1000 * 1000 / 8) = 31622.8  vs  32209  ->  32209/31622.8= 1.01853725792782422809
    # sqrt(10 * 1000 * 1000 * 1000 / 8) = 35355.3  vs  35000  ->  35000/35355.3= 0.98995058732354130781
    # sqrt(14 * 1000 * 1000 * 1000 / 8) = 41833.0  vs  42789  ->  42789/41833.0= 1.02285277173523295006
    # sqrt(30 * 1000 * 1000 * 1000 / 8) = 61237.2  vs  62897  ->  62897/61237.2= 1.02710443978496730745
    #
    #  Preset    Problem Size    Working Set    Paged Memory Size    Runtime (5)    Runtime (3)
    #  100MB      3535             122884096      138047488             0.5s          1.1s
    #  250MB      5590             278528000      293904384             1.8s          4.4s
    #  500MB      7905             528187392      544448512             5.1s         12.4s
    #  750MB      9682             778194944      794996736             9.3s         22.8s
    #  1GB       11180            1027702784     1045536768            14.3s         34.8s
    #            15811            2027700224     2047574016            39.9s
    #  2GB*      15825            2031202304     2051129344            40.1s         98.8s
    #  4GB*      22611            4117999616     4141985792           117s          287s
    #  6GB*      27818            6218633216     6246969344           216s          534s
    #  8GB*      32209            8325988352     8358510592
    # 10GB*      35000            9826689024     9862184960
    # 14GB*      42789           14673854464    14719131648
    # 30GB*      62897           31677247488    31754022912                         >1h
    # * = original preset

    # Calculate the problem size from the provided memory string
    # Problem Size = sqrt(MB * 1000 * 1000 / 8)
    # Problem Size = sqrt(GB * 1000 * 1000 * 1000 / 8)
    # Problem Size = sqrt(TB * 1000 * 1000 * 1000 * 1000 / 8)

    # The default value for the leading dimension (LDA) is problemSize+1
    # It's advised to select the next larger integer value that is divisble by 8 (apparently "odd" multiple, see below)

    # From the xhelp.lpk file:
    # The leading dimension must be no less than the number of equations. Experience has shown that the best performance for a given problem size
    # is obtained when the leading dimension is set to the nearest odd multiple of 8 (16 for Intel(R) AVX processors) equal to or larger
    # than the number of equations (divisible by 8 but not by 16, or divisible by 16 but not 32 for Intel(R) AVX processors).
    # https://stackoverflow.com/questions/49345420/understanding-linpack-input-configuration

    # The string entered by the user
    $memorySizeString = $settings.Linpack.memory.ToLowerInvariant()


    # Removed because we're no longer using Linpack Xtreme
    # Also, let's hard code the problem sizes that are already defined in Linpack Xtreme
    # Calculating these ourselves would result in slightly different values
    # But let's keep these values to be consistent with the standalone version of Linpack Xtreme
    <#
    $hardCodedProblemSizes = @{
        '2GB'  = 15825
        '4GB'  = 22611
        '6GB'  = 27818
        '8GB'  = 32209
        '10GB' = 35000
        '14GB' = 42789
        '30GB' = 62897
    }

    # The default values
    $problemSize = $hardCodedProblemSizes['2GB']
    $leadingDim  = $hardCodedProblemSizes['2GB']

    # Get the memory size in bytes
    [UInt64] $memory = Get-ByteValueFromString -string $memorySizeString

    # Check for a hardcoded value
    $gbValue = ($memory / [Math]::Pow(1000, 3)).ToString() + 'GB'

    # Use the hardcoded value
    if ($hardCodedProblemSizes[$gbValue]) {
        $problemSize = $hardCodedProblemSizes[$gbValue]
        $leadingDim  = $problemSize
        Write-DebugText('Found a hardcoded problem size: "' + $memorySizeString + '" -> ' + $gbValue + ' -> ' + $problemSize + ' (LDA ' + $leadingDim + ')')
    }

    # For any other memory value, calculate the problem size ourself
    else {
        $usesAvx     = ($settings.Linpack.mode -eq 'FAST' -or $settings.Linpack.mode -eq 'FASTEST')
        $problemSize = Get-LinpackProblemSize -memoryBytes $memory -usesAvx $usesAvx
        $leadingDim  = Get-LinpackLeadingDimensionValue -problemSize $problemSize -usesAvx $usesAvx
        Write-DebugText('Calculated the problem size: "' + $memorySizeString + '" -> ' + $memory + ' -> ' + $problemSize + ' (LDA ' + $leadingDim + ')')
    }
    #>


    # 8000 = 512MB
    $problemSize = 8000
    $leadingDim  = 8008

    # Get the memory size in bytes
    [UInt64] $memory = Get-ByteValueFromString -string $memorySizeString

    # Calculate the problem size and leading dimension value
    $usesAvx     = ($settings.mode -eq 'FAST' -or $settings.mode -eq 'FASTEST')
    $problemSize = Get-LinpackProblemSize -memoryBytes $memory -usesAvx $usesAvx
    $leadingDim  = Get-LinpackLeadingDimensionValue -problemSize $problemSize -usesAvx $usesAvx

    Write-DebugText('Calculated the problem size: "' + $memorySizeString + '" -> ' + $memory + ' -> ' + $problemSize + ' (LDA ' + $leadingDim + ')')
    Write-DebugText('Selected Memory: ' + [Math]::Round($memory / 1GB, 1)     + ' GB (' + $memory     + ' bytes) ("memory = ' + $memorySizeString + '")')
    Write-DebugText('Free Memory:     ' + [Math]::Round($freeMemory / 1GB, 1) + ' GB (' + $freeMemory + ' bytes)')
    Write-DebugText('The final problem size: ' + $problemSize)
    Write-DebugText('The leading dimension:  ' + $leadingDim)

    if ($problemSize -lt 1) {
        $errorText  = 'The Linpack memory size is too small or the problem size could not be calculated!'
        $errorText += [Environment]::NewLine + '             (memory = "' + $memorySizeString + '", problem size = ' + $problemSize + ', leading dimensions = ' + $leadingDim + ')'
        Exit-WithFatalError -text $errorText
    }

    # Too much memory!
    if ($memory -gt $freeMemory) {
        $errorText  = 'You have selected too much memory!'
        $errorText += [Environment]::NewLine + '             Selected Memory: ' + [Math]::Round($memory / 1GB, 1)     + ' GB (' + $memory     + ' bytes) ("memory = ' + $memorySizeString + '")'
        $errorText += [Environment]::NewLine + '             Free Memory:     ' + [Math]::Round($freeMemory / 1GB, 1) + ' GB (' + $freeMemory + ' bytes)'
        Exit-WithFatalError -text $errorText
    }


    # If the parameter to override the number of threads is provided, use it, otherwise use the setting value
    $numberOfThreads = $(if ($overrideNumberOfThreads -gt 0) { $overrideNumberOfThreads } else { $settings.General.numberOfThreads })

    # Generate the string that is displayed when Linpack is started
    $linpackStartString = [String]::Format('[CoreCycler] Linpack v{0} - {1} - {2} - {3} bytes', $settings.Linpack.version, $settings.mode, $(if ($numberOfThreads -eq 1) { '1 Thread' } else { '2 Threads' }), $memory)


    # The custom ini file entries
    # Here's some explanation:
    # https://stackoverflow.com/questions/49345420/understanding-linpack-input-configuration
    # The first two lines apparently can be any text
    $configEntries = @(
        'CoreCycler Linpack data file'  # This line is disregarded (can be anything)
        $linpackStartString             # Text to display when starting Linpack
        '1'                             # The number of tests (how many problem sizes appear in the next line). Leave this at 1
        $problemSize                    # The problem size, calculated from the memory size
        $leadingDim                     # Leading dimension of the array. It's advised to set this to the $problemSize+x, to get the closest larger integer value that is an odd multiple of 8
        '9999999'                       # Number of iterations per run (times to run a test ("trials"))
        '4'                             # Alignment values in kilobytes (should be left at 4, but maybe increase it to 16 or 64 for large memory pages)
    )

    [System.IO.File]::WriteAllLines($configFile, $configEntries)

    # Check if the file exists
    if (!(Test-Path $configFile -PathType Leaf)) {
        Exit-WithFatalError -text ('Could not create the config file at ' + $configFile + '!')
    }

    Write-DebugText('Also modifying the startup command, because Linpack requires an')
    Write-DebugText('environment variable for the number of threads')

    # Generate the command line
    # Linpack uses environment variables to set the number of threads
    # If we're restarting the program, the %OMP_NUM_THREADS% variable has already been replaced
    # So also search for the already replaced strings
    $data = @{
        '%OMP_NUM_THREADS%'            = 1
        '\$env:OMP_NUM_THREADS = \d+;' = 1
    }

    $data['%OMP_NUM_THREADS%'] = $numberOfThreads
    $data['\$env:OMP_NUM_THREADS = \d+;'] = [String]::Format('$env:OMP_NUM_THREADS = {0};', $numberOfThreads)

    $command = $stressTestPrograms['linpack']['command']

    foreach ($key in $data.Keys) {
        # -Replace uses regex, .Replace() doesn't
        $command = $command -Replace $key, $data[$key]
    }

    $Script:stressTestPrograms['linpack']['command'] = $command
}



<#
.DESCRIPTION
    Open Linpack and set global script variables
.PARAMETER overrideNumberOfThreads
    [Int] If this is set, use this value instead of $settings.General.numberOfThreads for the expected number of threads
.OUTPUTS
    [Void]
#>
function Start-Linpack {
    param(
        [Parameter(Mandatory=$false)] $overrideNumberOfThreads
    )

    Write-VerboseText('Starting Linpack')

    $command         = $stressTestPrograms[$settings.General.stressTestProgram]['command']
    $command         = $(if ($stressTestProgramWindowToForeground) { $command.Replace('/MIN ', '') } else { $command })   # Remove the /MIN so that the window isn't placed in the background
    $windowBehaviour = $stressTestPrograms[$settings.General.stressTestProgram]['windowBehaviour']
    $windowBehaviour = $(if ($stressTestProgramWindowToForeground) { 1 } else { $windowBehaviour })

    Write-DebugText('Trying to start the stress test with the command:')
    Write-DebugText($command)

    # We're using Powershell to open the binary, since we can use the Tee-Object command to copy the output to a log file
    $processId = [Microsoft.VisualBasic.Interaction]::Shell($command, $windowBehaviour)


    # This might be necessary to correctly read the process. Or not
    Start-Sleep -Milliseconds 500

    # Get the main window and stress test processes, as well as the main window handle
    # This also works for windows minimized to the tray
    Get-StressTestProcessInformation $true $overrideNumberOfThreads

    # This is to find the exact counter path, as you might have multiple processes with the same name
    if ($enablePerformanceCounters) {
        try {
            # Start a background job to get around the cached Get-Counter value
            $Script:processCounterPathId = Start-Job -ScriptBlock {
                $counterPathName = $args[0].'FullName'
                $processId = $args[1]
                ((Get-Counter $counterPathName -ErrorAction Ignore).CounterSamples | Where-Object { $_.RawValue -eq $processId }).Path
            } -ArgumentList $counterNames, $stressTestProcessId | Wait-Job | Receive-Job

            if (!$processCounterPathId) {
                Exit-WithFatalError -text ('Could not find the counter path for the y-cruncher instance!')
            }

            $Script:processCounterPathTime = $processCounterPathId -Replace $counterNames['SearchString'], $counterNames['ReplaceString']

            Write-VerboseText('The Performance Process Counter Path for the ID:')
            Write-VerboseText($processCounterPathId)
            Write-VerboseText('The Performance Process Counter Path for the Time:')
            Write-VerboseText($processCounterPathTime)
        }
        catch {
            Write-DebugText('Could not query the process path')
            Write-DebugText('Error: ' + $_)
        }
    }
}



<#
.DESCRIPTION
    Close Linpack
.PARAMETER
    [Void]
.OUTPUTS
    [Void]
#>
function Close-Linpack {
    Write-VerboseText('Trying to close Linpack')


    # If there is no windowProcessMainWindowHandle id
    # Try to get it
    if (!$windowProcessMainWindowHandle) {
        Get-StressTestProcessInformation $false -1   # Don't exit the script when the process or threads are not found
    }


    # If we now have a windowProcessMainWindowHandle, try to close the window
    if ($windowProcessMainWindowHandle) {
        $windowProcess = Get-Process -Id $windowProcessId -ErrorAction Ignore

        if (!$windowProcess) {
            Write-VerboseText('The window process wasn''t found, no need to close it')
        }
        else {
            # Is the stress test process still running?
            $stressTestProcess = Get-Process -Id $stressTestProcessId -ErrorAction Ignore

            # If yes, the process may be suspended
            if ($stressTestProcess) {
                $null = Resume-Process -process $stressTestProcess -ignoreError $true
            }


            Write-VerboseText('Trying to gracefully close Linpack')
            Write-DebugText('The window process main window handle: ' + $windowProcessMainWindowHandle)

            # Send the message to close the main window
            # The window may still be blocked from the stress test process being closed, so repeat if necessary
            try {
                for ($i = 1; $i -le 5; $i++) {
                    Write-DebugText('Try ' + $i)
                    [Void] $SendMessage::SendMessage($windowProcessMainWindowHandle, $SendMessage::WM_CLOSE, 0, 0)

                    # We've send the close request, let's wait a second for it to actually exit
                    if ($windowProcess -and !$windowProcess.HasExited) {
                        $timestamp = Get-Date -Format HH:mm:ss
                        Write-VerboseText($timestamp + ' - Sent the close message, waiting for Linpack to exit')
                        $null = $windowProcess.WaitForExit(1000)
                    }

                    $hasExited = $windowProcess.HasExited
                    Write-VerboseText('         - ... has exited: ' + $hasExited)

                    if ($windowProcess.HasExited) {
                        Write-VerboseText('The main window has exited')

                        # But is the process still there?
                        $windowProcess = Get-Process -Id $windowProcessId -ErrorAction Ignore

                        if (!$windowProcess) {
                            Write-VerboseText('The main window has truly exited')
                            break
                        }
                        else {
                            Write-VerboseText('The main window is still there, trying again')
                        }
                    }
                }
            }
            catch {
                Write-VerboseText('Could not gracefully close Linpack, proceeding to kill the process')
                Write-DebugText('Error: ' + $_)
            }
        }
    }


    # If we didn't find a windowProcessMainWindowHandle, try to check if the binary is open, and kill that instead
    elseif (!$windowProcessMainWindowHandle) {
        $binaryProcess = Get-Process $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad'] -ErrorAction Ignore

        if ($binaryProcess) {
            Write-VerboseText('Found at least one process for ' + $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad'] + ', killing all of them')

            $binaryProcess | ForEach-Object {
                Write-VerboseText('Killing Process ' + $_.Id)
                Write-VerboseText('Path:  ' + $_.Path)
                Write-VerboseText('Title: ' + $_.MainWindowTitle)
                Stop-Process $_.Id -Force -ErrorAction Continue
            }
        }
    }



    # If the window is still here at this point, just kill the process
    $windowProcess = Get-Process $processName -ErrorAction Ignore

    if ($windowProcess) {
        Write-VerboseText('Could not gracefully close Linpack, killing the process')

        #'The process is still there, killing it'
        # Unfortunately this will leave any tray icons behind
        Stop-Process $windowProcess.Id -Force -ErrorAction Ignore
    }
    else {
        Write-VerboseText('Linpack closed')
    }
}



<#
.DESCRIPTION
    Initialize the selected stress test program
.PARAMETER overrideNumberOfThreads
    [Int] If this is set, use this value instead of $settings.General.numberOfThreads
.OUTPUTS
    [Void]
#>
function Initialize-StressTestProgram {
    param(
        [Parameter(Mandatory=$false)] $overrideNumberOfThreads
    )

    Write-VerboseText('Initializing the stress test program')

    if ($overrideNumberOfThreads) {
        Write-DebugText('Override the number of threads: ' + $overrideNumberOfThreads)
    }

    if ($isPrime95) {
        Test-Prime95
        Initialize-Prime95 $overrideNumberOfThreads
    }
    elseif ($isAida64) {
        Initialize-Aida64   # No number of threads to override, Aida64 already always starts with 4 threads
    }
    elseif ($isYCruncher -or $isYCruncherOld) {
        Initialize-yCruncher $overrideNumberOfThreads
    }
    elseif ($isLinpack) {
        Initialize-Linpack $overrideNumberOfThreads
    }
    else {
        Exit-WithFatalError -text 'No stress test program selected!'
    }
}



<#
.DESCRIPTION
    Start the selected stress test program
.PARAMETER startOnlyStressTestProcess
    [Bool] If this is set, it will only start the stress test process and not the whole program
           Currently this is only supported when starting Aida64 (it uses a dedicated DLL to perform the stress test)
.PARAMETER overrideNumberOfThreads
    [Int] If this is set, use this value instead of $settings.General.numberOfThreads for the expected number of threads
.OUTPUTS
    [Void]
#>
function Start-StressTestProgram {
    param(
        [Parameter(Mandatory=$false)] [Bool] $startOnlyStressTestProcess = $false,
        [Parameter(Mandatory=$false)] $overrideNumberOfThreads
    )

    Write-VerboseText('Starting the stress test program')

    if ($isPrime95) {
        Start-Prime95 $overrideNumberOfThreads
    }
    elseif ($isAida64) {
        Start-Aida64 $startOnlyStressTestProcess $overrideNumberOfThreads
    }
    elseif ($isYCruncher -or $isYCruncherOld) {
        Start-yCruncher $overrideNumberOfThreads
    }
    elseif ($isLinpack) {
        Start-Linpack $overrideNumberOfThreads
    }
    else {
        Exit-WithFatalError -text 'No stress test program selected!'
    }
}



<#
.DESCRIPTION
    Close the selected stress test program
.PARAMETER closeOnlyStressTest
    [Bool] If this is set, it will only close the stress test process and not the whole program
.OUTPUTS
    [Void]
#>
function Close-StressTestProgram {
    param(
        [Parameter(Mandatory=$false)] [Bool] $closeOnlyStressTest = $false
    )

    Write-VerboseText('Trying to close the stress test program')

    if ($isPrime95) {
        Close-Prime95
    }
    elseif ($isAida64) {
        Close-Aida64 $closeOnlyStressTest
    }
    elseif ($isYCruncher -or $isYCruncherOld) {
        Close-yCruncher
    }
    elseif ($isLinpack) {
        Close-Linpack
    }
    else {
        Exit-WithFatalError -text 'No stress test program selected!'
    }
}



<#
.DESCRIPTION
    Check if there has been an error while running the stress test program and restart it if necessary
    Checks the existance of the process, the log file (if available), and the CPU utilization (if the setting is enabled)
    Throws an error if something is wrong (PROCESSMISSING, CALCULATIONERROR, CPULOAD)
.PARAMETER coreNumber
    [Int] The current core being tested
.PARAMETER coreStartDate
    [Date] The date when core was started
.OUTPUTS
    [Void] But throws a string if there was an error with the CPU usage (PROCESSMISSING, CALCULATIONERROR, CPULOAD)
#>
function Test-StressTestProgrammIsRunning {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'index')]     # This fixes the incorrect "assigned but never used" detection of the $index variable
    param (
        $coreNumber,
        $coreStartDate
    )

    # Clear any previous errors
    $Error.Clear()

    $timestamp = Get-Date -Format HH:mm:ss

    # Set to a string if there was an error
    $stressTestError = $false

    # What type of error occurred (PROCESSMISSING, CALCULATIONERROR, CPULOAD, WHEAERROR)
    $errorType = $null

    # Does the stress test process still exist?
    $checkProcess = Get-Process -Id $stressTestProcessId -ErrorAction Ignore

    Write-DebugText($timestamp + ' - Checking for stress test errors')


    # 1. The process doesn't exist anymore, immediate error
    if (!$checkProcess) {
        $stressTestError = 'The ' + $selectedStressTestProgram + ' process doesn''t exist anymore.'
        $errorType = 'PROCESSMISSING'
    }


    # 2. Parse the log file if it exists and look for an error
    if (!$stressTestError) {
        # If using Prime95, parse the results.txt file and look for an error message
        if ($isPrime95) {
            Write-DebugText('           Checking the new Prime95 log entries...')

            # Look for a line with an "error" string in the new log entries
            $errorResults = $newLogEntries | Where-Object { $_.Line -Match '.*error.*' } | Select-Object -Last 1

            # Found the "error" string
            if ($errorResults) {
                # We don't need to check for a false alarm anymore, as we're already checking only new log entries
                $stressTestError = $errorResults.Line
                $errorType = 'CALCULATIONERROR'

                Write-VerboseText($timestamp)
                Write-VerboseText('Found an error in the new entries of the results.txt!')
            }
        }


        # We can use a wrapper to capture the output for yCruncher
        elseif ($isYCruncherWithLogging) {
            Write-DebugText('           Checking the new y-cruncher log entries...')

            # The messages y-cruncher displays:
            # Exception Encountered: XYZ
            #
            # <ERROR MESSAGE>
            # <May have multiple lines>
            #
            #
            # Error(s) encountered on logical core X
            #
            # Failed  Test Speed <...>
            # Errors encountered. Stopping test...

            # Look for a line with an "error" string in the new log entries
            $errorResults = $newLogEntries | Where-Object { $_.Line -Match '.*error\(s\).*' } | Select-Object -Last 1

            # Found the "error" string
            if ($errorResults) {
                # We don't need to check for a false alarm anymore, as we're already checking only new log entries
                $stressTestError = $errorResults.Line
                $errorType = 'CALCULATIONERROR'

                Write-VerboseText($timestamp)
                Write-VerboseText('Found an error in the new entries of the y-cruncher output!')

                # For y-cruncher, remove the core number, since it doesn't represent the actual core being tested
                $stressTestError = $stressTestError -Replace '\s*\d+\.', ''
            }
        }


        # Linpack also has a log file, created by Powershell's Tee-Object
        elseif ($isLinpack) {
            Write-DebugText('           Checking the new Linpack log entries...')

            Write-DebugText('           The new log file entries to check:')
            $newLogEntries | ForEach-Object {
                Write-DebugText('           [Line ' + $_.LineNumber + '] ' + $_.Line)
            }

            # Look for a line with a "fail" string in the new log entries
            $errorResults = $newLogEntries | Where-Object { $_.Line -Match '.*fail.*' } | Select-Object -Last 1

            Write-DebugText('           errorResults:')
            Write-DebugText('           ' + $(if ($errorResults) { $errorResults } else { 'null' }))

            # Found the "fail" string
            if ($errorResults) {
                # We don't need to check for a false alarm anymore, as we're already checking only new log entries
                $stressTestError = $errorResults.Line
                $errorType = 'CALCULATIONERROR'

                Write-VerboseText($timestamp)
                Write-VerboseText('Found an error in the new entries of the Linpack output!')
            }
        }
    }


    # 3. Look for WHEA errors
    # Only treat this as a true error if the treatWheaWarningAsError setting was set
    if (!$stressTestError) {
        if ($settings.General.lookForWheaErrors -gt 0) {
            $lastWheaError = Compare-WheaErrorEntries $coreStartDate

            if ($lastWheaError) {
                $timestamp = Get-Date -Format HH:mm:ss

                $cpuNumberString = (($coresInfo['coreToCpus'][$coreNumber] | Sort-Object) -Join ' or ')
                $coreString = $coreNumber.ToString() + ' (CPU ' + $cpuNumberString + ')'

                $wheaMessageArray = $lastWheaError.Message -Split '\r?\n'
                $firstMessagEntry, $wheaMessageArray = $wheaMessageArray

                # Get the core from the WHEA message
                $apicIdFromWheaMessage = Convert-WheaMessageToApicId $lastWheaError
                $coreFromWheaMessage   = Convert-WheaMessageToCoreId $lastWheaError

                Write-DebugText('The core extracted APIC ID from the WHEA message: ' + $apicIdFromWheaMessage)
                Write-DebugText('The core extracted from the WHEA message:         ' + $coreFromWheaMessage)


                # Depending on the settings, this is either a warning or an error
                # However it is only an error if the core matches the APIC ID
                if ($settings.General.treatWheaWarningAsError -gt 0) {
                    if ($actualCoreNumber -eq $coreFromWheaMessage) {
                        Write-DebugText('The core from the WHEA message matches the tested core (' + $coreNumber + ' = ' + $coreFromWheaMessage + ')')

                        $stressTestError = 'There has been a WHEA error while running this test and the setting to treat this as an error has been set!'
                        $errorType = 'WHEAERROR'
                    }

                    # Wrong core, just display a warning
                    else {
                        Write-DebugText('The core from the WHEA message does not match the tested core (' + $coreNumber + ' = ' + $coreFromWheaMessage + ')')

                        Write-ColorText('WARNING: ' + $timestamp) Magenta
                        Write-ColorText('WARNING: There seems to have been a WHEA error while running this test!') Magenta
                        Write-ColorText('WARNING: At Core ' + $coreString) Magenta
                        Write-ColorText('WARNING: The flag to treat this as an error has been set, but the APIC ID from the WHEA message does not match the tested core!') Magenta
                        Write-ColorText('WHEA TIMESTAMP: ' + $lastWheaError.TimeCreated.ToString()) Magenta
                        Write-ColorText('WHEA EVENT ID:  ' + $lastWheaError.Id) Magenta
                        Write-ColorText('WHEA APIC ID:   ' + $apicIdFromWheaMessage) Magenta
                        Write-ColorText('WHEA MESSAGE:   ' + $firstMessagEntry) Magenta

                        $wheaMessageArray | ForEach-Object {
                            Write-ColorText('                ' + $_) Magenta
                        }
                    }
                }

                # Not treating as an error, just display a warning message
                else {
                    Write-ColorText('WARNING: ' + $timestamp) Magenta
                    Write-ColorText('WARNING: There seems to have been a WHEA error while running this test!') Magenta
                    Write-ColorText('WARNING: At Core ' + $coreString) Magenta
                    Write-ColorText('WHEA TIMESTAMP:  ' + $lastWheaError.TimeCreated.ToString()) Magenta
                    Write-ColorText('WHEA EVENT ID:   ' + $lastWheaError.Id) Magenta
                    Write-ColorText('WHEA APIC ID:    ' + $apicIdFromWheaMessage) Magenta
                    Write-ColorText('WHEA MESSAGE:    ' + $firstMessagEntry) Magenta

                    $wheaMessageArray | ForEach-Object {
                        Write-ColorText('                ' + $_) Magenta
                    }
                }


                # Add the WHEA error always to the event log (if we use it)
                if ($canUseWindowsEventLog) {
                    $errorString  = 'Timestamp: ' + $lastWheaError.TimeCreated.ToString()
                    $errorString += [Environment]::NewLine + 'WHEA Record Id: ' + $lastWheaError.RecordId.ToString()
                    $errorString += [Environment]::NewLine + 'WHEA Event Id: ' + $lastWheaError.Id.ToString()
                    $errorString += [Environment]::NewLine + 'APIC ID: ' + $apicIdFromWheaMessage
                    $errorString += [Environment]::NewLine + 'APIC ID converted to Core: ' + $coreFromWheaMessage
                    $errorString += [Environment]::NewLine + 'CoreCycler was running on Core: ' + $coreNumber
                    $errorString += [Environment]::NewLine + [Environment]::NewLine + 'Message: ' + $lastWheaError.Message

                    Write-AppEventLog -type 'core_whea' -infoString1 $coreString -infoString2 $errorString
                }

                # Store the core number in the array
                $Script:coresWithWheaError += $actualCoreNumber
                $Script:numCoresWithWheaError = $coresWithWheaError.Count

                # Count the number of errors per core
                $Script:coresWithWheaErrorsCounter[$actualCoreNumber]++
            }
        }
    }



    # 4. Check if the process is still using enough CPU process power
    # Only if we have the setting to do so enabled
    if (!$stressTestError) {
        # If the CPU utilization check is disabled in the settings
        if ($disableCpuUtilizationCheck -gt 0) {
            #Write-DebugText('Checking CPU usage is disabled, skipping the check')
        }

        # If the CPU utilization check is enabled in the settings, but not using the Windows Performance Counters
        elseif (!$enablePerformanceCounters) {
            # Let's fall back to the more general property of the process itself, instead of using the Windows Process Counters
            # TotalProcessorTime
            # A TimeSpan that indicates the amount of time that the associated process has spent utilizing the CPU. This value is the sum of the UserProcessorTime and the PrivilegedProcessorTime.
            # UserProcessorTime
            # A TimeSpan that indicates the amount of time that the associated process has spent running code inside the application portion of the process (not inside the operating system core).
            # PrivilegedProcessorTime
            # A TimeSpan that indicates the amount of time that the process has spent running code inside the operating system core.
            # TotalProcessorTime = UserProcessorTime + PrivilegedProcessorTime
            # .CPU = .TotalProcessorTime.TotalSeconds

            # The .UserProcessorTime.TotalSeconds property seems to be the best one, as it only seems to observe the actual stress tests
            #$cpuTime1 = $checkProcess.UserProcessorTime.TotalSeconds; Start-Sleep -Milliseconds 100; $cpuTime2 = $checkProcess.UserProcessorTime.TotalSeconds; '$cpuTime1: ' + $cpuTime1 + [Environment]::NewLine + '$cpuTime2: ' +$cpuTime2;

            # Note: For two threads, the processor time is actually 2x the measure time
            #       We're handling this by using the "factor" variables
            do {
                $measureTime  = 100
                $expectedTime = $measureTime * $factorForExpectedUsage      # 100 * 1 for 1 thread = 100ms or 100 * 2 = 200ms for 2 threads
                $minTime      = $measureTime * $factorForMinProcessorTime   # 50% usage of the expected usage
                $waitTime     = 2000
                $maxChecks    = 3

                try {
                    $cpuTime1 = $checkProcess.UserProcessorTime.TotalSeconds
                    Start-Sleep -Milliseconds $measureTime
                    $cpuTime2 = $checkProcess.UserProcessorTime.TotalSeconds
                }

                # We assume that the process doesn't exist anymore if this fails
                catch {
                    $timestamp = Get-Date -Format HH:mm:ss

                    # Does the stress test process still exist?
                    $checkProcess = Get-Process -Id $stressTestProcessId -ErrorAction Ignore

                    Write-DebugText($timestamp + ' - Checking for stress test errors')

                    if (!$checkProcess) {
                        $stressTestError = 'The ' + $selectedStressTestProgram + ' process doesn''t exist anymore.'
                        $errorType = 'PROCESSMISSING'
                        break
                    }
                    else {
                        throw $_
                    }
                }

                $measuredTime = [Math]::Round(($cpuTime2 - $cpuTime1) * 1000, 0)

                # For 100% core usage, this should be 0.1 seconds time increase during 100 milliseconds
                Write-VerboseText($timestamp + ' - Checking CPU usage: ' + $measuredTime + 'ms (expected: ' + $expectedTime + 'ms, lower limit: ' + $minTime + 'ms)')

                if ($measuredTime -le $minTime) {
                    # For Prime95
                    if ($isPrime95) {
                        # Look for a line with an "error" string in the new log entries
                        $errorResults = $newLogEntries | Where-Object { $_.Line -Match '.*error.*' } | Select-Object -Last 1

                        # Found the "error" string
                        if ($errorResults) {
                            # We don't need to check for a false alarm anymore, as we're already checking only new log entries
                            $stressTestError = $errorResults.Line
                            $errorType = 'CALCULATIONERROR'
                        }
                    }


                    # For y-cruncher with logging enabled
                    elseif ($isYCruncherWithLogging) {
                        # Look for a line with an "error" string in the new log entries
                        $errorResults = $newLogEntries | Where-Object { $_.Line -Match '.*error\(s\).*' } | Select-Object -Last 1

                        # Found the "error" string
                        if ($errorResults) {
                            # We don't need to check for a false alarm anymore, as we're already checking only new log entries
                            $stressTestError = $errorResults.Line
                            $errorType = 'CALCULATIONERROR'
                        }
                    }

                    # For Linpack
                    elseif ($isLinpack) {
                        # Look for a line with a "fail" string in the new log entries
                        $errorResults = $newLogEntries | Where-Object { $_.Line -Match '.*fail.*' } | Select-Object -Last 1

                        # Found the "fail" string
                        if ($errorResults) {
                            # We don't need to check for a false alarm anymore, as we're already checking only new log entries
                            $stressTestError = $errorResults.Line
                            $errorType = 'CALCULATIONERROR'
                        }
                    }



                    # Error string still not found
                    # This might have been a false alarm, wait a bit and try again
                    if (!$stressTestError) {
                        # Repeat the CPU usage check $maxChecks times and only throw an error if the process hasn't recovered by then
                        for ($curCheck = 1; $curCheck -le $maxChecks; $curCheck++) {
                            $timestamp = Get-Date -Format HH:mm:ss
                            Write-VerboseText($timestamp + ' - ...the CPU usage was too low, waiting ' + $waitTime + 'ms for another check...')

                            # Let's use the wait time as the measure time!
                            try {
                                $measureTime = $waitTime
                                $cpuTime1 = $checkProcess.UserProcessorTime.TotalSeconds
                                Start-Sleep -Milliseconds $measureTime
                                $cpuTime2 = $checkProcess.UserProcessorTime.TotalSeconds
                                $measuredTime = [Math]::Round(($cpuTime2 - $cpuTime1) * 1000, 0)

                                $expectedTime = $measureTime * $factorForExpectedUsage
                                $minTime      = $measureTime * $factorForMinProcessorTime
                            }

                            # We assume that the process doesn't exist anymore if this fails
                            catch {
                                $timestamp = Get-Date -Format HH:mm:ss

                                # Does the stress test process still exist?
                                $checkProcess = Get-Process -Id $stressTestProcessId -ErrorAction Ignore

                                Write-DebugText($timestamp + ' - Checking for stress test errors')

                                if (!$checkProcess) {
                                    $stressTestError = 'The ' + $selectedStressTestProgram + ' process doesn''t exist anymore.'
                                    $errorType = 'PROCESSMISSING'
                                }
                                else {
                                    throw $_
                                }

                                break
                            }

                            $timestamp = Get-Date -Format HH:mm:ss
                            Write-VerboseText($timestamp + ' - Checking CPU usage again (#' + $curCheck + '): ' + $measuredTime + 'ms (expected: ' + $expectedTime + 'ms, lower limit: ' + $minTime + 'ms)')

                            # If we have recovered, break and continue with stresss testing
                            if ($measuredTime -ge $minTime) {
                                Write-VerboseText('           The process seems to have recovered, continuing with stress testing')
                                break
                            }

                            else {
                                if ($curCheck -lt $maxChecks) {
                                    Write-VerboseText('           Still not enough usage (#' + $curCheck + ')')
                                }

                                # Reached the maximum amount of checks for the CPU usage
                                else {
                                    Write-VerboseText('           Still not enough usage, throw an error')

                                    # We don't care about an error string here anymore
                                    $stressTestError = 'The ' + $selectedStressTestProgram + ' process doesn''t use enough CPU power anymore (only ' + $measuredTime + 'ms instead of the expected ' + $expectedTime + 'ms)'
                                    $errorType = 'CPULOAD'
                                }
                            }
                        }
                    }
                }
            } while (0)
        }


        # If the CPU utlization check should use the Windows Performance Counters
        elseif ($enablePerformanceCounters) {
            # Get the CPU percentage
            $processCPUPercentage = [Math]::Round(((Get-Counter $processCounterPathTime -ErrorAction Ignore).CounterSamples.CookedValue) / $numLogicalCores, 2)

            Write-VerboseText($timestamp + ' - Checking CPU usage: ' + $processCPUPercentage + '% (expected: ' + $expectedUsageTotal + '%, lower limit: ' + $minProcessUsage + '%)')

            # It doesn't use enough CPU power
            if ($processCPUPercentage -le $minProcessUsage) {

                # For Prime95
                if ($isPrime95) {
                    # Look for a line with an "error" string in the new log entries
                    $errorResults = $newLogEntries | Where-Object { $_.Line -Match '.*error.*' } | Select-Object -Last 1

                    # Found the "error" string
                    if ($errorResults) {
                        # We don't need to check for a false alarm anymore, as we're already checking only new log entries
                        $stressTestError = $errorResults.Line
                        $errorType = 'CALCULATIONERROR'
                    }
                }


                # For y-cruncher with logging enabled
                elseif ($isYCruncherWithLogging) {
                    # Look for a line with an "error" string in the new log entries
                    $errorResults = $newLogEntries | Where-Object { $_.Line -Match '.*error\(s\).*' } | Select-Object -Last 1

                    # Found the "error" string
                    if ($errorResults) {
                        # We don't need to check for a false alarm anymore, as we're already checking only new log entries
                        $stressTestError = $errorResults.Line
                        $errorType = 'CALCULATIONERROR'
                    }
                }

                # For Linpack
                elseif ($isLinpack) {
                    # Look for a line with a "fail" string in the new log entries
                    $errorResults = $newLogEntries | Where-Object { $_.Line -Match '.*fail.*' } | Select-Object -Last 1

                    # Found the "fail" string
                    if ($errorResults) {
                        # We don't need to check for a false alarm anymore, as we're already checking only new log entries
                        $stressTestError = $errorResults.Line
                        $errorType = 'CALCULATIONERROR'
                    }
                }



                # Error string still not found
                # This might have been a false alarm, wait a bit and try again
                if (!$stressTestError) {
                    $waitTime  = 2000
                    $maxChecks = 3

                    # Repeat the CPU usage check $maxChecks times and only throw an error if the process hasn't recovered by then
                    for ($curCheck = 1; $curCheck -le $maxChecks; $curCheck++) {
                        $timestamp = Get-Date -Format HH:mm:ss
                        Write-VerboseText($timestamp + ' - ...the CPU usage was too low, waiting ' + $waitTime + 'ms for another check...')

                        Start-Sleep -Milliseconds $waitTime

                        # The additional check
                        # Do the whole process path procedure again
                        $thisProcessId = $checkProcess.Id[0]

                        Write-VerboseText('Process Id: ' + $thisProcessId)

                        # Start a background job to get around the cached Get-Counter value
                        $thisProcessCounterPathId = Start-Job -ScriptBlock {
                            $counterPathName = $args[0].'FullName'
                            $processId = $args[1]
                            ((Get-Counter $counterPathName -ErrorAction Ignore).CounterSamples | Where-Object { $_.RawValue -eq $processId }).Path
                        } -ArgumentList $counterNames, $thisProcessId | Wait-Job | Receive-Job

                        $thisProcessCounterPathTime = $thisProcessCounterPathId -Replace $counterNames['SearchString'], $counterNames['ReplaceString']
                        $thisProcessCPUPercentage   = [Math]::Round(((Get-Counter $thisProcessCounterPathTime -ErrorAction Ignore).CounterSamples.CookedValue) / $numLogicalCores, 2)

                        $timestamp = Get-Date -Format HH:mm:ss
                        Write-VerboseText($timestamp + ' - Checking CPU usage again (#' + $curCheck + '): ' + $thisProcessCPUPercentage + '% (expected: ' + $expectedUsageTotal + '%, lower limit: ' + $minProcessUsage + '%)')

                        # If we have recovered, break and continue with stresss testing
                        if ($thisProcessCPUPercentage -ge $minProcessUsage) {
                            Write-VerboseText('           The process seems to have recovered, continuing with stress testing')
                            break
                        }

                        else {
                            if ($curCheck -lt $maxChecks) {
                                Write-VerboseText('           Still not enough usage (#' + $curCheck + ')')
                            }

                            # Reached the maximum amount of checks for the CPU usage
                            else {
                                Write-VerboseText('           Still not enough usage, throw an error')

                                # We don't care about an error string here anymore
                                $stressTestError = 'The ' + $selectedStressTestProgram + ' process doesn''t use enough CPU power anymore (only ' + $thisProcessCPUPercentage + '% instead of the expected ' + $expectedUsageTotal + '%)'
                                $errorType = 'CPULOAD'
                            }
                        }
                    }
                }
            }
        }
    }


    # No stress test error found, abort
    if (!$stressTestError) {
        return
    }


    Write-VerboseText('There has been an error while running the stress test program!')
    Write-VerboseText('Error type: ' + $errorType)

    # Store the core number in the array
    $Script:coresWithError += $coreNumber
    $Script:numCoresWithError = $coresWithError.Count

    # Count the number of errors per core
    $Script:coresWithErrorsCounter[$coreNumber]++

    $cpuNumbersArray = @()
    $errorLogMessage = ''

    # If the processor has a different architecture between the cores
    # E.g. performance cores with 2 threads and efficient cores with only 1 thread
    if ($Script:hasAsymmetricCoreThreads -and $Script:coresWithOneThread.Contains($coreNumber)) {
        # All previous coresWithTwoThreads * 2 + all previous coresWithOneThread * 1
        # We do assume that the cores with only one thread all appear after the cores with two threads

        #two: [0, 1, 2, 3, 4, 5]         -> [0,1 - 2,3 - 4,5 - 6,7 - 8,9 - 10,11]
        #one: [6, 7, 8, 9]               -> [12, 13, 14, 15]
        #core: 8
        #index: 2
        #cpu: (5+1) * 2 + 2 -> 12 + 2 -> 14

        $cpuNumber        = ($Script:coresWithTwoThreads[-1] + 1) * 2 + [Array]::indexOf($Script:coresWithOneThread, $coreNumber)
        $cpuNumbersArray += $cpuNumber
    }

    # All cores support the same amount of threads (either one or two)
    else {
        # If the number of threads is more than 1
        if ($settings.General.numberOfThreads -gt 1) {
            for ($currentThread = 0; $currentThread -lt $settings.General.numberOfThreads; $currentThread++) {
                # We don't care about Hyperthreading / SMT here, it needs to be enabled for 2 threads
                $cpuNumber        = ($coreNumber * 2) + $currentThread
                $cpuNumbersArray += $cpuNumber
            }
        }

        # Only one thread
        else {
            # assignBothVirtualCoresForSingleThread is enabled, we want to use both virtual cores, but with only one thread
            # The load should bounce back and forth between the two cores this way
            # Hyperthreading needs to be enabled for this
            if ($settings.General.assignBothVirtualCoresForSingleThread -and $Script:isHyperthreadingEnabled) {
                for ($currentThread = 0; $currentThread -lt 2; $currentThread++) {
                    $cpuNumber        = ($coreNumber * 2) + $currentThread
                    $cpuNumbersArray += $cpuNumber
                }
            }

            # Setting not active, only one core for the load thread
            else {
                # If Hyperthreading / SMT is enabled, the tested CPU number is 0, 2, 4, etc
                # If disabled, the CPU number is the same value as the core number
                $cpuNumber        = $coreNumber * (1 + [Int] $Script:isHyperthreadingEnabled)
                $cpuNumbersArray += $cpuNumber
            }
        }
    }

    $cpuNumberString = (($cpuNumbersArray | Sort-Object) -Join ' or ')


    # If running a stress with logging capabilities, and if we haven't already found a log entry,
    # make one additional check if the log file now has an error entry
    if (($isPrime95 -or $isYCruncherWithLogging -or $isLinpack) -and $errorType -ne 'CALCULATIONERROR' -and $errorType -ne 'WHEAERROR') {
        $timestamp = Get-Date -Format HH:mm:ss

        Write-VerboseText($timestamp + ' - The stress test program has a log file, trying to look for an error message in the log')

        Get-NewLogfileEntries

        # Prime95: Look for a line with an "error" string in the new log entries
        if ($isPrime95) {
            $errorResults = $newLogEntries | Where-Object { $_.Line -Match '.*error.*' } | Select-Object -Last 1
        }

        # y-cruncher: Look for "error(s)"
        elseif ($isYCruncherWithLogging) {
            $errorResults = $newLogEntries | Where-Object { $_.Line -Match '.*error\(s\).*' } | Select-Object -Last 1
        }

        # Linpack: Look for "fail"
        elseif ($isLinpack) {
            $errorResults = $newLogEntries | Where-Object { $_.Line -Match '.*fail.*' } | Select-Object -Last 1
        }


        # Found the "error" string
        if ($errorResults) {
            # We don't need to check for a false alarm anymore, as we're already checking only new log entries
            $stressTestError = $errorResults.Line

            # For y-cruncher, remove the core number, since it doesn't represent the actual core being tested
            if ($isYCruncherWithLogging) {
                $stressTestError = $stressTestError -Replace '\s*\d+\.', ''
            }

            Write-VerboseText($timestamp)
            Write-VerboseText('           Now found an error in the new entries of the log file!')
        }
    }


    # Put out an error message
    $timestamp = Get-Date -Format HH:mm:ss
    Write-ColorText('ERROR: ' + $timestamp) Magenta
    Write-ColorText('ERROR: There has been an error while running ' + $selectedStressTestProgram + '!') Magenta
    Write-ColorText('ERROR: At Core ' + $coreNumber + ' (CPU ' + $cpuNumberString + ')') Magenta
    Write-ColorText('ERROR MESSAGE: ' + $stressTestError) Magenta

    # Additional information for true WHEA errors


    # Flash!
    if ($settings.General.flashOnError) {
        # We need to use the parent process of this script, which is the cmd.exe calling the PowerShell script
        # The script process itself ($PID) doesn't have a main window handle
        [Void] [Window]::FlashWindow($parentMainWindowHandle, 500, 4)
    }


    # Beep!
    if ($settings.General.beepOnError) {
        [Console]::Beep(450, 400)
    }



    # Try to get more detailed error information

    # A WHEA Error
    if ($errorType -eq 'WHEAERROR') {
        Write-ColorText('ERROR: At Core ' + $coreString + ' (APIC ID ' + $apicIdFromWheaMessage + ' = Core ' + $coreFromWheaMessage + ')') Magenta
        Write-ColorText('WHEA TIMESTAMP: ' + $lastWheaError.TimeCreated.ToString()) Magenta
        Write-ColorText('WHEA EVENT ID:  ' + $lastWheaError.Id) Magenta
        Write-ColorText('WHEA APIC ID:   ' + $apicIdFromWheaMessage) Magenta
    }


    # Prime95
    elseif ($isPrime95) {
        # Try to determine the last run FFT size
        $lastRunFFT    = $null
        $lastPassedFFT = $null
        $lastFiveRows  = @()

        # In newer Prime95 versions, the FFT size is provided in the results.txt
        # In older versions, we have to make an eduacted guess

        # Check in the error message
        # "Hardware failure detected running 10752K FFT size, consult stress.txt file."
        $lastFFTErrorEntry = $newLogEntries | Where-Object { $_.Line -Match 'Hardware failure detected running \d+K FFT size*' } | Select-Object -Last 1

        if ($lastFFTErrorEntry) {
            Write-VerboseText('There was an FFT size provided in the error message, use it.')

            $hasMatched = $lastFFTErrorEntry -Match 'Hardware failure detected running (\d+)K FFT size'
            $lastRunFFT = if ($hasMatched) { [Int] $Matches[1] }   # $Matches is a fixed(?) variable name for -Match

            Write-ColorText('ERROR: The error happened at FFT size ' + $lastRunFFT + 'K') Magenta
            $errorLogMessage = 'Hardware failure detected running ' + $lastRunFFT + 'K FFT size'
        }


        # If nothing was found, try to guess
        else {
            # If the results.txt doesn't exist, assume that it was on the very first iteration
            # Note: Unfortunately Prime95 randomizes the FFT sizes for anything above Large FFT sizes
            #       So we cannot make an educated guess for these settings
            #if ($maxFFTSize -le $FFTMinMaxValues[$settings.mode]['LARGE'].Max) {

            # This check is taken from the Prime95 source code:
            # if (fftlen > max_small_fftlen * 2) num_large_lengths++;
            # The max smallest FFT size is 240, so starting with 480 the order should get randomized
            # Large FFTs are not randomized, Huge FFTs and All FFTs are

            Write-VerboseText('No FFT size provided in the error message, make an educated guess.')

            # Temporary(?) solution
            if ($maxFFTSize -le $FFTMinMaxValues['SSE']['LARGE']['Max']) {
                Write-VerboseText('The maximum FFT size is within the range where we can still make an educated guess about the failed FFT size')

                # There were no log entries yet
                if (!$allLogEntries -or $allLogEntries.Count -eq 0) {
                    Write-VerboseText('No results.txt exists yet, assuming the error happened on the first FFT size')
                    $lastRunFFT = $minFFTSize
                }

                # Get the last couple of rows and find the last passed FFT size
                else {
                    Write-VerboseText('Trying to find the last passed FFT sizes')

                    $lastFiveRows     = $allLogEntries | Select-Object -Last 5
                    $lastPassedFFTArr = @($lastFiveRows | Where-Object { $_ -like '*passed*' })  # This needs to be an array
                    $hasMatched       = ($lastPassedFFTArr | Select-Object -Last 1) -Match 'Self\-test (\d+)(K?) passed'

                    if ($hasMatched) {
                        if ($Matches[2] -eq 'K') {
                            $lastPassedFFT = [Int] $Matches[1] * 1024
                        }
                        else {
                            $lastPassedFFT = [Int] $Matches[1]
                        }
                    }

                    # No passed FFT was found, assume it's the first FFT size
                    if (!$lastPassedFFT) {
                        $lastRunFFT = $minFFTSize
                        Write-VerboseText('No passed FFT was found, assume it was the first FFT size: ' + ($lastRunFFT/1024))
                    }

                    # If the last passed FFT size is the max selected FFT size, start at the beginning
                    elseif ($lastPassedFFT -eq $maxFFTSize) {
                        $lastRunFFT = $minFFTSize
                        Write-VerboseText('Last passed FFT size found: ' + ($lastPassedFFT/1024))
                        Write-VerboseText('The last passed FFT size is the max selected FFT size, use the min FFT size: ' + ($lastRunFFT/1024))
                    }

                    # If the last passed FFT size is not the max size, check if the value doesn't show up at all in the FFT array
                    # In this case, we also assume that it successfully completed the max value and errored at the min FFT size
                    # Example: Smallest FFT max = 21, but the actual last size tested is 20K
                    elseif (!$FFTSizes[$cpuTestMode].Contains($lastPassedFFT)) {
                        $lastRunFFT = $minFFTSize
                        Write-VerboseText('Last passed FFT size found: ' + ($lastPassedFFT/1024))
                        Write-VerboseText('The last passed FFT size does not show up in the FFTSizes array, assume it''s the first FFT size: ' + ($lastRunFFT/1024))
                    }

                    # If it's not the max value and it does show up in the FFT array, select the next value
                    else {
                        $lastRunFFT = $FFTSizes[$cpuTestMode][$FFTSizes[$cpuTestMode].indexOf($lastPassedFFT)+1]
                        Write-VerboseText('Last passed FFT size found: ' + ($lastPassedFFT/1024))
                        Write-VerboseText('Last run FFT size assumed:  ' + ($lastRunFFT/1024))
                    }
                }

                # Educated guess
                if ($lastRunFFT) {
                    Write-ColorText('ERROR: The error likely happened at FFT size ' + ($lastRunFFT/1024) + 'K') Magenta
                    $errorLogMessage = 'The error likely happened at FFT size ' + ($lastRunFFT/1024) + 'K'
                }
                else {
                    Write-ColorText('ERROR: No additional FFT size information found in the results.txt') Magenta
                }

                Write-VerboseText('The last 5 entries in the results.txt:')

                $lastFiveRows | ForEach-Object -Begin {
                    $index = $allLogEntries.Count - 5
                } -Process {
                    Write-VerboseText('- [Line ' + $index + '] ' + $_)
                    $index++
                }

                Write-Text('')
            }

            # Only Smallest, Small and Large FFT presets follow the order, so no real FFT size fail detection is possible due to randomization of the order by Prime95
            else {
                $lastFiveRows     = $allLogEntries | Select-Object -Last 5
                $lastPassedFFTArr = @($lastFiveRows | Where-Object { $_ -like '*passed*' })
                $hasMatched       = ($lastPassedFFTArr | Select-Object -Last 1) -Match 'Self\-test (\d+)(K?) passed'

                if ($hasMatched) {
                    if ($Matches[2] -eq 'K') {
                        $lastPassedFFT = [Int] $Matches[1] * 1024
                    }
                    else {
                        $lastPassedFFT = [Int] $Matches[1]
                    }
                }

                if ($lastPassedFFT) {
                    Write-ColorText('ERROR: The last *passed* FFT size before the error was: ' + ($lastPassedFFT/1024) + 'K') Magenta
                    Write-ColorText('ERROR: Unfortunately FFT size fail detection only works for Smallest, Small or Large FFT sizes.') Magenta
                }
                else {
                    Write-ColorText('ERROR: No additional FFT size information found in the results.txt') Magenta
                }

                Write-VerboseText('The max FFT size was outside of the range where it still follows a numerical order')
                Write-VerboseText('The selected max FFT size:         ' + ($maxFFTSize/1024))
                Write-VerboseText('The limit for the numerical order: ' + ($FFTMinMaxValues['SSE']['LARGE']['Max']/1024))


                Write-VerboseText('The last 5 entries in the results.txt:')
                $lastFiveRows | ForEach-Object -Begin {
                    $index = $allLogEntries.Count - 5
                } -Process {
                    Write-VerboseText('- [Line ' + $index + '] ' + $_)
                    $index++
                }

                Write-Text('')
            }
        }
    }


    # Aida64
    elseif ($isAida64) {
        Write-VerboseText('The stress test program is Aida64, no detailed error detection available')
    }


    # y-cruncher with logging wrapper
    elseif ($isYCruncherWithLogging) {
        Write-VerboseText('The stress test program is y-cruncher with logging wrapper enabled')
        $lastRunTest = $null
        $lastErrorMessage = $null

        # The messages y-cruncher displays:
        # Exception Encountered: XYZ
        #
        # <ERROR MESSAGE>
        # <May have multiple lines>
        #
        #
        # Error(s) encountered on logical core X
        #
        # Failed  Test Speed <...>
        # Errors encountered. Stopping test...


        # Get the last 20 rows
        $lastTwentyRows = $allLogEntries | Select-Object -Last 20


        # Get the last test that was being run
        # We want the test that was started before the error message was thrown
        # The last entry may already be the next test that was started after the error happened

        # Look for the line the error message appears in
        $errorResults = $newLogEntries | Where-Object { $_.Line -Match '.*error\(s\).*' } | Select-Object -Last 1

        if ($errorResults) {
            $lastLineEntry  = $lastTwentyRows | Select-String -Pattern $errorResults.Line -SimpleMatch | Select-Object -First 1 | Select-Object Line, LineNumber
            $lastLineNumber = $lastLineEntry.LineNumber
        }
        else {
            $lastLineNumber = 20
        }


        # Reduce the Last Twenty Rows up to this line
        $lastRowsUpToError = $lastTwentyRows | Select-Object -First $lastLineNumber

        # Now get the last started test
        $allLatestTestArr = @($lastRowsUpToError | Where-Object { $_ -like '*Running *' })
        $hasMatched       = ($allLatestTestArr | Select-Object -Last 1) -Match 'Running ([a-z0-9]+):'

        if ($hasMatched) {
            $lastRunTest = $Matches[1]
        }

        if ($lastRunTest) {
            Write-ColorText('ERROR: The last test being started was: ' + $lastRunTest) Magenta
        }
        else {
            Write-ColorText('ERROR: No last test being started was found') Magenta
        }


        $exceptionEntry = $lastTwentyRows | Where-Object { $_ -Match 'Exception Encountered' } | Select-Object -Last 1
        $hasMatched = $($lastTwentyRows | Out-String) | Where-Object { $_ -Match "(?s)Exception Encountered.+`r`n`r`n(.+)`r`n`r`nError\(s\) encountered on logical core" }
        # Note: this needs double quotes to recognize the line breaks

        if ($hasMatched) {
            $lastErrorMessage = $Matches[1]
        }


        if ($exceptionEntry -or $lastErrorMessage) {
            Write-ColorText('ERROR: The error message:') Magenta

            if ($exceptionEntry) {
                Write-ColorText($exceptionEntry) Yellow
                $errorLogMessage = $exceptionEntry
            }

            if ($lastErrorMessage) {
                Write-ColorText($lastErrorMessage) Yellow
                $errorLogMessage = $lastErrorMessage
            }
        }
        else {
            Write-ColorText('ERROR: No error message was found') Magenta
        }


        Write-VerboseText('The last 20 entries of the output:')
        $lastTwentyRows | ForEach-Object -Begin {
            $index = $allLogEntries.Count - 20
        } -Process {
            Write-VerboseText('- [Line ' + $index + '] ' + $_)
            $index++
        }

        Write-Text('')
    }


    # y-cruncher without the wrapper
    elseif ($isYCruncher -or $isYCruncherOld) {
        Write-VerboseText('The stress test program is y-cruncher, no detailed error detection available')
    }


    # Linpack
    elseif ($isLinpack) {
        Write-VerboseText('The stress test program is Linpack, no additional error details available')

        # Look for the line the error message appears in
        $errorResults = $newLogEntries | Where-Object { $_.Line -Match '.*fail.*' } | Select-Object -Last 1

        # This is the same message as already displayed, so don't show it by default
        if ($errorResults) {
            Write-VerboseText('ERROR: The line with the error:')
            Write-VerboseText($errorResults.Line)
        }

        # Get the last 10 rows
        $lastTenRows = $allLogEntries | Select-Object -Last 10

        Write-VerboseText('The last 10 entries of the output:')
        $lastTenRows | ForEach-Object -Begin {
            $index = $allLogEntries.Count - 10
        } -Process {
            Write-VerboseText('- [Line ' + $index + '] ' + $_)
            $index++
        }
    }


    # Throw an error to let the caller know to close and possibily restart the stress test program
    # PROCESSMISSING
    # CALCULATIONERROR
    # CPULOAD
    # WHEAERROR
    if (!$errorType) {
        $errorType = 'UNKNOWN_STRESS_TEST_ERROR'
    }


    if ($canUseWindowsEventLog) {
        $coreString   = 'Core ' + $coreNumber + ' (CPU ' + $cpuNumberString + ')'
        $errorString  = 'There has been an error while running ' + $selectedStressTestProgram + '!'
        $errorString += [Environment]::NewLine + $errorLogMessage
        $errorString += [Environment]::NewLine + 'Error Type: ' + $errorType
        Write-AppEventLog -type 'core_error' -infoString1 $coreString -infoString2 $errorString
    }

    Add-ToErrorCollection $coreNumber $cpuNumberString $errorType $stressTestError $errorLogMessage

    $exception = New-Object System.ApplicationException -ArgumentList ('StressTestError', $errorType)
    throw $exception
}



<#
.DESCRIPTION
    Resolve the error that has been thrown by the Test-StressTestProgrammIsRunning function
.PARAMETER checkType
    [String] Which check to perform, TICK or LAST_ERROR_CHECK
.PARAMETER actualCoreNumber
    [Int] The core that is being tested
.PARAMETER coreTestOrderArray
    [System.Collections.ArrayList] The array of the cores being tested. We're modifying this if Automatic Test Mode is activated
.PARAMETER coreIndex
    [Ref] The current core index. We're modifying this if Automatic Test Mode is activated
.PARAMETER ExceptionObj
    The catch $_ object
.PARAMETER ErrorObj
    The catch $Error object
.OUTPUTS
    [Void]
#>
function Resolve-StressTestProgrammIsRunningError {
    param (
        [Parameter(Mandatory=$true)] [String] $checkType,
        [Parameter(Mandatory=$true)] [Int] $actualCoreNumber,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()] [System.Collections.ArrayList] $coreTestOrderArray,
        [Parameter(Mandatory=$true)] [Ref] $coreIndex,
        [Parameter(Mandatory=$true)] $ExceptionObj,
        [Parameter(Mandatory=$true)] $ErrorObj
    )

    Write-VerboseText('There has been some error in Test-StressTestProgrammIsRunning, checking (' + $checkType + ')')


    # Check if we're in Automatic Test Mode and need to increase the Curve Optimizer / voltage offset value
    $params = @{
        'mode'               = 'IN_LOOP'
        'actualCoreNumber'   = $actualCoreNumber
        'coreTestOrderArray' = $coreTestOrderArray
        'coreIndex'          = $coreIndex
    }

    Test-AutomaticTestModeIncrease @params


    # There is an error message
    if ($ExceptionObj.Exception -and $ExceptionObj.Exception.Message -eq 'StressTestError') {
        if ($checkType -eq 'LAST_ERROR_CHECK') {
            # Try to close the stress test program process if it is still running
            Write-VerboseText('Trying to close the stress test program to re-start it')

            # Set the flag to only stop the stress test program if possible
            Close-StressTestProgram $true
        }


        # If the stopOnError flag is set, stop at this point
        # But leave the stress test program open if possible
        # Only stop the testing process if we're not using Automatic Test Mode (fixes #110)
        if ($settings.General.stopOnError -and $useAutomaticTestMode) {
            Write-VerboseText('"stopOnError" is set, but Automatic Test Mode is enabled as well. Ignoring stopOnError')
        }

        if ($settings.General.stopOnError -and !$useAutomaticTestMode) {
            Write-Text('')
            Write-ColorText('Stopping the testing process because the "stopOnError" flag was set.') Yellow

            # Display the path to the log file
            if ($isPrime95) {
                Write-Text('')
                Write-ColorText('Prime95''s results log file can be found at:') Cyan
                Write-ColorText($stressTestLogFilePath) Cyan
            }
            elseif ($isYCruncherWithLogging) {
                Write-Text('')
                Write-ColorText('y-cruncher''s log file can be found at:') Cyan
                Write-ColorText($stressTestLogFilePath) Cyan
            }
            elseif ($isLinpack) {
                Write-Text('')
                Write-ColorText('Linpack''s log file can be found at:') Cyan
                Write-ColorText($stressTestLogFilePath) Cyan
            }

            # And the path to the CoreCycler the log file for this run
            Write-Text('')
            Write-ColorText('The path of the CoreCycler log file for this run is:') Cyan
            Write-ColorText($logFileFullPath) Cyan
            Write-Text('')

            Exit-Script
        }

        # y-cruncher can keep on running if the log wrapper is enabled and restartTestProgramForEachCore is not set
        # And the process is still running of course
        # And it is still using enough CPU power
        elseif ($isYCruncherWithLogging -and !$settings.General.restartTestProgramForEachCore -and $ExceptionObj.Exception.InnerException.Message -notmatch 'PROCESSMISSING|CPULOAD') {
            Write-VerboseText('Running y-cruncher with the log wrapper and restartTestProgramForEachCore disabled')
            Write-VerboseText('And the process is still there resp. the process is still using enough CPU power')
            Write-VerboseText('Continue to the next core')
        }

        # If it's not y-cruncher with logging, or the flag to restart is set, try to close and restart the stress test program process if it is still running
        else {
            Write-VerboseText('Trying to close the stress test program to re-start it')

            # Set the flag to only stop the stress test program if possible
            Close-StressTestProgram $true


            # Try to restart the stress test program and continue with the next core
            # Don't try to restart at this point if $settings.General.restartTestProgramForEachCore is set to 1
            # This will be taken care of in another routine
            if (!$settings.General.restartTestProgramForEachCore) {
                Write-VerboseText('restartTestProgramForEachCore is not set, restarting the test program right away')

                $timestamp = Get-Date -Format HH:mm:ss
                Write-Text($timestamp + ' - Trying to restart ' + $selectedStressTestProgram)

                # Start the stress test program again
                # Set the flag to only start the stress test program if possible
                Start-StressTestProgram $true
            }
        }
    }   # End: if ($ExceptionObj.Exception -and $ExceptionObj.Exception.Message -eq 'StressTestError')

    # Unknown error
    else {
        Write-ColorText('FATAL ERROR:') Red
        Write-ErrorText $ErrorObj
        Exit-WithFatalError -lineNumber (Get-ScriptLineNumber)
    }
}



<#
.DESCRIPTION
    Check if the Automatic Test Mode is active and if we should increase the Curve Optimizer / voltage offset value
.PARAMETER mode
    [String] Which mode, RESUME or IN_LOOP
.PARAMETER actualCoreNumber
    [Int] The core that is being tested
.PARAMETER coreTestOrderArray
    [System.Collections.ArrayList] The array of the cores being tested. We're modifying this if Automatic Test Mode is activated
.PARAMETER coreIndex
    [Ref] The current core index. We're modifying this if Automatic Test Mode is activated
#>
function Test-AutomaticTestModeIncrease {
    param (
        [Parameter(Mandatory=$true)] [String] $mode,
        [Parameter(Mandatory=$true)] [Int] $actualCoreNumber,
        [Parameter(Mandatory=$false)][AllowEmptyCollection()] [System.Collections.ArrayList] $coreTestOrderArray,
        [Parameter(Mandatory=$false)] $coreIndex
    )

    # If we're using Automatic Test Mode, increase the CO/voltage offset value
    if ($useAutomaticTestMode) {
        $incrementBy         = [Int] $settings['AutomaticTestMode']['incrementBy']
        $maxValue            = [Int] $settings['AutomaticTestMode']['maxValue']
        $oldValue            = $(if ($useCurveOptimizer) { [Int] $voltageCurrentValues[$actualCoreNumber] } elseif ($useIntelVoltageAdjustment) { [Int] $voltageCurrentValues[0] })
        $newValue            = [Int] [Math]::Max($oldValue, [Math]::Min($oldValue + $incrementBy, $maxValue))
        $autoModeDescription = ''
        $forCore             = ''
        $oldValueStr         = $oldValue
        $newValueStr         = $newValue
        $maxValueStr         = $maxValue
        $logType             = ''
        $reachedOrExceeded   = $(if ($oldValue -gt $maxValue) { 'exceeded' } else { 'reached' })

        if ($useCurveOptimizer) {
            $autoModeDescription = 'Curve Optimizer'
            $forCore             = ' for core ' + $actualCoreNumber
            $logType             = 'core_co_value'
        }
        elseif ($useIntelVoltageAdjustment) {
            $autoModeDescription = 'voltage offset'
            $oldValueStr         = $oldValue.ToString() + 'mv'
            $newValueStr         = $newValue.ToString() + 'mv'
            $maxValueStr         = $maxValue.ToString() + 'mv'
            $logType             = 'voltage_offset'
        }


        if ($mode -eq 'IN_LOOP') {
            Write-Text('')
            Write-ColorText('Automatic Test Mode is enabled') Yellow
        }

        Write-DebugText('Trying to increase the ' + $autoModeDescription + ' value' + $forCore)
        Write-DebugText('The new ' + $autoModeDescription + ' value: ' + $newValueStr + ' (old: ' + $oldValueStr + ')')


        # Temporary increasement, will be overwritten on each start of an iteration
        $Script:numCoresWithIncreasedVoltageValue++


        # Don't increase above the set maximum
        if ($oldValue -ge $maxValue) {
            Write-ColorText('Cannot increase the ' + $autoModeDescription + ' value for core ' + $actualCoreNumber + ' anymore! The maximum of ' + $maxValueStr + ' has been ' + $reachedOrExceeded) DarkYellow

            [Void] $Script:coresWithIncreasedVoltageValue.Add($actualCoreNumber)
            [Void] $Script:coresWithErrorAndMaxVoltageValue.Add($actualCoreNumber)

            if ($settings.General.skipCoreOnError) {
                Write-ColorText('This core will now be skipped in the following iterations') Yellow
            }
        }
        else {
            $Script:voltageCurrentValues[$actualCoreNumber] = $newValue
            [Void] $Script:coresWithIncreasedVoltageValue.Add($actualCoreNumber)

            # The current Intel implementation only works with a single voltage offset, not per core
            if ($useIntelVoltageAdjustment) {
                for ($i = 0; $i -lt $Script:voltageCurrentValues.Count; $i++) {
                    $Script:voltageCurrentValues[$i] = $newValue
                }
            }

            Write-ColorText('Modifying the ' + $autoModeDescription + ' value' + $forCore + ' from ' + $oldValueStr + ' to ' + $newValueStr) Yellow

            if ($newValue -eq $maxValue) {
                Write-ColorText('This is the maximum set ' + $autoModeDescription + ' value, there will be no further increases') Yellow
            }

            # Apply the new values
            Set-NewVoltageValues

            Write-AppEventLog -type $logType -infoString1 $actualCoreNumber -infoString2 $oldValue -infoString3 $newValue
        }


        # Make the loop repeat the same core if we're using Automatic Test Mode and the flag is set
        if ($mode -eq 'IN_LOOP' -and $settings.AutomaticTestMode.repeatCoreOnError -eq 1) {
            # Check if we haven't reached the maximum Curve Optimizer / voltage offset value for this core yet
            if ($oldValue -ge $maxValue) {
                Write-ColorText('The old ' + $autoModeDescription + ' value was already at the limit, will not repeat this core') Yellow
            }
            else {
                Write-ColorText('The flag to repeat the core is set, so repeating the test') Yellow
                Write-DebugText('Core test order array before: ' + $coreTestOrderArray)

                # Re-insert the core to the order array
                [Void] $coreTestOrderArray.Insert(0, $actualCoreNumber)

                Write-DebugText('Core test order array after:  ' + $coreTestOrderArray)

                # This sets the index to the one before this core, so it should fall on the same core again when we continue the loop
                # This variable was passed as a reference, so we need to access the .Value property
                $coreIndex.Value--
            }
        }


        Write-Text('')
    }
}



<#
.DESCRIPTION
    Get the (new) entries from a log file and store them in a global variable
.PARAMETER
    [Void]
.OUTPUTS
    [Void]
    Sets global variables:
    - $previousFileSize -> [Int] The current file size of the log file (to check if it was updated since then)
    - $lastFilePosition -> [Int] The position of the pointer within the log file
    - $lineCounter      -> [Int] On which line of the log file we are
    - $allLogEntries    -> [Array] All log entries
    - $newLogEntries    -> [Array] All new log entries
#>
function Get-NewLogfileEntries {
    $timestamp = Get-Date -Format HH:mm:ss
    Write-DebugText($timestamp + ' - Getting new log file entries')

    # Reset the newLogEntries array
    $Script:newLogEntries = [System.Collections.ArrayList]::new()

    # Try to get the log file (e.g. results.txt for Prime95)
    $resultFileHandle = Get-Item -Path $stressTestLogFilePath -ErrorAction Ignore

    # No file, no check
    if (!$resultFileHandle) {
        Write-DebugText('           The stress test log file doesn''t exist yet')
        return
    }

    # Only perform the check if the file size has increased
    # The size has increased, so something must have changed
    # It's either a new passed FFT entry, a [Timestamp], or an error
    if ($resultFileHandle.Length -le $previousFileSize) {
        Write-DebugText('           No file size change for the log file')
        return
    }

    # Store the file size of the log file
    $Script:previousFileSize = $resultFileHandle.Length

    Write-DebugText('           Getting new log entries starting at position ' + $lastFilePosition + ' / Line ' + $lineCounter)

    # Initialize the file stream
    # Note: This throws both PSUseConsistentIndentation: "Indentation not consistent" and
    #       PSUseConsistentWhitespace: "Use space after a comma" errors
    # I've found no way to disable or suppress this output ¯\_(ツ)_/¯
    # https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/using-scriptanalyzer?view=ps-modules#suppressing-rules
    #$fileStream = [System.IO.FileStream]::new(`
    #    $stressTestLogFilePath, `
    #    [System.IO.FileMode]::Open, `                                       # Open the file
    #    [System.IO.FileAccess]::Read, `                                     # Open the file only for reading
    #    [System.IO.FileShare]::ReadWrite + [System.IO.FileShare]::Delete`   # Allow other processes to read, write and delete the file
    #)
    $fileStream = [System.IO.FileStream]::new($stressTestLogFilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite + [System.IO.FileShare]::Delete)


    # Initialize the stream reader that accesses the file stream
    $streamReader = [System.IO.StreamReader]::new($fileStream)

    # We may need to reset the buffer due to a bug:
    # http://geekninja.blogspot.com/2007/07/streamreader-annoying-design-decisions.html
    $streamReader.DiscardBufferedData()

    # Set the pointer to the last file position (offset, beginning)
    [Void] $streamReader.BaseStream.Seek($lastFilePosition, [System.IO.SeekOrigin]::Begin)

    # Get all the new lines since the last check
    while ($streamReader.Peek() -gt -1) {
        $lineCounter++
        $line = $streamReader.ReadLine()
        $lineArr = @{
            'LineNumber' = $lineCounter
            'Line'       = $line
        }

        [Void] $Script:allLogEntries.Add($line)
        [Void] $Script:newLogEntries.Add($lineArr)
    }

    # Store the current position as the new last position for the next iteration
    $Script:lastFilePosition = $streamReader.BaseStream.Position    # This is the position of the entire read stream, so either 1024 or to the end of the file, whichever is less
    $Script:lineCounter      = $lineCounter

    # Close the file
    $streamReader.Close()

    Write-DebugText('           The new log file entries:')
    $newLogEntries | ForEach-Object {
        Write-DebugText('           - [Line ' + $_.LineNumber + '] ' + $_.Line)
    }

    Write-DebugText('           New file position: ' + $lastFilePosition + ' / Line ' + $lineCounter)
}



<#
.DESCRIPTION
    Set the affinity of the stress test program
    This sets the threads that are running the stress test to the desired affinity
    For two threads, on an Intel platform (14900KF) it seems that we explicitly need to set the affinity to one CPU for each thread, we cannot set it to both
    On an AMD 5900X it would work with simply setting the affinity to both CPUs
    This also works with CPUs that have more than 64 (logical) cores, where the regular .ProcessorAffinity property fails
    Note that this does not set the affinity of the main process, only for the threads
.PARAMETER CpuArray
    [Int[]] An array with the CPUs that the affinity should be set to
.OUTPUTS
    [Int64[]] An array with the affinities that should have been set
#>
function Set-StressTestProgramAffinities {
    param(
        [Parameter(Mandatory=$true)] [Int[]] $CpuArray
    )

    Write-DebugText('The number of Processor Groups:       ' + $numProcessorGroups)
    Write-DebugText('The number of CPUs in the last group: ' + $numCpusInLastProcessorGroup)


    # Get the Processor Group for the CPU(s) to test
    # Since we're only testing one physical core, i.e. not spreading across multiple physical core, we can assume
    # that the first entry of the CPU array is sufficient to test
    $groupId = [Math]::floor((($cpuArray[0]) / 64))

    Write-DebugText('The group ID of the CPU to set to: ' + $groupId)

    if ($groupId -gt $numProcessorGroups) {
        throw('Invalid groupId. Group ' + $groupId + ' is out of range. Maximum groupId is ' + $numProcessorGroups)
    }


    # Check how many CPUs are in the Processor Group of the new CPU
    # This is either the number of logical processors, or if more than 64 logical processors:
    # - 64 for any "full" group
    # - the remaining amount of cores if all the previous groups are already full
    if (($cpuArray[0] + 1) -gt ($numLogicalCores - $numCpusInLastProcessorGroup)) {
        $processorsInGroup = $numCpusInLastProcessorGroup
    }
    else {
        if ($numLogicalCores -gt 64) {
            $processorsInGroup = 64
        }
        else {
            $processorsInGroup = $numLogicalCores
        }
    }

    Write-DebugText('The number of processors in this group: ' + $processorsInGroup)


    # Modulo 64 the $cpuArray so the mask is correct for the given group
    # Since there are only max 64 CPUs per group, we need to find at which "point" of the group the new CPUs are
    # I.e. every Processor Group starts anew with CPU 0
    $cpuPerGroupArray = @(0) * $cpuArray.Count

    for ($i = 0; $i -lt $cpuArray.Count; $i++) {
        $cpuPerGroupArray[$i] = ($cpuArray[$i] % 64)
    }


    Write-DebugText('The IDs of the CPUs in its own group: ' + $cpuPerGroupArray)


    # Calculate the new affinities
    $affinities = @()


    # When both CPU cores should be used for a single thread, we actually need to sum the affinities
    if ($settings.General.assignBothVirtualCoresForSingleThread -and $settings.General.numberOfThreads -eq 1 -and $isHyperthreadingEnabled) {
        $affinity = [UInt64] 0
        $cpuNumbersArray = @()

        for ($i = 0; $i -lt $cpuPerGroupArray.Count; $i++) {
            $cpuNumber = $cpuPerGroupArray[$i]
            $cpuNumbersArray += $cpuNumber
            $affinity += [UInt64] [Math]::Pow(2, $cpuNumber)    # CPU 63 would overflow signed [Int64]
        }

        Write-DebugText('Calculated the group specific affinity as ' + $affinity + ' [CPUs ' + ($cpuNumbersArray -Join ' and ') + ', Group ' + $groupId + ']')

        $affinities += $affinity
    }


    # Instead, when regularly using one or two threads, calculate the affinity for each core and thread separately
    else {
        for ($i = 0; $i -lt $cpuPerGroupArray.Count; $i++) {
            $cpuNumber = $cpuPerGroupArray[$i]
            $affinity  = [UInt64] [Math]::Pow(2, $cpuNumber)    # CPU 63 would overflow signed [Int64]
            $affinities += $affinity

            Write-DebugText('Calculated the group specific affinity as ' + $affinity + ' [CPU ' + $cpuNumber + ', Group ' + $groupId + ']')
        }
    }


    Write-DebugText('All calculated group specific affinities: ' + ($affinities -Join ' & '))


    # Go through the stress test threads that we identified earlier, and evenly distribute the CPU affinities across the threads
    # (e.g. just 1, or 1 + 1, or 2 + 2)
    # Prime95 and y-cruncher use 1/2 threads, Aida64 uses 4 threads
    # And let's hope that these threads never change while the test is running!
    $numberOfStressTestThreads = $stressTestThreads.Count

    Write-DebugText('Found number of stress test threads: ' + $numberOfStressTestThreads)
    Write-DebugText('The original affinities array: ' + ($affinities -Join ', '))

    # Expand the affinities array to the number of threads
    if ($numberOfStressTestThreads -gt 2 -and $affinities.Count -gt 1) {
        $originalAffinities = $affinities
        $affinities = @()
        $cutOff = [Math]::Ceiling($numberOfStressTestThreads / 2)

        for ($i = 0; $i -lt $numberOfStressTestThreads; $i++) {
            $affinities += $(if ($i -lt $cutOff) { $originalAffinities[0] } else { $originalAffinities[1] })
        }
    }

    Write-DebugText('The final affinities array:    ' + ($affinities -Join ', '))

    # Now set the affinities
    for ($i = 0; $i -lt $numberOfStressTestThreads; $i++) {
        Write-DebugText('Processing stress test thread number ' + $i)

        $stressTestThread = $stressTestThreads[$i]

        Write-VerboseText('Trying to set the affinity for thread ID: ' + $stressTestThread.Id)


        # If there's more than one affinity, use the one that matches the thread number
        # Otherwise use the same one
        $affinity = $(if ($affinities.Count -ge ($i+1) -and $affinities[$i]) { $affinities[$i] } else { $affinities[0] })

        Write-VerboseText('- Processor Group: ' + $groupId + ' | Affinity: ' + $affinity)


        try {
            Set-ThreadGroupAffinity -ThreadId $stressTestThread.Id -Affinity $affinity -Group $groupId
            Write-DebugText('Successfully set the group affinity for thread ID ' + $stressTestThread.Id + ' to ' + $affinity + ' within group ' + $groupId)
        }
        catch {
            $errorMessage  = 'Failed to set the group affinity for thread ID ' + $stressTestThread.Id + '.'
            $errorMessage += [Environment]::NewLine + 'Error: ' + $_

            Exit-WithFatalError -text $errorMessage
        }
    }

    return $affinities
}



<#
.DESCRIPTION
    Convert a CPU array into a binary affinity mask string
.PARAMETER CpuArray
    [Int[]] Array with the CPU IDs *WITHIN ITS GROUP*
.PARAMETER ProcessorCount
    [Int] How many processors are in this group (i.e. how many characters the string will have)
.OUTPUTS
    [String] The bitmask string, with the lowest CPU to the right, the highest to the left
#>
function Convert-CpuArrayToAffinityMaskString {
    param (
        [Parameter(Mandatory=$true)] [Int[]] $CpuArray,
        [Parameter(Mandatory=$true)] [Int] $ProcessorCount
    )

    $affinityMaskArray = @(0) * $ProcessorCount

    foreach ($cpu in $CpuArray) {
        if ($cpu -ge $ProcessorCount) {
            throw('Invalid CPU value: ' + $cpu + '. CPU values must be less than the ProcessorCount (' + $ProcessorCount + ').')
        }

        # Right to left
        $affinityMaskArray[$ProcessorCount - 1 - $cpu] = 1
    }

    return -Join ($affinityMaskArray | ForEach-Object { $_.ToString() })
}



<#
.DESCRIPTION
    Get the affinity value for a CPU array
.PARAMETER CpuArray
    [Int[]] Array with the CPU IDs *WITHIN ITS GROUP*
.PARAMETER ProcessorCount
    [Int] How many processors are in this group (i.e. how many characters the string will have)
.OUTPUTS
    [Int64] The affinity value. Can be negative for core 63 (and combinations with core 63)
#>
function Get-AffinityValue {
    param (
        [Parameter(Mandatory=$true)] [Int[]] $CpuArray
    )

    # We're generating the bit mask for the CPU array, which we then convert to an integer
    # This can actually also retun a negative value, which seems to be fine (and expected)

    # Get the number of processors in the processor group for the CPU array
    # This is either the number of logical processors, or if more than 64 logical processors:
    # - 64 for any "full" group
    # - the remaining amount of cores if all the previous groups are already full
    if (($CpuArray[0] + 1) -gt ($Script:numLogicalCores - $Script:numCpusInLastProcessorGroup)) {
        $processorsInGroup = $Script:numCpusInLastProcessorGroup
    }
    else {
        if ($Script:hasMoreThan64Cores) {
            $processorsInGroup = 64
        }
        else {
            $processorsInGroup = $Script:numLogicalCores
        }
    }

    Write-DebugText('Get-AffinityValue for CPUs ' + (($cpuNumbersArray | Sort-Object) -Join ' and '))
    Write-DebugText('Number of processors in the group of the CPUs: ' + $processorsInGroup)

    $affinityBitMaskString = Convert-CpuArrayToAffinityMaskString -CpuArray $CpuArray -ProcessorCount $processorsInGroup

    Write-DebugText('The affinity mask string: ' + $affinityBitMaskString)

    $affinityValue = [System.Convert]::ToInt64($affinityBitMaskString, 2)

    Write-DebugText('The affinity value:       ' + $affinityValue)

    return $affinityValue
}



<#
.DESCRIPTION
    Get the Processor Group affinities for a thread
.PARAMETER threadId
    [Int] The ID of the thread
.OUTPUTS
    [Object] The group affinity object
             [UInt64] Mask A bitmap that specifies the affinity for zero or more processors within the specified group
             [Int] Group The processor group number
             [Array] Reserved Currently unused
#>
function Get-ThreadGroupAffinity {
    param (
        [Parameter(Mandatory=$true)] [Int] $threadId
    )

    # Open the thread with the necessary access rights
    $threadHandle = [ThreadHandler]::OpenThread([ThreadHandler]::THREAD_QUERY_INFORMATION, $false, $threadId)

    if ($threadHandle -eq [IntPtr]::Zero) {
        throw('Failed to open thread with ID ' + $threadId)
    }

    try {
        # Retrieve the group affinity for the specified thread
        $groupAffinity = New-Object ThreadHandler+GROUP_AFFINITY
        $result = [ThreadHandler]::GetThreadGroupAffinity($threadHandle, [ref]$groupAffinity)
        $errorCode = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()

        if (!$result) {
            if ($errorCode -gt 0) {
                Write-DebugText('Error Code: ' + $errorCode + ' - Line: ' + (Get-ScriptLineNumber))
                $errorResult = Get-DotNetErrorMessage $errorCode

                throw('Failed to get thread group affinity.' + [Environment]::NewLine + 'Error code: ' + $errorResult.errorCode + '. Error message: ' + $errorResult.errorMessage)
            }

            throw('Failed to get thread group affinity. No error code was provided.')
        }

        return $groupAffinity
    }
    finally {
        [Void] [ThreadHandler]::CloseHandle($threadHandle)
    }
}



<#
.DESCRIPTION
    Set the affinity of a thread, taking into account the Processor Group as well
    This enables us to set the affinity for systems with more than 64 logical processors
.PARAMETER ThreadId
    [Int] The ID of the thread to change
.PARAMETER Affinity
    [UInt64] The affinity value. This value is a 64bit value and specific to each Processor Group
             (i.e. two groups can have the same affinity value, but they refer to different "overall" cores)
.PARAMETER Group
    [Int] The Processor Group in which the cores are located in, that the Affinity value will refer to
.OUTPUTS
    [Void]
#>
function Set-ThreadGroupAffinity {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'threadFound')]     # This fixes the incorrect "assigned but never used" detection of the $threadFound variable
    param (
        [Parameter(Mandatory=$true)] [Int] $ThreadId,
        [Parameter(Mandatory=$true)] [UInt64] $Affinity,
        [Parameter(Mandatory=$true)] [Int] $Group
    )

    Write-DebugText('Getting the thread handle for thread ID: ' + $ThreadId)

    # Open the thread with the necessary access rights
    $threadHandle = [ThreadHandler]::OpenThread([ThreadHandler]::THREAD_SET_INFORMATION -bor [ThreadHandler]::THREAD_QUERY_INFORMATION, $false, $ThreadId)

    Write-DebugText('The returned thread handle: ' + $threadHandle)

    # The thread doesn't seem to exist anymore
    if ($threadHandle -eq [IntPtr]::Zero) {
        Write-VerboseText('We didn''t receive a thread handle for the thread ID ' + $ThreadId + '!')
        Write-DebugText('A list of all the threads of the stress test process:')

        $threadFound = $false
        $stressTestProcess.Threads | ForEach-Object {
            Write-DebugText($_ | Format-List | Out-String)

            if ($_.Id -eq $ThreadId) {
                $threadFound = $true
            }
        }

        $errorMessage = 'Failed to open thread with ID ' + $ThreadId + '!'

        if ($threadFound) {
            $errorMessage += ' The thread was found, but we couldn''t get a handle for it!'
        }
        else {
            $errorMessage += ' It doesn''t seem to exist anymore!'
            $errorMessage += [Environment]::NewLine
            $errorMessage += 'Maybe the stress test threw an error or it stopped.'
        }

        throw($errorMessage)
    }

    try {
        # Set the affinity and the Processor Group for the specified thread
        $groupAffinity = New-Object ThreadHandler+GROUP_AFFINITY
        $groupAffinity.Mask = $Affinity
        $groupAffinity.Group = [Convert]::ToUInt16($Group)
        $groupAffinity.Reserved = @(0, 0, 0)

        $result = [ThreadHandler]::SetThreadGroupAffinity($threadHandle, [ref]$groupAffinity, [IntPtr]::Zero)
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()

        if (!$result) {
            if ($errorCode -gt 0) {
                Write-DebugText('Error Code: ' + $errorCode + ' - Line: ' + (Get-ScriptLineNumber))
                $errorResult = Get-DotNetErrorMessage $errorCode

                throw('Failed to set thread group affinity.' + [Environment]::NewLine + 'Error code: ' + $errorResult.errorCode + '. Error message: ' + $errorResult.errorMessage)
            }

            throw('Failed to set thread group affinity. No error code was provided.')
        }
    }
    finally {
        [Void] [ThreadHandler]::CloseHandle($threadHandle)
    }
}



<#
.DESCRIPTION
    Get the affinites of the stress test program threads
.OUTPUTS
    [Int64[]] The affinities of the threads that are running the stress test
#>
function Get-StressTestProgramAffinities {
    $affinities = @()

    foreach ($thread in $stressTestThreads) {
        $affinityOfThread = Get-ThreadGroupAffinity -ThreadId $thread.Id
        $affinities += $affinityOfThread.Mask
    }


    return $affinities
}



<#
.DESCRIPTION
    Try to save any cached file data to the disk
    Uses Write-VolumeCache to flush the disk write cache
    It may not work for drive internal caches though
.OUTPUTS
    [Void]
#>
function Save-CachedDataToDisk {
    Write-DebugText('           Trying to flush the write cache to disk for drive: ' + $scriptDriveLetter)

    # Start it as a job to not block the script execution
    Write-VolumeCache -AsJob -DriveLetter $scriptDriveLetter -ErrorAction Ignore | Out-Null
}



<#
.DESCRIPTION
    Check if we the Windows Event Log service is available
.OUTPUTS
    [Bool] $true if it is running
#>
function Test-EventLogService {
    # The service itself may not be available
    try {
        $eventLogService = Get-Service 'EventLog'

        if (!($eventLogService | Get-Member Status) -or $eventLogService.Status -ne 'Running' ) {
            Write-VerboseText('The Event Log service is not available')
            $Script:eventLogAvailable = $false
            $Script:canUseWindowsEventLog = $false
            return $false
        }
    }
    catch {
        Write-VerboseText('Error while checking for the Event Log service, it is not available')
        $Script:eventLogAvailable = $false
        $Script:canUseWindowsEventLog = $false
        return $false
    }

    return $true
}



<#
.DESCRIPTION
    Check if we need to add a Windows Event Log "Source"
    This is required to be able to use the Windows Event Log
    Adding this Source requires admin rights, so we've outsourced the actual code to do so into
    /helpers/add-eventlog-source.ps1
.OUTPUTS
    [Void]
#>
function Add-AppEventLogSource {
    Write-VerboseText('Checking if we can and need to add the Event Log Source for CoreCycler')

    $askToAddEventLog = $false
    $startedNewAdminProcess = $null


    try {
        if ([System.Diagnostics.EventLog]::SourceExists('CoreCycler') -eq $false) {
            Write-DebugText('The Event Log Source "CoreCycler" does not exist yet (#1)')
            $askToAddEventLog = $true
        }

        # All good, continue
        else {
            Write-DebugText('The Event Log Source "CoreCycler" already exist, nothing to do')
            $Script:canUseWindowsEventLog = $true
            return
        }
    }

    # Failed attempts are probably due to not having administrator rights
    # But we only care about the "Application" Event Log, which shouldn't need admin rights, and it is *very* unlikely
    # that "CoreCycler" is used as a source there, so just parse the exception message to determine our next steps
    # It will not throw an exeption if the source was found in "Application"
    catch [System.Security.SecurityException] {
        # We assume that every SecurityException is due to not being able to search the "Security" part of the Event Log
        Write-DebugText('Expected exception found, the Event Log Source "CoreCycler" does not exist yet (#2)')
        $askToAddEventLog = $true
    }

    # Any other exception should be something else, so throw it
    catch {
        Write-DebugText('There was an unexpected exception when trying to get the Event Log Source!')
        throw $_
    }


    if ($askToAddEventLog) {
        try {
            $pathToAddSourceScript = '"' + $helpersPathAbsolute + 'add-eventlog-source.ps1"'

            # We need admin rights for this, and we're probably not running as as an admin
            # If we are an admin, we can just add the Source
            if ($areWeAdmin) {
                $startedNewAdminProcess = Start-Process 'powershell.exe' -ArgumentList '-ExecutionPolicy Bypass', '-File', $pathToAddSourceScript, 'isAdmin' -PassThru -Wait -NoNewWindow
            }

            # But if not, we will need to open a new window with admin rights
            else {
                Write-Text('')
                Write-Text('')
                Write-ColorText('┌─────────────────────────────────┤ IMPORTANT ├────────────────────────────────┐') Yellow DarkRed
                Write-ColorText('│ ' + 'Using the Windows Event Log has been enabled, but to be able to do so, we'.PadRight(76, ' ') + ' │') Yellow DarkRed
                Write-ColorText('│ ' + 'need to add a so called "Source" to the Event Log first.'.PadRight(76, ' ') + ' │') Yellow DarkRed
                Write-ColorText('│ ' + 'This has to be done only once (i.e. this time), so after it has been added,'.PadRight(76, ' ') + ' │') Yellow DarkRed
                Write-ColorText('│ ' + 'this message will no longer appear.'.PadRight(76, ' ') + ' │') Yellow DarkRed
                Write-ColorText('│ ' + 'To add this "Source", administrator rights are required, so we''re trying to'.PadRight(76, ' ') + ' │') Yellow DarkRed
                Write-ColorText('│ ' + 'open a new window now, which asks for elevation.'.PadRight(76, ' ') + ' │') Yellow DarkRed
                Write-ColorText('│ ' + ''.PadRight(76, ' ') + ' │') Yellow DarkRed
                Write-ColorText('│ ' + '- Choosing "Yes" will open a new window and ask for administrator privileges'.PadRight(76, ' ') + ' │') Yellow DarkRed
                Write-ColorText('│ ' + '- Choosing "No" will continue with the script without using the Event Log'.PadRight(76, ' ') + ' │') Yellow DarkRed
                Write-ColorText('│ ' + ''.PadRight(76, ' ') + ' │') Yellow DarkRed
                Write-ColorText('│ ' + 'You can disable this functionality by setting "useWindowsEventLog = 0" in'.PadRight(76, ' ') + ' │') Yellow DarkRed
                Write-ColorText('│ ' + 'the [Logging] section of the config.ini file.'.PadRight(76, ' ') + ' │') Yellow DarkRed
                Write-ColorText('│ ' + ''.PadRight(76, ' ') + ' │') Yellow DarkRed
                Write-ColorText('│ ' + 'If you choose to allow the creation of these Event Log entries, they will'.PadRight(76, ' ') + ' │') Yellow DarkRed
                Write-ColorText('│ ' + 'appear in the Windows Logs/Application section of the Event Viewer.'.PadRight(76, ' ') + ' │') Yellow DarkRed
                Write-ColorText('└──────────────────────────────────────────────────────────────────────────────┘') Yellow DarkRed


                $title    = 'Please confirm to add the new Windows Event Log Source'
                $question = [Environment]::NewLine + 'Proceed?' + [Environment]::NewLine + ' '
                $choices  = @(
                    [System.Management.Automation.Host.ChoiceDescription]::new('&Yes', 'Add the Event Log Source. Requires Administrator Privileges')
                    [System.Management.Automation.Host.ChoiceDescription]::new('&No', 'Continue without adding the Event Log Source. No Event Log entries will be available')
                )
                $decision = $Host.UI.PromptForChoice($title, $question, $choices, 0)

                if ($decision -eq 0) {
                    Write-Host 'Trying to open a new window as admin'
                    $startedNewAdminProcess = Start-Process 'powershell.exe' -ArgumentList '-ExecutionPolicy Bypass', '-File', $pathToAddSourceScript -Verb 'runAs' -PassThru -Wait
                }
                else {
                    Write-Text('Ok, not adding the Window Event Log Source')
                    Write-Text('Entries in the Event Log will not be available')
                }
            }
        }
        catch {
            Write-ColorText('FATAL ERROR: Could not set the Event Log Source "CoreCycler"!') Red
            Write-ErrorText $_
            Exit-WithFatalError
        }

        # Check if we added the Source or not
        if ($startedNewAdminProcess) {
            if ($startedNewAdminProcess.ExitCode -ne 0) {
                Write-ColorText('FATAL ERROR: Could not set the Event Log Source "CoreCycler"!') Red
                Exit-WithFatalError
            }
            else {
                Write-Text('Successfully added the Event Log Source')
                Write-Text('Entries will now be written to the "Windows Logs"/"Application" section')
                $Script:canUseWindowsEventLog = $true
            }
        }
    }
}



<#
.DESCRIPTION
    Writes an entry to the Windows Event Log
.PARAMETER type
    [String] Which Event Log type to add (script_started, script_finished, script_terminated, script_error, core_started, core_finished, core_error, core_whea, core_co_value, voltage_offset)
.PARAMETER infoString1
    [String] A string with additional information
.PARAMETER infoString2
    [String] A string with with more additional information
.PARAMETER infoString3
    [String] A string with with more additional information
.OUTPUTS
    [Void]
#>
function Write-AppEventLog {
    param(
        [Parameter(Mandatory=$true)] [String] $type,
        [Parameter(Mandatory=$false)] [String] $infoString1,
        [Parameter(Mandatory=$false)] [String] $infoString2,
        [Parameter(Mandatory=$false)] [String] $infoString3
    )

    Write-DebugText('Adding Event Log entry: ' + $type)

    $wheaTypes = @{
        'script_started'    = @{
            'eventId'   = 100
            'entryType' = 'Information'
            'message'   = [String]::Format('CoreCycler has started{0}{1}', [Environment]::NewLine*2, $infoString1)
        }
        'script_finished'   = @{
            'eventId'   = 200
            'entryType' = 'Information'
            'message'   = 'CoreCycler has finished all iterations'
        }
        'script_terminated' = @{
            'eventId'   = 300
            'entryType' = 'Information'
            'message'   = [String]::Format('CoreCycler was terminated{0}{1}{2}{3}', [Environment]::NewLine*2, $infoString1, [Environment]::NewLine*2, $infoString2)
        }
        'script_error'      = @{
            'eventId'   = 999
            'entryType' = 'Error'
            'message'   = [String]::Format('There has been a general error in the script!{0}{1}', [Environment]::NewLine*2, $infoString1)
        }
        'core_started'      = @{
            'eventId'   = 1000
            'entryType' = 'Information'
            'message'   = [String]::Format('Started testing Core {0}', $infoString1)
        }
        'core_finished'     = @{
            'eventId'   = 2000
            'entryType' = 'Information'
            'message'   = [String]::Format('Finished testing Core {0}{1}{2}', $infoString1, [Environment]::NewLine*2, $infoString2)
        }
        'core_co_value'     = @{
            'eventId'   = 5000
            'entryType' = 'Information'
            'message'   = [String]::Format('Increasing Curve Optimizer value for core {0} from {1} to {2}', $infoString1, $infoString2, $infoString3)
        }
        'voltage_offset'    = @{
            'eventId'   = 5000
            'entryType' = 'Information'
            'message'   = [String]::Format('Increasing voltage offset value from {1} to {2} (error on core {0})', $infoString1, $infoString2, $infoString3)
        }
        'core_whea'         = @{
            'eventId'   = 8888
            'entryType' = 'Warning'
            'message'   = [String]::Format('There has been a WHEA error while running the test for Core {0}.{1}The WHEA error:{2}{3}', $infoString1, [Environment]::NewLine, [Environment]::NewLine, $infoString2)
        }
        'core_error'        = @{
            'eventId'   = 9999
            'entryType' = 'Error'
            'message'   = [String]::Format('Error on Core {0}!{1}{2}', $infoString1, [Environment]::NewLine*2, $infoString2)
        }
    }

    if (!$wheaTypes[$type]) {
        Write-DebugText('The provided type "' + $type + '" doesn''t exist for the Event Log Writer')
        return
    }

    $type        = $type.ToLowerInvariant()
    $eventSource = 'CoreCycler'     # This Source needs to be available, and can only be set with admin rights
    $eventId     = $wheaTypes[$type]['eventId']
    $entryType   = $wheaTypes[$type]['entryType']
    $message     = $wheaTypes[$type]['message']

    try {
        Write-DebugText('Adding the Windows Event Log entry:')

        if ($message) {
            $messageArray = @($message -Split '\r?\n')

            foreach ($line in $messageArray) {
                Write-DebugText('[EVENTLOG] ' + $line)
            }
        }

        [System.Diagnostics.EventLog]::WriteEntry($eventSource, $message, $entryType, $eventId, 0)
    }
    catch {
        Write-DebugText('Couldn''t add the Event Log entry!')
        Write-DebugText($_)
    }
}



<#
.DESCRIPTION
    Get the last WHEA error, if any
.OUTPUTS
    [Object] The last WHEA error object, or a default object
#>
function Get-LastWheaError {
    $defaultWheaObj = @{
        'TimeCreated' = -1
        'RecordId'    = -1
        'Message'     = 'No WHEA errors found'
    }

    $filterHashTable = @{
        'ProviderName' = 'Microsoft-Windows-WHEA-Logger'
        'Level'        = @(2, 3)
    }

    # TODO: Maybe use the coreStartTime filter here, to get only new entries since the core start time?
    $lastWheaError = Get-WinEvent -FilterHashtable $filterHashTable -MaxEvents 1 -ErrorAction Ignore

    if ($lastWheaError) {
        return $lastWheaError
    }

    return $defaultWheaObj
}



<#
.DESCRIPTION
    Compare two WHEA errors, if they are the same or if there's a new one
.PARAMETER coreStartDate
    [DateTime] The start time of the most recent core test
.OUTPUTS
    Writes text if thers a new one since our last test
#>
function Compare-WheaErrorEntries {
    param(
        $coreStartDate
    )

    $timestamp = Get-Date -Format HH:mm:ss
    Write-DebugText($timestamp + ' - Looking for new WHEA errors')

    $lastWheaError = Get-LastWheaError

    Write-DebugText('           Core Start Date:        ' + $coreStartDate.ToString())
    Write-DebugText('           Stored WHEA Error Date: ' + $storedWheaError.TimeCreated.ToString())
    Write-DebugText('           Last WHEA Error Date:   ' + $lastWheaError.TimeCreated.ToString())

    if ($lastWheaError.RecordId -eq $storedWheaError.RecordId) {
        Write-VerboseText('           No new WHEA error')
        return
    }

    Write-VerboseText('           New WHEA error found!')

    # Store this new error
    if ($lastWheaError.RecordId -ne $storedWheaError.RecordId) {
        $Script:storedWheaError = $lastWheaError
    }

    # Check if we have a new WHEA error that has occurred after the current core test has started
    if ($lastWheaError.TimeCreated -gt 0 -and $lastWheaError.TimeCreated -gt $coreStartDate) {
        return $lastWheaError
    }
}



<#
.DESCRIPTION
    Parse a WHEA error and get the APIC ID that fired it
.PARAMETER wheaErrorEntry
    [Object] The WHEA error object
.OUTPUTS
    [Int] The core that is included in the report
#>
function Convert-WheaMessageToApicId {
    param(
        [Parameter(Mandatory=$true)] $wheaErrorEntry
    )

    <#
    A WHEA Warning message:
    A corrected hardware error has occurred.

    Reported by component: Processor Core
    Error Source: Corrected Machine Check
    Error Type: Internal parity error
    Processor APIC ID: 32

    The details view of this entry contains further information.


    The details view:
     [0] = ErrorSource     = 1
     [1] = ApicId          = 32
     [2] = MCABank         = 0
     [3] = MciStat         = 0x8000004000040005
     [4] = MciAddr         = 0x0
     [5] = MciMisc         = 0x0
     [6] = ErrorType       = 12
     [7] = TransactionType = 256
     [8] = Participation   = 256
     [9] = RequestType     = 256
    [10] = MemorIO         = 256
    [11] = MemHierarchyLvl = 256
    [12] = Timeout         = 256
    [13] = OperationType   = 256
    [14] = Channel         = 256
    [15] = Length          = 1003
    [16] = RawData         = ...
    #>

    <#
    Another WHEA message, with ID 1:
    A fatal hardware error has occurred. A record describing the condition is contained in the data section of this event.

    Has basically no details, just the Length and RawData
    #>

    Write-DebugText('Parsing the WHEA entry')
    Write-DebugText('Id: ' + $wheaErrorEntry.Id)

    # 18 = Fatal Hardware Error
    # 19 = Correctable Hardware Error
    if ($wheaErrorEntry.Id -ne 18 -and $wheaErrorEntry.Id -ne 19) {
        return -1
    }

    if (!($wheaErrorEntry | Get-Member Properties)) {
        return -2
    }

    # The apicId represents the logical core, i.e. the virtual CPU
    $apicId = [Int] $wheaErrorEntry.Properties[1].Value

    return $apicId
}



<#
.DESCRIPTION
    Parse a WHEA error and get the core that fired it
.PARAMETER wheaErrorEntry
    [Object] The WHEA error object
.OUTPUTS
    [Int] The core that is included in the report
#>
function Convert-WheaMessageToCoreId {
    param(
        [Parameter(Mandatory=$true)] $wheaErrorEntry
    )

    <#
    On Ryzen CPUs, the Apic ID equals the virtual CPU if on one CCD / CCX or two full CCDs / CCXs:
    Core 0: 0/1 - Core 1: 2/3 - Core 2: 4/5 - Core 3: 6/7 - Core 4: 8/9 - Core 5: 10/11 - Core 6: 12/13 - Core 7: 14/15 - Core 8: 16/17 - Core 9: 18/19 - Core 10: 20/21 - Core 11: 22/23 - Core 12: 24/25 - Core 13: 26/27 - Core 14: 28/29 - Core 15: 30/31
    ApicId -> Core: core = floor(ApicId / 2)

    If the chip has two CCDs that are not fully populated (e.g. a Ryzen 5900X), the Ids have a "gap":
    Core 0: 0/1 - Core 1: 2/3 - Core 2: 4/5 - Core 3: 6/7 - Core 4: 8/9 - Core 5: 10/11 - Core 6: 16/17 - Core 7: 18/19 - Core 8: 20/21 - Core 9: 22/23 - Core 10: 24/25 - Core 11: 26/27

    For Intel, this is different:
    Core 0: 0/1 - Core 1: 8/9 - Core 2: 16/17 - Core 3: 24/25 - Core 4: 32/33 - Core 5: 40/41 - Core 6: 48/19 - Core 7: 56/57 - Core 8: 64 - Core 9: 66 - Core 10: 68 - Core 11: 70 - Core 12: 72 - Core 13: 74 - Core 14: 76 - Core 15: 78 - Core 16: 80 - Core 17: 82 - Core 18: 84 - Core 19: 86 - Core 20: 88 - Core 21: 90 - Core 22: 92 - Core 23: 94

    For cores with Hyperthreading (P-Core), each core seems to be 8 bit wide
    For cores without Hyperthreading (E-Core), each core seems to be 2 bit wide
    x2apic mode?

    Anyway, we're now using the APICID tool to get the actual IDs
    #>

    <#
    Possible different sources from WHEA errors:
    https://www.overclock.net/threads/official-amd-ryzen-ddr4-24-7-memory-stability-thread.1628751/post-28817021
    ErrorSourceId: 0 Type: WheaErrSrcTypeDeviceDriver = 0x10, Device Driver Error Source
    ErrorSourceId: 1 Type: WheaErrSrcTypeMCE          = 0x00, Machine Check Exception
    ErrorSourceId: 2 Type: WheaErrSrcTypeCMC          = 0x01, Corrected Machine Check
    ErrorSourceId: 3 Type: WheaErrSrcTypeNMI          = 0x03, Non-Maskable Interrupt
    ErrorSourceId: 4 Type: WheaErrSrcTypeBOOT         = 0x07, BOOT Error Source
    #>

    # The apicId represents the logical core, i.e. the virtual CPU
    $apicId = Convert-WheaMessageToApicId $wheaErrorEntry

    # Convert this to a physical core
    $coreId = [Int] $coresInfo['apicIdToCore'][$apicId]

    return $coreId
}



<#
.DESCRIPTION
    Get the core information, including APIC IDs
    Uses APICID.exe
.OUTPUTS
    [Void] But sets the global $coresInfo lookup table
#>
function Get-ProcessorCoresInformation {
    $apicIdToCpu   = @{}
    $cpuToApicId   = @{}
    $cpuToCore     = @{}
    $apicIdToCore  = @{}
    $coreToApicId  = @{}
    $coreToCpus    = @{}
    $coreSmtStatus = @{}

    $apicIdProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
    $apicIdProcessInfo.FileName = $apicIdTool
    $apicIdProcessInfo.RedirectStandardError = $true
    $apicIdProcessInfo.RedirectStandardOutput = $true
    $apicIdProcessInfo.UseShellExecute = $false

    $apicIdProcess = New-Object System.Diagnostics.Process
    $apicIdProcess.StartInfo = $apicIdProcessInfo
    $null = $apicIdProcess.Start()


    $stdOut = $apicIdProcess.StandardOutput.ReadToEnd()
    $stdErr = $apicIdProcess.StandardError.ReadToEnd()
    $apicIdProcess.WaitForExit()
    $exitCode = $apicIdProcess.ExitCode


    if ($exitCode -ne 0) {
        $msg = 'APICID: Program terminated unexpectedly. Exit Code: ' + $exitCode

        if ($stdErr) {
            $msg += [Environment]::NewLine + $stdErr
        }

        if ($stdOut) {
            $msg += [Environment]::NewLine + $stdOut
        }

        throw($msg)
    }

    if ($stdErr -and $stdErr.Length -gt 0) {
        throw('APICID: Error message returned: ' + $stdErr)
    }

    if (!$stdOut -or $stdOut -eq '') {
        throw('APICID: Returned value was empty')
    }

    $apicArr = $stdOut -Split '\r?\n'

    $apicArr | ForEach-Object {
        # Logical CPU 12 - Physical Core 6 - APIC ID 16 - SMT On
        $null = $_ -Match 'Logical CPU (?<CPU>\d+) \- Physical Core (?<Core>\d+) \- APIC ID (?<APICID>\d+) - SMT (?<SMT>On|Off)'

        if ($Matches['CPU'] -and $Matches['Core'] -and $Matches['APICID'] -and $Matches['SMT']) {
            $apicId = [Int] $Matches['APICID']
            $cpuId  = [Int] $Matches['CPU']
            $core   = [Int] $Matches['Core']
            $SMT    = ($Matches['SMT'] -eq 'On')

            $apicIdToCpu[$apicId]  = $cpuId
            $cpuToApicId[$cpuId]   = $apicId
            $cpuToCore[$cpuId]     = $core
            $apicIdToCore[$apicId] = $core
            $coreToApicId[$core]   = $apicId
            $coreSmtStatus[$core]  = $SMT

            if (!$coreToCpus[$core]) {
                $coreToCpus[$core] = [System.Collections.ArrayList]::new()
            }

            [Void] $coreToCpus[$core].Add($cpuId)
        }
    }


    $Script:coresInfo = @{
        'apicIdToCpu'   = $apicIdToCpu
        'cpuToApicId'   = $cpuToApicId
        'cpuToCore'     = $cpuToCore
        'apicIdToCore'  = $apicIdToCore
        'coreToApicId'  = $coreToApicId
        'coreToCpus'    = $coreToCpus
        'coreSmtStatus' = $coreSmtStatus
    }
}



<#
.DESCRIPTION
    Get the error message for .NET error code
    Unfortunately we cannot just use this to also get the last error code, as it will be overwritten
    by the function call itself
.PARAMETER errorCode
    [Int] (probably) The error message. Might also be hex?
.OUTPUTS
    [Object] The error code and message
#>
function Get-DotNetErrorMessage {
    param(
        [Parameter(Mandatory=$true)] $errorCode
    )

    $errorMessage = (New-Object System.ComponentModel.Win32Exception($errorCode)).Message
    #$errorMessage = [ComponentModel.Win32Exception] $errorCode


    <#
    $errorCode = $dotNetClass::GetLastError()
    $errorMessagePtr = [IntPtr]::Zero
    $bufferSize = 512  # Specify a non-zero value for buffer size
    $formatMessageFlags = 0x100 -bor 0x1000  # FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM
    [Void] $dotNetClass::FormatMessage($formatMessageFlags, [IntPtr]::Zero, $errorCode, 0, [ref]$errorMessagePtr, $bufferSize, [IntPtr]::Zero)
    $errorMessage = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($errorMessagePtr)
    #>

    Write-DebugText('Error Code:    ' + $errorCode)
    Write-DebugText('Error Message: ' + $errorMessage)

    return @{
        'errorMessage' = $errorMessage
        'errorCode'    = $errorCode
    }
}



<#
.DESCRIPTION
    Adds a core error to our global collection for errors, for later use
.PARAMETER coreNumber
    [Int] The core that has thrown the error
.PARAMETER cpuNumberString
    [String] The CPU(s) that have thrown the error
.PARAMETER errorType
    [String] The type of error
.PARAMETER stressTestError
    [String] The stress test error
.PARAMETER errorLogMessage
    [String] An additional error message
.OUTPUTS
    [Void]
#>
function Add-ToErrorCollection {
    param(
        [Parameter(Mandatory=$true)] [Int] $coreNumber,
        [Parameter(Mandatory=$true)] [String] $cpuNumberString,
        [Parameter(Mandatory=$true)] [String] $errorType,
        [Parameter(Mandatory=$true)] [String] $stressTestError,
        [Parameter(Mandatory=$true)][AllowEmptyString()] [String] $errorLogMessage
    )


    if (!$Script:errorCollector[$coreNumber]) {
        $Script:errorCollector[$coreNumber] = @()
    }

    $newEntry = @{
        'date'            = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        'cpuNumberString' = $cpuNumberString
        'errorType'       = $errorType
        'stressTestError' = $stressTestError
        'errorMessage'    = $errorLogMessage
    }

    $Script:errorCollector[$coreNumber] += $newEntry
}




#
# -------------------------------------------------------------------------------------------------------------------------------------
# ------------------------------------------------------- THE MAIN FUNCTIONALITY ------------------------------------------------------
# -------------------------------------------------------------------------------------------------------------------------------------
#

<#
.DESCRIPTION
    The main functionality
#>


# Error Checks

# We need the logs and the configs directory to exist
try {
    if (!(Test-Path -Path $logFilePathAbsolute)) {
        $null = New-Item $logFilePathAbsolute -ItemType Directory
    }

    if (!(Test-Path -Path $configsPathAbsolute)) {
        $null = New-Item $configsPathAbsolute -ItemType Directory
    }
}
catch {
    Exit-WithFatalError -text $_
}


# PowerShell version too low
# This is a neat flag
#Requires -Version 5.0


# The script doesn't work for Powershell version 6 and 7
# There are some missing cmdlets
if ($PSVersionTable.PSVersion.Major -gt 5) {
    Write-Host('')
    Write-Host('FATAL ERROR: The PowerShell version is too _new_!') -ForegroundColor Red
    Write-Host('PowerShell version 6 and above do not support the required functions inside this script!') -ForegroundColor Red
    Write-Host('')
    Write-Host('Please run this script with PowerShell 5.1, which is included with Windows') -ForegroundColor Yellow

    Exit-WithFatalError
}

Write-VerboseText('Started the script at ' + $scriptStartDate.ToString('yyyy-MM-dd HH:mm:ss'))


# Check the directory we're running from
Write-DebugText('PSScriptRoot: ' + $PSScriptRoot)


# Please don't use OneDrive or Dropbox
if ($PSScriptRoot -Match '\\(OneDrive)\\' -or $PSScriptRoot -Match '\\(Dropbox)\\'  -or $PSScriptRoot -Match '\\(_tests)\\') {
    $syncFolder = $Matches[1]

    Write-VerboseText('Synchronized directory detected: ' + $syncFolder)
    Write-DebugText('Checking if the corresponding binary is still running')

    # We assume that the directory name equals the program name (e.g. OneDrive -> OneDrive.exe)
    $syncPrograms = @{
        'onedrive' = @{
            'process' = 'onedrive'
            'name'    = 'OneDrive'
        }
        'dropbox'  = @{
            'process' = 'dropbox'
            'name'    = 'Dropbox'
        }
        # Test conditions
        '_tests'   = @{
            'process' = 'notepad'
            'name'    = 'Test Program'
        }
    }

    $syncProgramProcess  = $syncPrograms[$syncFolder.ToLowerInvariant()]['process']
    $syncProgramName     = $syncPrograms[$syncFolder.ToLowerInvariant()]['name']
    $checkForSyncProcess = Get-Process $syncProgramProcess -ErrorAction Ignore

    Write-DebugText('The synchronization process to check for: ' + $syncProgramProcess)

    if ($checkForSyncProcess) {
        Write-VerboseText('The synchronization binary is running!')
        Write-DebugText('Sync Program Name: ' + $syncProgramName)
        Write-DebugText('Sync Program Path: ' + $checkForSyncProcess.Path)
        Write-DebugText('Throwing error and exiting')

        Write-Host('')
        Write-Host('FATAL ERROR: The directory seems to indicate that you''re trying') -ForegroundColor Red
        Write-Host('to run this inside the ' + $syncProgramName + ' directory!') -ForegroundColor Red
        Write-Host('The ' + $syncProgramName + ' synchronization program is also still running!') -ForegroundColor Red
        Write-Host('')
        Write-Host('If CoreCycler is running inside a synchronized directory, it can severely') -ForegroundColor Yellow
        Write-Host('interfere with the testing process.') -ForegroundColor Yellow
        Write-Host('')
        Write-Host('')

        Write-Host('┌──────────────────────────────────────────────────────────────────────────────┐') -ForegroundColor Black -BackgroundColor DarkYellow
        Write-Host('│ ' + 'To fix this, please run CoreCycler outside such a directory, or close the'.PadRight(76, ' ') + ' │') -ForegroundColor Black -BackgroundColor DarkYellow
        Write-Host('│ ' + 'synchronization program before starting CoreCycler.'.PadRight(76, ' ') + ' │') -ForegroundColor Black -BackgroundColor DarkYellow
        Write-Host('└──────────────────────────────────────────────────────────────────────────────┘') -ForegroundColor Black -BackgroundColor DarkYellow

        Write-Host('')
        Write-Host('The current directory is:') -ForegroundColor Yellow
        Write-Host($PSScriptRoot) -ForegroundColor Cyan
        Write-Host('')
        Write-Host('The detected synchronization program path:') -ForegroundColor Yellow
        Write-Host($checkForSyncProcess.Path) -ForegroundColor Cyan

        Exit-WithFatalError
    }

    else {
        Write-VerboseText('The synchronization binary is not running, assume we''re ok')
    }
}


# Non-ANSI characters in the directory path may pose problems
if ($PSScriptRoot -Match '[^\x00-\x7F]') {
    Write-Host('')
    Write-Host('FATAL ERROR: The directory path contains non-ANSI characters!') -ForegroundColor Red
    Write-Host('')
    Write-Host('Please run this script from a directory that only contains ANSI characters.') -ForegroundColor Yellow
    Write-Host('(for example D:\Overclock\CoreCycler\)') -ForegroundColor Yellow
    Write-Host('')
    Write-Host('The current directory is:') -ForegroundColor Yellow
    Write-Host($PSScriptRoot) -ForegroundColor Cyan

    Exit-WithFatalError
}


# Check if .NET is installed
$hasDotNet3_5 = (($dotNetEntry3_5 = Get-ItemProperty 'HKLM:\Software\Microsoft\NET Framework Setup\NDP\v3.5' -ErrorAction Ignore)        -and ($dotNetEntry3_5 | Get-Member Install) -and $dotNetEntry3_5.Install -eq 1)
$hasDotNet4_0 = (($dotNetEntry4_0 = Get-ItemProperty 'HKLM:\Software\Microsoft\NET Framework Setup\NDP\v4.0\Client' -ErrorAction Ignore) -and ($dotNetEntry4_0 | Get-Member Install) -and $dotNetEntry4_0.Install -eq 1)
$hasDotNet4_x = (($dotNetEntry4_x = Get-ItemProperty 'HKLM:\Software\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction Ignore)     -and ($dotNetEntry4_x | Get-Member Install) -and $dotNetEntry4_x.Install -eq 1)

if (!$hasDotNet3_5 -and !$hasDotNet4_0 -and !$hasDotNet4_x) {
    Write-Host('')
    Write-Host('FATAL ERROR: .NET could not be found or the version is too old!') -ForegroundColor Red
    Write-Host('At least version 3.5 of .NET is required!') -ForegroundColor Red
    Write-Host('')
    Write-Host('You can download the .NET Framework here:') -ForegroundColor Yellow
    Write-Host('https://dotnet.microsoft.com/download/dotnet-framework') -ForegroundColor Cyan

    Exit-WithFatalError
}


# Check if .NET 8 is installed
# We need this for smu-ryzen-cli
if (!(Test-IsDotNetInstalled)) {
    Write-Host('')
    Write-Host('FATAL ERROR: .NET 8 could not be found on the system!') -ForegroundColor Red
    Write-Host('')
    Write-Host('You can download the latest version here:') -ForegroundColor Yellow
    Write-Host('https://dotnet.microsoft.com/en-us/download') -ForegroundColor Cyan

    Exit-WithFatalError
}


# Check if Visual C++ is installed
# We need it for the y-cruncher console wrapper
if (!(Test-IsVisualCInstalled)) {
    Write-Host('')
    Write-Host('FATAL ERROR: Visual C++ Runtime could not be found or the version is too old!') -ForegroundColor Red
    Write-Host('At least version 14 of the VC++ Redistributable is required!') -ForegroundColor Red
    Write-Host('')
    Write-Host('You can download the latest version here:') -ForegroundColor Yellow
    Write-Host('https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist') -ForegroundColor Cyan

    Exit-WithFatalError
}


# Clear the error variable, it may have been populated by the above calls
$Error.Clear()



# Wrap the main functionality in a try {} block, so that the finally {} block is executed even if CTRL+C is pressed
try {
    # Gets the log level, so that Write-DebugText and Write-VerboseText work correctly
    $Script:logLevel = Get-InitialLogLevel

    Write-DebugText('The initial log level: ' + $Script:logLevel)
    Write-DebugText('Starting the main functionality block')



    # Disable the QuickEdit Mode feature of the terminal window
    # The QuickEdit Mode can freeze the console output and the script execution, and we don't want this
    $consoleMode = [ChangeConsoleMode]::GetMode()

    Write-DebugText('The original console mode: ' + $consoleMode)

    $disableQuickEditModeResult = [ChangeConsoleMode]::DisableQuickEdit()
    $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()

    if ($disableQuickEditModeResult) {
        Write-DebugText('Disabled the QuickEdit Mode feature')
    }
    else {
        Write-DebugText('Failed to disabled the QuickEdit Mode feature. (Result ' + $disableQuickEditModeResult + ')')

        if ($errorCode -gt 0) {
            Write-DebugText('Error Code: ' + $errorCode + ' - Line: ' + (Get-ScriptLineNumber))
            $errorResult = Get-DotNetErrorMessage $errorCode
            Write-DebugText($errorResult.errorMessage)
        }
    }



    # Remove the close button from our console window (or at least try to, it won't work for e.g. Windows Terminal)
    # We only really need this when using the Automatic Test Mode with resume, because it creates a Scheduled Task, which can only
    # be removed if the script is exited via CTRL+C
    # And the Automatic Test Mode requires administrator privileges, so the process *should* be started in its own window
    # It's not guaranteed though
    $parentMainWindowMenuHandle = [ConsoleWindowMenu]::GetSystemMenu($parentMainWindowHandle, $false)
    $disableCloseButtonResult = [ConsoleWindowMenu]::DeleteMenu($parentMainWindowMenuHandle, [ConsoleWindowMenu]::SC_CLOSE, [ConsoleWindowMenu]::MF_BYCOMMAND)
    $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()

    if ($disableCloseButtonResult) {
        Write-DebugText('Disabled the close button')
    }
    else {
        Write-DebugText('Failed to disabled the close button. (Result ' + $disableCloseButtonResult + ')')

        if ($errorCode -gt 0) {
            Write-DebugText('Error Code: ' + $errorCode + ' - Line: ' + (Get-ScriptLineNumber))
            $errorResult = Get-DotNetErrorMessage $errorCode
            Write-DebugText($errorResult.errorMessage)
        }
    }



    # Check if we can start the update check background job early, before truely parsing the settings
    $checkForEarlyUpdateCheck = Get-InitialUpdateCheckSetting

    if ($checkForEarlyUpdateCheck -and $checkForEarlyUpdateCheck['enabled'] -eq $true) {
        Write-DebugText('Update check is enabled, initializing the background job (early start)')

        # Store this in our global variable, which will be overwritten later when the settings are fully parsed
        $enableUpdateCheck = $checkForEarlyUpdateCheck['enabled']

        # Create a temporary update settings hashtable to pass to the background job
        $tempUpdateSettings = @{
            'updateCheckFrequency' = $(if ($checkForEarlyUpdateCheck['frequency']) { [Decimal] $checkForEarlyUpdateCheck['frequency'] } else { $updateCheckFrequency })
        }

        $updateCheckJob = Start-UpdateCheckBackgroundJob $tempUpdateSettings
    }


    # This needs to be determined before Get-Settings is called
    # The number of physical and logical cores
    # This also includes hyperthreading resp. SMT (Simultaneous Multi-Threading)
    # We currently only test the first core for each hyperthreaded "package",
    # so e.g. only 12 cores for a 24 threaded Ryzen 5900X
    # If you disable hyperthreading / SMT, both values should be the same
    # Newer Intel processors have a mixed layout, where some cores only support 1 thread
    $processor        = Get-CimInstance -ClassName Win32_Processor
    $isIntelProcessor = ($processor.Manufacturer -eq 'GenuineIntel')
    $numLogicalCores  = $($processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
    $numPhysCores     = $($processor | Measure-Object -Property NumberOfCores -Sum).Sum


    # Set the flag if Hyperthreading / SMT is enabled or not
    $isHyperthreadingEnabled = ($numLogicalCores -gt $numPhysCores)


    # Get the APCI IDs
    # Useful for identifying cores with two threads and threads with one thread
    # Sets the $coresInfo lookup table
    Get-ProcessorCoresInformation


    # Set the flag if we have an asymmetric thread loadout, e.g. on a 12th-14th generation Intel system,
    # where the Performance cores have 2 threads, but the Efficient cores have only 1
    $hasAsymmetricCoreThreads = ($isHyperthreadingEnabled -and ($numLogicalCores -lt $numPhysCores*2))


    # Get the cores with 2 threads and those with only 1
    $coresInfo['coreSmtStatus'].Keys | Sort-Object | ForEach-Object {
        $coreId = $_
        $smtStatus = $coresInfo['coreSmtStatus'][$coreId]

        if ($smtStatus -eq $true) {
            [Void] $coresWithTwoThreads.Add($coreId)
        }
        else {
            [Void] $coresWithOneThread.Add($coreId)
        }
    }


    # Check if we have more than 64 logical cores, in which case we need a special treatment for setting the affinity
    # We cannot use the default .ProcessorAffinity property then, we need to use SetThreadGroupAffinity
    $hasMoreThan64Cores = ($numLogicalCores -gt 64)


    # Calculate the number of Processor Groups
    # We assume that the first group is filled up to 64 and all remaining CPUs are then put in the second (or third, etc) group
    # TODO: Note that this is not always the case, for multi-socket mainboards the cores seem to be evenly split across the groups
    #       Although I don't expect a multi-socket system being used with CoreCycler
    if ($hasMoreThan64Cores) {
        $numProcessorGroups = [Math]::ceiling(($numLogicalCores / 64))

        if ($numLogicalCores % 64 -ne 0) {
            $numCpusInLastProcessorGroup = $numLogicalCores % 64
        }
    }


    # Export the default settings to the default.config.ini file
    Export-DefaultSettings


    # Get the default and the user settings
    # This is early because we want to be able to get the log level
    Get-Settings


    # Dump the settings to the log file
    Write-DebugText('')
    Write-DebugText('-------------------------------- The config file -------------------------------')
    Write-DebugText($configUserPath)
    Write-DebugText('--------------------------------------------------------------------------------')
    Write-DebugText('')

    $configFile = Get-ChildItem -Path $configUserPath
    $reader = [System.IO.File]::OpenText($configFile)
    $settingsString = $reader.ReadToEnd()
    $settingsArray = @($settingsString -Split '\r?\n')
    $reader.Close()

    foreach ($line in $settingsArray) {
        Write-DebugText($line)
    }

    Write-DebugText('')
    Write-DebugText('')


    if ($customConfigPath) {
        Write-DebugText('---------------------------- The custom config file ----------------------------')
        Write-DebugText($customConfigPath)
        Write-DebugText('--------------------------------------------------------------------------------')
        Write-DebugText('')

        $configFile = Get-ChildItem -Path $customConfigPath
        $reader = [System.IO.File]::OpenText($configFile)
        $settingsString = $reader.ReadToEnd()
        $settingsArray = @($settingsString -Split '\r?\n')
        $reader.Close()

        foreach ($line in $settingsArray) {
            Write-DebugText($line)
        }

        Write-DebugText('')
        Write-DebugText('')
    }


    Write-DebugText('------------------------------ The parsed settings -----------------------------')

    foreach ($section in $settings.GetEnumerator()) {
        if (($null -ne $section.Value -and ![String]::IsNullOrWhiteSpace($section.Value)) -and $section.Value -is [Hashtable]) {
            foreach ($setting in $section.Value.GetEnumerator()) {
                Write-DebugText('[' + $section.Name +'] ' + $setting.Name + ' = ' + $setting.Value)
            }
        }
        else {
            Write-DebugText('[No Section] ' + $section.Name + ' = ' + $section.Value)
        }

        Write-DebugText('')
    }

    Write-DebugText('--------------------------------------------------------------------------------')
    Write-DebugText('--------------------------------------------------------------------------------')
    Write-DebugText('--------------------------------------------------------------------------------')
    Write-DebugText('')


    # Start a request to check for an update
    # As early as possible, so that it has time to finish the URL query while other things are being processed
    # The result of this job will be received later
    # We may have started this job already earlier, so check if it's already set
    if ($enableUpdateCheck -and !$updateCheckJob) {
        Write-DebugText('Update check is enabled, initializing the background job')

        $updateCheckJob = Start-UpdateCheckBackgroundJob
    }


    # Get data for the OS (only works for Windows obviously)
    $winOperatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem


    # Get the loale
    $currentLocale = Get-WinSystemLocale


    # The amount of memory in the system
    $freeMemory  = $winOperatingSystem.FreePhysicalMemory * 1KB                     # This is returned in KB, so we multiply it


    Write-VerboseText('')
    Write-VerboseText('Operating System:')
    Write-VerboseText('OS:          ' + $winOperatingSystem.Caption)
    Write-VerboseText('Version:     ' + $winOperatingSystem.Version)
    Write-VerboseText('BuildNumber: ' + $winOperatingSystem.BuildNumber)
    Write-VerboseText('CSDVersion:  ' + $winOperatingSystem.CSDVersion)
    Write-VerboseText('CodeSet:     ' + $winOperatingSystem.CodeSet)
    Write-VerboseText('CountryCode: ' + $winOperatingSystem.CountryCode)
    Write-VerboseText('OSLanguage:  ' + $winOperatingSystem.OSLanguage)
    Write-VerboseText('Locale:      ' + $winOperatingSystem.Locale + ' (hex -> int -> ' + [System.Convert]::ToInt32($winOperatingSystem.Locale, 16) + ')')
    Write-VerboseText('Locale Name: ' + $currentLocale.DisplayName + ' (' + $currentLocale.Name + ')')
    Write-VerboseText('Free Memory: ' + [Math]::Round($freeMemory / 1MB) + ' MB')
    Write-VerboseText('Script Root: ' + $PSScriptRoot)

    Write-VerboseText('')
    Write-VerboseText('CPU Info:')
    Write-VerboseText('Manufacturer:              ' + $processor.Manufacturer)
    Write-VerboseText('Name:                      ' + $processor.Name)
    Write-VerboseText('Caption:                   ' + $processor.Caption)
    Write-VerboseText('NumberOfCores:             ' + $numPhysCores)
    Write-VerboseText('NumberOfLogicalProcessors: ' + $numLogicalCores)
    Write-VerboseText('MaxClockSpeed:             ' + $processor.MaxClockSpeed)
    Write-VerboseText('DeviceID:                  ' + $processor.DeviceID)

    Write-VerboseText('')
    Write-VerboseText('APIC IDs:')

    $maxLengthCpu    = ($coresInfo['cpuToApicId'].Keys | Measure-Object -Maximum).Maximum.ToString().Length
    $maxLengthAcpiId = ($coresInfo['apicIdToCpu'].Keys | Measure-Object -Maximum).Maximum.ToString().Length
    $maxLengthCore   = $numLogicalCores.ToString().Length

    $coresInfo['cpuToApicId'].Keys | Sort-Object | ForEach-Object {
        $cpuId     = $_
        $coreId    = $coresInfo['cpuToCore'][$_]
        $apicId    = $coresInfo['cpuToApicId'][$_]
        $smtStatus = $coresInfo['coreSmtStatus'][$coreId]

        $str  = 'CPU ' + ($cpuId.ToString().PadLeft($maxLengthCpu, ' '))
        $str += ':  ACPI ID = ' + ($apicId.ToString().PadLeft($maxLengthAcpiId, ' '))
        $str += '  -> Core ' + ($coreId.ToString().PadLeft($maxLengthCore, ' '))
        $str += ' (SMT ' + $(if ($smtStatus) { 'On' } else { 'Off' }) + ')'

        Write-VerboseText($str)
    }


    # Check if we can use Write-VolumeCache to write the log file data to the disk
    # It will not work under certain circumstances, e.g. for VeraCrypt volumes
    # Get-Volume and Write-VolumeCache have the same requirements
    if ($settings.Logging.flushDiskWriteCache -eq 1 -or $settings.AutomaticTestMode.enableResumeAfterUnexpectedExit -gt 0) {
        $canUseFlushToDisk = !!(Get-Volume $scriptDriveLetter -ErrorAction Ignore)

        # Also check if the drive "letter" is an actual drive, and not e.g. a network share
        $canUseFlushToDisk = ($canUseFlushToDisk = $scriptDriveLetter -and $scriptDriveLetter -match '[a-z]')

        Write-DebugText("Can we use the flush to disk functionality: " + $canUseFlushToDisk)
    }


    # Get last WHEA error
    if ($settings.General.lookForWheaErrors -gt 0) {
        if (!(Test-EventLogService)) {
            Exit-WithFatalError -text ('"[General] lookForWheaErrors" was set to 1, but the Windows Event Log service is not running!')
        }


        $storedWheaError = Get-LastWheaError

        # DEBUG
        # Used to throw a WHEA error notice
        # $filterHashTable = @{
        #     'ProviderName' = 'Microsoft-Windows-WHEA-Logger'
        #     'Level'        = @(2, 3)
        # }
        # $storedWheaError = Get-WinEvent -FilterHashtable $filterHashTable -MaxEvents 2 -ErrorAction Ignore
        # $storedWheaError = $storedWheaError[1]
    }


    # Check if we can access Visual Basic
    try {
        $null = [Microsoft.VisualBasic.Interaction] | Get-Member -Static
    }
    catch {
        Write-ColorText('FATAL ERROR: Could not access [Microsoft.VisualBasic.Interaction]!') Red
        Write-ErrorText $Error
        Exit-WithFatalError
    }


    # The process id of this and the calling process
    Write-DebugText('The script process id (PID):   ' + $scriptProcessId)
    Write-DebugText('The parent process id:         ' + $parentProcessId)
    Write-DebugText('The parent main window handle: ' + $parentMainWindowHandle)


    # Try to get the localized counter names
    # We only need these if "disableCpuUtilizationCheck" is set to 0 and "useWindowsPerformanceCountersForCpuUtilization" is set to 1, or "enableCpuFrequencyCheck" is set to 1
    # The "enablePerformanceCounters" is the shortcut for this
    if ($enablePerformanceCounters) {
        try {
            Write-VerboseText('Trying to get the localized performance counter names')

            $counterNameIds = Get-PerformanceCounterIDs $englishCounterNames

            $englishCounterNames.GetEnumerator() | ForEach-Object {
                Write-VerboseText(('ID of "' + $_ + '": ').PadRight(43, ' ') + $(if ($counterNameIds[$_]) { $counterNameIds[$_] } else { 'NOT FOUND!' }))
            }

            foreach ($performanceCounterName in $englishCounterNames) {
                if (!$counterNameIds[$performanceCounterName] -or $counterNameIds[$performanceCounterName] -eq 0) {
                    throw('Could not get the ID for the Performance Counter Name "' + $performanceCounterName + '" from the registry!')
                }

                Write-DebugText('Getting the localized name for "' + $performanceCounterName + '" with ID "' + $counterNameIds[$performanceCounterName] + '"')
                $counterNames[$performanceCounterName] = Get-PerformanceCounterLocalName $counterNameIds[$performanceCounterName]
                Write-VerboseText(('The localized name for "' + $performanceCounterName + '": ').PadRight(43, ' ') + $counterNames[$performanceCounterName])
            }


            $counterNames['FullName']      = '\'  + $counterNames['Process'] + '(*)\' + $counterNames['ID Process']
            $counterNames['SearchString']  = '\\' + $counterNames['ID Process'] + '$'
            $counterNames['ReplaceString'] = '\'  + $counterNames['% Processor Time']

            Write-VerboseText(('FullName: ').PadRight(43, ' ')      + $counterNames['FullName'])
            Write-VerboseText(('SearchString: ').PadRight(43, ' ')  + $counterNames['SearchString'])
            Write-VerboseText(('ReplaceString: ').PadRight(43, ' ') + $counterNames['ReplaceString'])

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
            Write-Host 'The full thrown error message:' -ForegroundColor Yellow

            $Error


            # Get the content of the registry entry for the performance counters, both the English and the localized one
            $keyEnglish         = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib\009'
            $allCountersEnglish = (Get-ItemProperty -Path $keyEnglish -Name Counter).Counter
            $numCountersEnglish = $allCountersEnglish.Count

            # The localized performance counters
            $keyCurrent         = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib\CurrentLanguage'
            $allCountersCurrent = (Get-ItemProperty -Path $keyCurrent -Name Counter).Counter
            $numCountersCurrent = $allCountersCurrent.Count

            Write-DebugText('The number of counters for English:         ' + $numCountersEnglish)
            Write-DebugText('The number of counters for CurrentLanguage: ' + $numCountersCurrent)

            Write-DebugText('')
            Write-DebugText('English Counters:')
            Write-DebugText('-------------------------------------------------------------------------')
            Write-DebugText($allCountersEnglish)

            Write-DebugText('')
            Write-DebugText('CurrentLanguage Counters:')
            Write-DebugText('-------------------------------------------------------------------------')
            Write-DebugText($allCountersCurrent)

            Exit-WithFatalError
        }


        # Try to access the localized Performance Process Counters
        # It may be disabled

        # This is the original english call:
        # Get-Counter "\Process(*)\ID Process" -ErrorAction Stop
        # We're starting a background job so that the Get-Counter call is not cached, which causes problems later on
        $counter = Start-Job -ScriptBlock {
            $data = @($input)
            (Get-Counter $data.'FullName' -ErrorAction Ignore).CounterSamples
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
    }



    # Get the final stress test program file paths and command lines
    foreach ($testProgram in $stressTestPrograms.GetEnumerator()) {
        $stressTestPrograms[$testProgram.Name]['absolutePath']        = $PSScriptRoot + '\' + $testProgram.Value['processPath'] + '\'
        $stressTestPrograms[$testProgram.Name]['absoluteInstallPath'] = $PSScriptRoot + '\' + $testProgram.Value['installPath'] + '\'
        $stressTestPrograms[$testProgram.Name]['fullPathToExe']       = $testProgram.Value['absolutePath'] + $testProgram.Value['processName']
        $stressTestPrograms[$testProgram.Name]['configFilePath']      = $testProgram.Value['absolutePath'] + $testProgram.Value['configName']

        # If we have a comma separated list, remove all spaces and transform to upper case
        # yCruncher and yCruncher Old share the same setting in the config file, adjust for that
        # As do Prime95 and Prime95 Dev
        $settingTestProgramName = $(if ($testProgram.Name -eq 'ycruncher_old') { 'ycruncher' } elseif ($testProgram.Name -eq 'prime95_dev') { 'prime95' } else { $testProgram.Name })
        $commandMode = (($settings[$settingTestProgramName].mode -Split '\s*,\s*' | Where-Object { $_.Length -gt 0 } | Sort-Object) -Join ',').ToUpperInvariant()

        # Generate the command line
        $data = @{
            '%fileName%'       = $testProgram.Value['processName'] + '.' + $testProgram.Value['processNameExt']
            '%fullPathToExe%'  = $testProgram.Value['fullPathToExe'] + '.' + $testProgram.Value['processNameExt']
            '%mode%'           = $commandMode
            '%configFilePath%' = $testProgram.Value['configFilePath']
        }

        $command = $stressTestPrograms[$testProgram.Name]['command']


        # Special handling if the custom logging wrapper for y-cruncher is activated
        if (($testProgram.Name -eq 'ycruncher' -or $testProgram.Name -eq 'ycruncher_old') -and $isYCruncherWithLogging) {
            $stressTestPrograms[$testProgram.Name]['fullPathToLoadExe'] = $testProgram.Value['absolutePath'] + $testProgram.Value['processNameForLoad']

            # Use the command for logging, not the regular command
            $command = $stressTestPrograms[$testProgram.Name]['commandWithLogging']

            $Script:stressTestLogFileName = 'yCruncher_' + $scriptStartDateTime + '_mode_' + $settings.mode + '.log'
            $Script:stressTestLogFilePath = $logFilePathAbsolute + $stressTestLogFileName

            $data['%fileName%'] = ($testProgram.Value['processNameForLoad'] + '.' + $testProgram.Value['processNameExt'])
            $data.add('%fullPathToLoadExe%', $testProgram.Value['fullPathToLoadExe'] + '.' + $testProgram.Value['processNameExt'])
            $data.add('%helpersPath%', $helpersPathAbsolute)
            $data.add('%logFilePath%', $stressTestLogFilePath)
        }

        # Special handling for Linpack
        if ($testProgram.Name -eq 'linpack') {
            if ($isLinpack) {
                $Script:stressTestLogFileName = 'Linpack_' + $scriptStartDateTime + '_Version_' + $settings.Linpack.version + '_' + $settings.mode + '.log'
                $Script:stressTestLogFilePath = $logFilePathAbsolute + $stressTestLogFileName
            }

            $stressTestPrograms[$testProgram.Name]['fullPathToLoadExe'] = $testProgram.Value['absolutePath'] + $testProgram.Value['processNameForLoad']

            $data['%fileName%'] = ($testProgram.Value['processNameForLoad'] + '.' + $testProgram.Value['processNameExt'])
            $data.add('%fullPathToLoadExe%', $testProgram.Value['fullPathToLoadExe'] + '.' + $testProgram.Value['processNameExt'])
            $data.add('%logFilePath%', $stressTestLogFilePath)


            # Some other environment variables also need to be set, depending on if we're running on AMD or Intel
            # AMD:
            # MKL_DEBUG_CPU_TYPE = 4
            # Intel:
            # MKL_DEBUG_CPU_TYPE not set at all
            # Maybe we can influence which instructions to use by setting MKL_DEBUG_CPU_TYPE?
            # At least when set to 0 (instead of completely removing it), the GFlops dropped significantly on a 14900KF
            #                             Ryzen 5900X                  Intel 14900KF
            #                             GFlops    Time    Temp       GFlops    Time    Temp
            # MKL_DEBUG_CPU_TYPE missing  crash                        ~78       ~34s    ~69°C
            # MKL_DEBUG_CPU_TYPE = 0      crash                        ~28       ~96s    ~64°C
            # MKL_DEBUG_CPU_TYPE = 1      ~21       ~126s   ~67°C      ~30       ~87s    ~66°C (when set to only CPU 1: Intel MKL ERROR: CPU 1 is not supported)
            # MKL_DEBUG_CPU_TYPE = 2      ~25       ~105s   ~71°C      ~28       ~94s    ~65°C
            # MKL_DEBUG_CPU_TYPE = 3      ~27       ~99s    ~71°C      ~30       ~89s    ~66°C
            # MKL_DEBUG_CPU_TYPE = 4      ~45       ~59s    ~75°C      ~51       ~52s    ~66°C
            # MKL_DEBUG_CPU_TYPE = 5      ~66       ~40s    ~76°C      ~78       ~34s    ~69°C
            #
            #            AMD    INTEL
            # SLOWEST    1      0
            # SLOW       2      2
            # MEDIUM     3      3
            # FAST       4      4
            # FASTEST    5      5

            # Set the MKL_DEBUG_CPU_TYPE depending on the mode and the processor type
            $MKL_DEBUG_CPU_TYPES = @{
                'SLOWEST' = @{ 'amd' = 1; 'intel' = 0 }
                'SLOW'    = @{ 'amd' = 2; 'intel' = 2 }
                'MEDIUM'  = @{ 'amd' = 3; 'intel' = 3 }
                'FAST'    = @{ 'amd' = 4; 'intel' = 4 }
                'FASTEST' = @{ 'amd' = 5; 'intel' = 5 }
            }


            # Reduce Linpack to three settings?
            # SSE  -> MKL_DEBUG_CPU_TYPE 1 / 0
            # AVX  -> MKL_DEBUG_CPU_TYPE ?
            # AVX2 -> MKL_DEBUG_CPU_TYPE 5

            # Supported values for MKL_ENABLE_INSTRUCTIONS
            # (used in Intel XTU)
            # (only available in 2021+)
            # SSE4_2
            # AVX
            # AVX2
            #
            # Possibly these are all the supported values for MKL_ENABLE_INSTRUCTIONS (taken from the linpack binary):
            # It doesn't seem to work with on AMD at all
            # Setting               Ryzen
            # COMPATIBLE            113.7
            # SSE2                  113.7
            # SSSE3                 113.4
            # SSE4_1                113.4
            # SSE4_2                113.4
            # AVX                   113.6
            # AVX2                  113.3
            # AVX512_MIC            113.1
            # AVX512                113.9
            # AVX512_MIC_E1         113.3
            #
            # On Intel 14th gen this works for SSE4_2, AVX, AVX2

            $processorType = $(if ($isIntelProcessor) { 'intel' } else { 'amd' })

            # Only version 2018 and 2019 support lower modes than FASTEST
            $linpackMode =  $(if ($settings.Linpack.version -eq '2018' -or $settings.Linpack.version -eq '2019') { $settings.Linpack.mode.ToUpperInvariant() } else { 'FASTEST' })

            $data.add('%MKL_DEBUG_CPU_TYPE%', '$env:MKL_DEBUG_CPU_TYPE = ' + $MKL_DEBUG_CPU_TYPES[$linpackMode][$processorType] + ';')
        }



        # Replace the variables in the command to start the stress test
        foreach ($key in $data.Keys) {
            $command = $command.Replace($key, $data[$key])
        }

        $stressTestPrograms[$testProgram.Name]['command'] = $command
    }


    # The name of the selected stress test program
    $selectedStressTestProgram = $stressTestPrograms[$settings.General.stressTestProgram]['displayName']

    if ($isLinpack) {
        $selectedStressTestProgram = $selectedStressTestProgram + ' ' + $settings.Linpack.version
    }


    # Set the correct process name
    $processName = $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad']


    # The expected CPU usage for the running stress test process
    # The selected number of threads should be at 100%, so e.g. for 1 thread out of 24 threads this is 100/24*1= 4.17%
    # Used to determine if the stress test is still running or has thrown an error
    # For one thread
    $expectedUsagePerCore = (100 / $numLogicalCores)


    # For the selected number of threads
    # We will need to set this on a per-core basis further below (e.g. for cores that only support one thread)
    $expectedUsageTotal = $null


    # Define the lower limit for process usage / processor time
    # Set it to 50% of the expected / measured time
    $lowerLimitForProcessUsage = 0.5


    # The factor to calculate the minimum processor time
    # Most of the time it should equal $lowerLimitForProcessUsage
    # But not always:
    # 1 Thread:  measureTime * 0.5
    # 2 Threads: measureTime * ($numberOfThreads * 0.5)
    # 2 Threads but core supports only 1: measureTime * 0.5
    # assignBothVirtualCoresForSingleThread: measureTime * 0.5
    $factorForMinProcessorTime = $lowerLimitForProcessUsage


    # The factor to calculate the expected usage / processor time
    # 1 Thread:  measureTime * numberOfThreads = measureTime * 1
    # 2 Threads: measureTime * numberOfThreads = measureTime * 2
    # 2 Threads but core supports only 1: measureTime * 1
    # assignBothVirtualCoresForSingleThread: measureTime * 1
    $factorForExpectedUsage = $null


    # The minimum CPU usage for the stress test program, below which it should be treated as an error
    # We need to account for the number of threads
    # 100/128=  0,781% for 1 thread out of 128 threads
    # 100/64=   1,563% for 1 thread out of 64 threads
    # 100/32=   3,125% for 1 thread out of 32 threads
    # 100/32*2= 6,250% for 2 threads out of 32 threads
    # 100/24=   4,167% for 1 thread out of 24 threads
    # 100/24*2= 8,334% for 2 threads out of 24 threads
    # 100/12=   8,334% for 1 thread out of 12 threads
    # 100/12*2= 16,67% for 2 threads out of 12 threads
    # Use either 0.75% as the lower limit or the total expected usage - the expected usage per core if one thread failed
    # That's pretty low with many cores
    # Let's set it to 50% of the expected usage
    # We will need to set this on a per-core basis further below (e.g. for cores that only support one thread)
    $minProcessUsage = $null


    # Store all the cores that have thrown an error in the stress test
    # These cores will be skipped on the next iteration
    [Int[]] $coresWithError = @()


    # Count the number of errors for each cores if the skipCoreOnError setting is 0
    $coresWithErrorsCounter = @{}

    for ($i = 0; $i -lt $numPhysCores; $i++) {
        $coresWithErrorsCounter[$i] = 0
        $coresWithWheaErrorsCounter[$i] = 0
    }


    # The runtime per core
    $runtimePerCore = $settings.General.runtimePerCore

    # It may be set to "auto"
    if ($settings.General.runtimePerCore.ToString().ToLowerInvariant() -eq 'auto') {
        # For Prime95 and y-cruncher with logging wrapper, we're setting the runtimePerCore to 24 hours as a temporary value
        # For y-cruncher without logging, we're trying to estimate based on the selected/available tests
        # For Aida64 and Linpack, we're using 10 minutes
        if ($isPrime95 -or $isYCruncherWithLogging) {
            $runtimePerCore = 24 * 60 * 60  # 24 hours as a temporary value
            $useAutomaticRuntimePerCore = $true
        }
        # For y-cruncher without logging, try to estimate the duration
        elseif ($isYCruncher -or $isYCruncherOld) {
            # Selected tests * duration of test + time in suspension + buffer
            $runtimePerCore = Get-EstimatedYCruncherRuntimePerCore
        }
        # Otherwise we're just using 10 minutes
        else {
            $runtimePerCore = 10 * 60
        }
    }


    # Calculate the amount of interval checks for the CPU power check
    # Note: we cannot calculate this when the runtimePerCore is set to "auto"
    if ($tickInterval -ge 1) {

        # We need a special treatment for a custom delayFirstErrorCheck value
        if ($delayFirstErrorCheck) {
            $cpuCheckIterations = [Math]::Floor(($runtimePerCore - $delayFirstErrorCheck) / $tickInterval)
        }
        else {
            $cpuCheckIterations = [Math]::Floor($runtimePerCore / $tickInterval)
        }

        # We want at least one tick to happen
        $cpuCheckIterations = [Math]::Max(1, $cpuCheckIterations)
    }


    # Calculate the remaining runtime after all the ticks have been processed
    # Note that we may ditch or make it conditional in a future release due the inconsistencies with the suspension and resuming
    if ($delayFirstErrorCheck) {
        $runtimeRemaining = $runtimePerCore - $delayFirstErrorCheck - ($cpuCheckIterations * $tickInterval)
    }
    else {
        $runtimeRemaining = $runtimePerCore - ($cpuCheckIterations * $tickInterval)
    }

    $runtimeRemaining = [Math]::Max(0, $runtimeRemaining)


    # Get the actual core test mode
    $coreTestOrderMode = $settings.General.coreTestOrder

    # If set to default, switch between alternate for more than 8 cores and random for up to 8 cores
    if ($settings.General.coreTestOrder -eq 'default') {
        if ($numPhysCores -gt 8) {
            $coreTestOrderMode = 'alternate'
        }
        else {
            $coreTestOrderMode = 'random'
        }
    }

    # If we find only numbers (and a comma), transform it into an array
    elseif ($settings.General.coreTestOrder -Match '\d+') {
        $coreTestOrderMode = 'custom'

        # Store the custom core test order array in an ArrayList
        $settings.General.coreTestOrder -Split '\s*,\s*|\s+' | ForEach-Object {
            if ($_ -Match '^\d+$') {
                $coreIndex = [Int] $_

                # Check if cores to test contains an invalid core (i.e. more than available)
                if ($coreIndex -lt 0 -or $coreIndex -gt $numPhysCores-1) {
                    $errorMessage = 'Invalid "coreTestOrder" entry detected!' + [Environment]::NewLine

                    if ($coreIndex -lt 0) {
                        $errorMessage += 'Core entry "' + $coreIndex.ToString() + '" is negative'
                    }

                    if ($coreIndex -gt $numPhysCores-1) {
                        $errorMessage += 'Core entry "' + $coreIndex.ToString() + '" is too high (only ' + $numPhysCores + ' cores available - starting with 0, so max is ' + ($numPhysCores-1) + ')'
                    }

                    Exit-WithFatalError $errorMessage
                }

                [Void] $coreTestOrderCustom.Add($coreIndex)
            }
        }
    }


    # Prevent sleep while the script is running (but allow the monitor to turn off)
    [Windows.PowerUtil]::StayAwake($true, $false, 'CoreCycler is currently running.')

    # Create a reason to block a shutdown
    # $PID may not work, as the function requires "a handle to the main window of the application"
    # The parent window (the calling cmd.exe or WindowsTerminal) does have a main window handle, so let's try this
    if ($parentMainWindowHandle -ne [System.IntPtr]::Zero) {
        $shutdownBlockReasonCreateRetVal = [ShutdownBlock]::ShutdownBlockReasonCreate($parentMainWindowHandle, 'CoreCycler is currently running.')
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()

        if ($shutdownBlockReasonCreateRetVal) {
            Write-VerboseText('Successfully created the shutdown block reason: (' + $shutdownBlockReasonCreateRetVal + ')')
        }
        else {
            Write-VerboseText('Could not create the shutdown block reason! (Return value: ' + $shutdownBlockReasonCreateRetVal + ')')

            if ($errorCode -gt 0) {
                Write-DebugText('Error Code: ' + $errorCode + ' - Line: ' + (Get-ScriptLineNumber))
                $errorResult = Get-DotNetErrorMessage $errorCode
                Write-VerboseText($errorResult.errorMessage)
            }
        }
    }



    # Check if the stress test process is already running
    $stressTestProcess = Get-Process $processName -ErrorAction Ignore

    # Some programs share the same process for stress testing and for displaying the main window, and some not
    if ($stressTestProgramsWithSameProcess -contains $settings.General.stressTestProgram) {
        $windowProcess = $stressTestProcess
    }
    else {
        $windowProcess = Get-Process $stressTestPrograms[$settings.General.stressTestProgram]['processName'] -ErrorAction Ignore
    }


    # Close all existing instances of the stress test program and start a new one with our config
    if ($stressTestProcess -or $windowProcess) {
        Write-VerboseText('There already exists an instance of ' + $selectedStressTestProgram + ', trying to close it')

        if ($windowProcess) {
            Write-VerboseText('Window Process ID: ' + $windowProcess.Id + ' - ProcessName: ' + $windowProcess.ProcessName)
        }
        if ($stressTestProcess) {
            Write-VerboseText('Stress Test ID: ' + $stressTestProcess.Id + ' - ProcessName: ' + $stressTestProcess.ProcessName)
        }

        Close-StressTestProgram
    }


    # Create the required config files for the stress test program
    Initialize-StressTestProgram


    # Get the current datetime
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'


    # Start messages
    $headline     = '┤ CoreCycler v' + $version + ' started at ' + $timestamp + ' ├'
    $padding      = 80 - $headline.Length - 2
    $paddingLeft  = [Math]::Ceiling($padding / 2)
    $paddingRight = [Math]::Floor($padding / 2)


    # Get the update check job at this point
    if ($enableUpdateCheck) {
        Write-DebugText('Getting the result of the update check background job')

        $updateStartTime = Get-Date
        $updateCheckResult = $updateCheckJob | Wait-Job -Timeout 4 | Receive-Job

        # Write-DebugText('The returned result:')

        # if ($updateCheckResult) {
        #     foreach ($entry in $updateCheckResult.GetEnumerator()) {
        #         if ($entry.Name -ne 'messages') {
        #             #Write-DebugText($entry | Format-List | Out-String)
        #             Write-DebugText('{ ' + $entry.Name + ' = ' + $entry.Value + ' }')
        #         }
        #     }
        # }

        Write-DebugText('Messages from the update background job:')

        if (!$updateCheckResult -or !($updateCheckResult['messages'])) {
            Write-DebugText('No messages returned')
        }
        else {
            foreach ($message in $updateCheckResult['messages']) {
                Write-DebugText($message)
            }

            $showUpdateAvailableMessage = $updateCheckResult['isNew']
            Write-DebugText('Is there an update available:       ' + $updateCheckResult['isNew'])
        }


        $updateEndTime = Get-Date
        $updateRunTime = $updateEndTime - $updateStartTime

        Write-DebugText('Update Check Started (User Time):   ' + $updateStartTime.ToString('HH:mm:ss'))
        Write-DebugText('Update Check Ended (User Time):     ' + $updateEndTime.ToString('HH:mm:ss'))
        Write-DebugText('Update Check Runtime (User Time):   ' + $updateRunTime.TotalSeconds)
    }



    # Check if the Automatic Test Mode feature was enabled
    Initialize-AutomaticTestMode


    # Always remove the .automode file at this point, we don't want it to interfere
    Remove-AutoModeFile



    # Start messages
    Write-Text('')
    Write-ColorText('╔══════════════════════════════════════════════════════════════════════════════╗') Green
    #Write-ColorText('╟' + ''.PadLeft($paddingLeft, '─') + $headline + ''.PadRight($paddingRight, '─') + '╢') Green
    Write-ColorText('╟' + ''.PadLeft($paddingLeft, '─')) Green -NoNewline
    Write-ColorText($headline) Green -NoNewline
    Write-ColorText(''.PadRight($paddingRight, '─') + '╢') Green
    Write-ColorText('╚══════════════════════════════════════════════════════════════════════════════╝') Green
    Write-Text('')

    # Log Level
    $logLevelText = @(
        'No additional output'
        'Writing verbose messages to log file'
        'Writing debug messages to log file'
        'Display verbose messages in terminal'
        'Display debug messages in terminal'
    )

    $logLevel = [Math]::Min([Math]::Max(0, $settings.Logging.logLevel), 4)

    Write-ColorText('Log Level set to: ..................... ' + $logLevel + ' [' + $logLevelText[$logLevel] + ']') Cyan
    Write-ColorText('Use the Windows Event Log: ............ ' + ($(if ($settings.Logging.useWindowsEventLog) { 'ENABLED' } else { 'DISABLED' }))) Cyan
    Write-ColorText('Check for WHEA errors: ................ ' + ($(if ($settings.General.lookForWheaErrors) { 'ENABLED' } else { 'DISABLED' }))) Cyan

    # Display some initial information
    Write-ColorText('Stress test program: .................. ' + $selectedStressTestProgram.ToUpperInvariant()) Cyan
    Write-ColorText('Selected test mode: ................... ' + $settings.mode.ToUpperInvariant()) Cyan

    if ($isPrime95 -and $settings.mode -ne 'CUSTOM') {
        Write-ColorText('Selected FFT size: .................... ' + $settings.Prime95.FFTSize.ToUpperInvariant() + ' (' + [Math]::Floor($minFFTSize/1024) + 'K - ' + [Math]::Ceiling($maxFFTSize/1024) + 'K)') Cyan
    }
    if ($isYCruncher -or $isYCruncherOld) {
        Write-ColorText('Selected y-cruncher tests: ............ ' + ($settings.yCruncher.tests -Join ', ')) Cyan
        Write-ColorText('Duration per test: .................... ' + ($settings.yCruncher.testDuration)) Cyan
    }
    if ($isLinpack) {
        Write-ColorText('Memory size: .......................... ' + ($settings.Linpack.memory.ToUpperInvariant())) Cyan
    }

    Write-ColorText('Detected processor: ................... ' + $processor.Name) Cyan
    Write-ColorText('Logical/Physical cores: ............... ' + $numLogicalCores + ' logical / ' + $numPhysCores + ' physical cores') Cyan
    Write-ColorText('Hyperthreading / SMT is: .............. ' + ($(if ($isHyperthreadingEnabled) { 'ENABLED' } else { 'DISABLED' }))) Cyan
    Write-ColorText('Selected number of threads: ........... ' + $settings.General.numberOfThreads) Cyan

    if ($settings.General.numberOfThreads -eq 1) {
        Write-ColorText('Assign both cores to stress thread: ... ' + ($(if ($settings.General.assignBothVirtualCoresForSingleThread) { 'ENABLED' } else { 'DISABLED' }))) Cyan
    }

    Write-ColorText('Runtime per core: ..................... ' + (Get-FormattedRuntimePerCoreString $settings.General.runtimePerCore).ToUpperInvariant()) Cyan
    Write-ColorText('Suspend periodically: ................. ' + ($(if ($settings.General.suspendPeriodically) { 'ENABLED' } else { 'DISABLED' }))) Cyan
    Write-ColorText('Restart for each core: ................ ' + ($(if ($settings.General.restartTestProgramForEachCore) { 'ENABLED' } else { 'DISABLED' }))) Cyan
    Write-ColorText('Test order of cores: .................. ' + $settings.General.coreTestOrder.ToUpperInvariant() + $(if ($settings.General.coreTestOrder.ToLowerInvariant() -eq 'default') { ' (' + $coreTestOrderMode.ToUpperInvariant() + ')' })) Cyan
    Write-ColorText('Number of iterations: ................. ' + $settings.General.maxIterations) Cyan


    # Print a message if we're ignoring certain cores
    if ($settings.General.coresToIgnore.Count -gt 0) {
        $coresToIgnoreString = (($settings.General.coresToIgnore | Sort-Object) -Join ', ')
        Write-ColorText('Ignored cores: ........................ ' + $coresToIgnoreString) Cyan
    }


    # Automatic Test Mode
    if ($useAutomaticTestMode) {
        if ($useAutomaticTestModeWithResume) {
            Write-ColorText('Automatic Test Mode with resume: ...... ENABLED') Cyan
        }
        else {
            Write-ColorText('Automatic Test Mode: .................. ENABLED') Cyan
        }

        if ($useCurveOptimizer) {
            Write-ColorText('Starting Curve Optimizer values: ...... ' + ($voltageStartingValues -Join ', ')) Cyan
        }

        if ($useIntelVoltageAdjustment) {
            Write-ColorText('Starting voltage offset value: ....... ' + $voltageStartingValues[0] + 'mv') Cyan
        }
    }


    if ($settings.mode -eq 'CUSTOM') {
        Write-ColorText('') Cyan
        Write-ColorText('Custom Prime95 settings:') Cyan
        Write-ColorText('────────────────────────────────────────────────────────────────────────────────') Cyan
        Write-ColorText('CpuSupportsAVX    = ' + $settings.Prime95Custom.CpuSupportsAVX) Cyan
        Write-ColorText('CpuSupportsAVX2   = ' + $settings.Prime95Custom.CpuSupportsAVX2) Cyan
        Write-ColorText('CpuSupportsFMA3   = ' + $settings.Prime95Custom.CpuSupportsFMA3) Cyan
        Write-ColorText('CpuSupportsAVX512 = ' + $settings.Prime95Custom.CpuSupportsAVX512) Cyan
        Write-ColorText('MinTortureFFT     = ' + $settings.Prime95Custom.MinTortureFFT) Cyan
        Write-ColorText('MaxTortureFFT     = ' + $settings.Prime95Custom.MaxTortureFFT) Cyan
        Write-ColorText('TortureMem        = ' + $settings.Prime95Custom.TortureMem) Cyan
        Write-ColorText('TortureTime       = ' + $settings.Prime95Custom.TortureTime) Cyan
    }

    Write-Text('')
    Write-ColorText('────────────────────────────────────────────────────────────────────────────────') Cyan


    # Display the log file location(s)
    $leftStringLength = $(if ($stressTestLogFileName) { [Math]::Max(10, $stressTestPrograms[$settings.General.stressTestProgram]['displayName'].Length) + 5 } else { 15 })

    Write-ColorText('The log files for this run are stored in:') Cyan
    Write-ColorText($logFilePathAbsolute) Cyan
    Write-ColorText((' - CoreCycler:').PadRight($leftStringLength, ' ') + $logFileName) Cyan

    if ($stressTestLogFileName) {
        Write-ColorText((' - ' + $stressTestPrograms[$settings.General.stressTestProgram]['displayName'] + ':').PadRight($leftStringLength, ' ') + $stressTestLogFileName) Cyan
    }

    Write-ColorText('────────────────────────────────────────────────────────────────────────────────') Cyan
    Write-Text('')


    # Print a message if we have set some debug settings
    if (
        ($stressTestProgramPriority.ToLowerInvariant() -ne $stressTestProgramPriorityDefault.ToLowerInvariant()) -or
        ($stressTestProgramWindowToForeground -ne $stressTestProgramWindowToForegroundDefault) -or
        ($disableCpuUtilizationCheck -ne $disableCpuUtilizationCheckDefault -or $showNoteForDisableCpuUtilization) -or
        ($useWindowsPerformanceCountersForCpuUtilization -ne $useWindowsPerformanceCountersForCpuUtilizationDefault) -or
        ($enableCpuFrequencyCheck -ne $enableCpuFrequencyCheckDefault) -or
        ($tickInterval -ne $tickIntervalDefault) -or
        ($delayFirstErrorCheck -ne $delayFirstErrorCheckDefault) -or
        ($suspensionTime -ne $suspensionTimeDefault) -or
        ($modeToUseForSuspension.ToLowerInvariant() -ne $modeToUseForSuspensionDefault.ToLowerInvariant())
    ) {
        $debugSettingsActive = $true
        Write-ColorText('────────────────────────────────────────────────────────────────────────────────') Magenta
        Write-ColorText('Enabled debug settings:') Magenta
    }

    if ($stressTestProgramPriority.ToLowerInvariant() -ne $stressTestProgramPriorityDefault.ToLowerInvariant()) {
        Write-ColorText('Stress test program priority: ......... ' + $stressTestProgramPriority) Magenta
    }
    if ($stressTestProgramWindowToForeground -ne $stressTestProgramWindowToForegroundDefault) {
        Write-ColorText('Stress test program to foreground: .... ' + ($(if ($stressTestProgramWindowToForeground) { 'TRUE' } else { 'FALSE' }))) Magenta
    }
    if ($disableCpuUtilizationCheck -ne $disableCpuUtilizationCheckDefault) {
        Write-ColorText('Disabled CPU utilization check: ....... ' + ($(if ($disableCpuUtilizationCheck) { 'TRUE' } else { 'FALSE' }))) Magenta
    }
    if ($useWindowsPerformanceCountersForCpuUtilization -ne $useWindowsPerformanceCountersForCpuUtilizationDefault) {
        Write-ColorText('Use Windows Performance Counters: ..... ' + ($(if ($useWindowsPerformanceCountersForCpuUtilization) { 'TRUE' } else { 'FALSE' }))) Magenta
    }
    if ($enableCpuFrequencyCheck -ne $enableCpuFrequencyCheckDefault) {
        Write-ColorText('Enabled CPU frequency check: .......... ' + ($(if ($enableCpuFrequencyCheck) { 'TRUE' } else { 'FALSE' }))) Magenta
    }
    if ($tickInterval -ne $tickIntervalDefault) {
        Write-ColorText('Tick interval: ........................ ' + $tickInterval) Magenta
    }
    if ($delayFirstErrorCheck -ne $delayFirstErrorCheckDefault) {
        Write-ColorText('Delay first error check: .............. ' + $delayFirstErrorCheck) Magenta
    }
    if ($suspensionTime -ne $suspensionTimeDefault) {
        Write-ColorText('Suspension time: ...................... ' + $suspensionTime) Magenta
    }
    if ($modeToUseForSuspension.ToLowerInvariant() -ne $modeToUseForSuspensionDefault.ToLowerInvariant()) {
        Write-ColorText('Method used to suspend: ............... ' + (Get-Culture).TextInfo.ToTitleCase($modeToUseForSuspension)) Magenta
    }

    if ($debugSettingsActive) {
        Write-ColorText('────────────────────────────────────────────────────────────────────────────────') Magenta
        Write-Text('')
    }



    # If the selected stress test program requires the CPU usage to be checked to detect errors, but the debug setting to do so is disabled
    # (This is the default setting now)
    if ($showNoteForDisableCpuUtilization) {
        Write-Text('')
        Write-Text('')
        Write-ColorText('┌──────────────────────────────────┤ NOTICE ├──────────────────────────────────┐') Black Cyan
        Write-ColorText('│ ' + 'With the selected stress test program errors can only be detected by'.PadRight(76, ' ') + ' │') Black Cyan
        Write-ColorText('│ ' + 'checking the CPU utilization, but "disableCpuUtilizationCheck" is set to 1'.PadRight(76, ' ') + ' │') Black Cyan
        Write-ColorText('│ ' + 'in the config file.'.PadRight(76, ' ') + ' │') Black Cyan
        Write-ColorText('│ ' + 'Setting it to 0 so that the program can be used.'.PadRight(76, ' ') + ' │') Black Cyan
        Write-ColorText('└──────────────────────────────────────────────────────────────────────────────┘') Black Cyan
        Write-Text('')
        Write-Text('')
    }


    if ($showPrime95NewWarning) {
        Write-Text('')
        Write-Text('')
        Write-ColorText('┌─────────────────────────────────┤ IMPORTANT ├────────────────────────────────┐') Yellow DarkRed
        Write-ColorText('│ ' + 'You''re using a Prime95 version that has not yet been tested with CoreCycler.'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + 'Some settings may have changed, which may cause it to act unpredictable,'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + 'or even prevent it from working at all.'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('└──────────────────────────────────────────────────────────────────────────────┘') Yellow DarkRed
        Write-Text('')
        Write-Text('')
    }



    # Inform the user about the experimental >64 core functionality
    if ($hasMoreThan64Cores) {
        Write-Text('')
        Write-Text('')
        Write-ColorText('┌─────────────────────────────────┤ IMPORTANT ├────────────────────────────────┐') Yellow DarkRed
        Write-ColorText('│ ' + 'Your system seems to have more than 64 logical cores.'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + 'Windows splits up large core amounts into multiple "Processor Groups".'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + 'An experimental feature has been enabled to test any core beyond 64.'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + 'Please report any problems you notice at:'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + 'https://github.com/sp00n/corecycler/issues'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + ''.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + ('Detected processor: ' + $processor.Name).PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + ('Detected number of physical cores: ' + $numPhysCores).PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + ('Detected number of logical cores:  ' + $numLogicalCores).PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('└──────────────────────────────────────────────────────────────────────────────┘') Yellow DarkRed
        Write-Text('')
        Write-Text('')
    }



    if ($hasAsymmetricCoreThreads -and $isPrime95 -and $settings.General.numberOfThreads -gt 1 -and !$settings.General.restartTestProgramForEachCore -and $useAutomaticRuntimePerCore) {
        Write-Text('')
        Write-Text('')
        Write-ColorText('┌──────────────────────────────────┤ NOTICE ├──────────────────────────────────┐') Yellow DarkRed
        Write-ColorText('│ ' + 'You have selected Prime95 as the test program and enabled testing with two'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + 'threads and an automatic runtime per core.'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + 'Your processor seems to have an architecture where some of its cores support'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + 'two and others support only a single thread (i.e. Intel big.LITTLE).'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + 'This may interfere with the automatic progress detection, and so it could'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + 'take very long to finish a core test, or it may not even finish at all.'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + ''.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + 'To work around this problem you could do the following:'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + '- Let the stress test program be restarted after each core'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + '- Set a fixed runtime per core'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + '- Separately test the cores with two and those with only one thread'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + '- Switch to testing with only one thread altogether'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('└──────────────────────────────────────────────────────────────────────────────┘') Yellow DarkRed
        Write-Text('')
        Write-Text('')
    }



    if ($useAutomaticTestModeWithResume) {
        Write-Text('')
        Write-Text('')
        Write-ColorText('┌─' + '────────────────────────────────┤ IMPORTANT ├───────────────────────────────' + '─┐') Yellow DarkRed
        Write-ColorText('│ ' + 'You have enabled the Automatic Test Mode with resume after reboot.'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + 'This creates a Scheduled Task that is scheduled to run at the next logon,'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + 'which will automatically resume the test process after a reboot / crash.'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + ''.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + 'In order to prevent the script from being started during a "regular" reboot,'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + 'please abort the CoreCycler script only by using CTRL+C (or by letting it'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + 'finish on its own).'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + 'Do NOT just close the window before the script has had a chance to exit,'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + 'otherwise the Scheduled Task will not be deleted!'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + ''.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + 'The name of the Scheduled Task is:'.PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + ('"' + $autoModeTaskName + '" and can be found within the').PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('│ ' + ('"' + $autoModeTaskPath + '" folder of the Task Scheduler Library.').PadRight(76, ' ') + ' │') Yellow DarkRed
        Write-ColorText('└─' + '────────────────────────────────────────────────────────────────────────────' + '─┘') Yellow DarkRed
        Write-Text('')
        Write-ColorText('┌─' + '────────────────────────────────────────────────────────────────────────────' + '─┐') Yellow DarkMagenta
        Write-ColorText('│ ' + 'Please note that the Curve Optimizer / voltage adjustments made here are not'.PadRight(76, ' ') + ' │') Yellow DarkMagenta
        Write-ColorText('│ ' + 'permanent and will be reverted once you restart the computer.'.PadRight(76, ' ') + ' │') Yellow DarkMagenta
        Write-ColorText('│ ' + 'So once you''ve found your final settings, you should add them to your BIOS.'.PadRight(76, ' ') + ' │') Yellow DarkMagenta
        Write-ColorText('└─' + '────────────────────────────────────────────────────────────────────────────' + '─┘') Yellow DarkMagenta
        Write-Text('')
        Write-Text('')
    }



    # There's an update available
    if ($showUpdateAvailableMessage) {
        Write-Text('')
        Write-Text('')
        Write-ColorText('┌─────────────────────────────┤ UPDATE AVAILABLE ├─────────────────────────────┐') Black Green
        Write-ColorText('│ ' + 'There''s an update available for CoreCycler!'.PadRight(76, ' ') + ' │') Black Green
        Write-ColorText('│ ' + ('Your current version: v' + $version).PadRight(76, ' ') + ' │') Black Green
        Write-ColorText('│ ' + ('The latest version:   ' + $updateCheckResult['version']).PadRight(76, ' ') + ' │') Black Green
        Write-ColorText('│ ' + 'You can find the new version here:'.PadRight(76, ' ') + ' │') Black Green
        Write-ColorText('│ ' + ($updateCheckResult['url']).PadRight(76, ' ') + ' │') Black Green
        Write-ColorText('└──────────────────────────────────────────────────────────────────────────────┘') Black Green
        Write-Text('')
        Write-Text('')
    }


    # Add the Windows Event Log Source if we want to use the Event Log
    if ($settings.Logging.useWindowsEventLog) {
        if (!(Test-EventLogService)) {
            Exit-WithFatalError -text ('"[Logging] useWindowsEventLog" was set to 1, but the Windows Event Log service is not running!')
        }

        Add-AppEventLogSource
    }


    if ($canUseWindowsEventLog) {
        $infoString  = 'The log files for this run are stored in:' + [Environment]::NewLine
        $infoString += $logFilePathAbsolute + $logFileName + [Environment]::NewLine

        if ($stressTestLogFileName) {
            $infoString += $logFilePathAbsolute + $stressTestLogFileName + [Environment]::NewLine
        }

        $infoString += [Environment]::NewLine
        $infoString += ('Stress test program: ' + $selectedStressTestProgram.ToUpperInvariant() + [Environment]::NewLine)
        $infoString += ('Selected test mode: ' + $settings.mode.ToUpperInvariant() + [Environment]::NewLine)
        $infoString += ('Selected number of threads: ' + $settings.General.numberOfThreads + [Environment]::NewLine)

        if ($settings.General.numberOfThreads -eq 1) {
            $infoString += ('Assign both cores to stress thread: ' + ($(if ($settings.General.assignBothVirtualCoresForSingleThread) { 'ENABLED' } else { 'DISABLED' })) + [Environment]::NewLine)
        }

        $infoString += ('Runtime per core: ' + (Get-FormattedRuntimePerCoreString $settings.General.runtimePerCore).ToUpperInvariant() + [Environment]::NewLine)
        $infoString += ('Suspend periodically: ' + ($(if ($settings.General.suspendPeriodically) { 'ENABLED' } else { 'DISABLED' })) + [Environment]::NewLine)
        $infoString += ('Restart for each core: ' + ($(if ($settings.General.restartTestProgramForEachCore) { 'ENABLED' } else { 'DISABLED' })) + [Environment]::NewLine)
        $infoString += ('Test order of cores: ' + $settings.General.coreTestOrder.ToUpperInvariant() + $(if ($settings.General.coreTestOrder.ToLowerInvariant() -eq 'default') { ' (' + $coreTestOrderMode.ToUpperInvariant() + ')' }) + [Environment]::NewLine)
        $infoString += ('Number of iterations: ' + $settings.General.maxIterations + [Environment]::NewLine)

        # Print a message if we're ignoring certain cores
        if ($settings.General.coresToIgnore.Count -gt 0) {
            $infoString += 'Ignored cores: ' + $coresToIgnoreString
        }


        Write-AppEventLog -type 'script_started' -infoString1 $infoString
    }


    # Start the stress test program
    Start-StressTestProgram


    # Try to get the affinity of the stress test program process. If not found, abort
    try {
        $null = $stressTestProcess.ProcessorAffinity
    }
    catch {
        Exit-WithFatalError -text ('Process ' + $processName + ' not found!')
    }


    # If Aida64 was started, try to clear any error messages from previous runs
    if ($isAida64) {
        Write-VerboseText('Trying to clear Aida64 error messages from previous runs')

        $initFunctions = [scriptblock]::Create(@"
            function Send-CommandToAida64 { ${function:Send-CommandToAida64} }
            function Write-VerboseText { ${function:Write-VerboseText} }
"@)

        $null = Start-Job -ScriptBlock {
            Start-Sleep -Seconds 3

            # Send the command a couple of times
            # Unfortunately we cannot get any Write-VerboseText without adding a Wait-Job
            for ($i = 0; $i -lt 3; $i++) {
                Send-CommandToAida64 'dismiss'
                Start-Sleep -Milliseconds 500
            }
        } -InitializationScript $initFunctions
    }


    # All the cores in the system
    # Initialize it as an ArrayList, to be able to use .RemoveAt()
    #$allCores = @(0..($numPhysCores-1))
    [System.Collections.ArrayList] $allCores = @(0..($numPhysCores-1))
    [System.Collections.ArrayList] $coresToTest = $allCores.Clone()

    # If a custom test order was provided, override the available cores
    if ($coreTestOrderMode -eq 'custom') {
        [System.Collections.ArrayList] $coresToTest = $coreTestOrderCustom.Clone()
    }

    # Remove ignored cores
    [System.Collections.ArrayList] $coresToTest = @($coresToTest | Where-Object { $_ -notin $settings.General.coresToIgnore })


    # Add the previously tested core from before the reboot if we're in Automatic Test Mode with resume
    if ($useAutomaticTestModeWithResume -and $CoreFromAutoMode -gt -1) {
        Write-Text('')
        Write-ColorText('Apparently the computer crashed in the last run while testing core ' + $CoreFromAutoMode) Red
        Write-ColorText('Trying to resume the test process') Red

        Write-VerboseText('Adding core ' + $CoreFromAutoMode + ' to the front of the test array')
        [Void] $coresToTest.Insert(0, $CoreFromAutoMode)

        $modeDescription = $(if ($useCurveOptimizer) { 'Curve Optimizer' } else { 'voltage offset' })
        Write-VerboseText('Adjusting the ' + $modeDescription + ' voltage value')

        # We need to pass empty values at this point, as we're only adjusting the starting values
        $params = @{
            'mode'             = 'RESUME'
            'actualCoreNumber' = $CoreFromAutoMode
        }

        Test-AutomaticTestModeIncrease @params
    }

    Write-VerboseText('All cores that could be tested:')
    Write-VerboseText($allCores -Join ', ')
    Write-VerboseText('The preliminary test order:')
    Write-VerboseText($coresToTest -Join ', ')


    # Start with the CPU test
    # Repeat the whole check $settings.General.maxIterations times
    for ($iteration = 1; $iteration -le $settings.General.maxIterations; $iteration++) {
        $timestamp = Get-Date -Format HH:mm:ss

        # Define the available cores
        [System.Collections.ArrayList] $coreTestOrderArray = $coresToTest.Clone()

        $halfCores               = $numPhysCores / 2
        $numAvailableCores       = $coreTestOrderArray.Count
        $numUniqueAvailableCores = @($coreTestOrderArray | Sort-Object | Get-Unique).Count
        $numCoresWithError       = $coresWithError.Count
        $numCoresWithWheaError   = $coresWithWheaError.Count
        $previousCoreNumber      = $null


        # Check if all of the cores have thrown an error, and if so, abort
        # Only if the skipCoreOnError setting is set
        # Cores can show up multiple times in the $coreTestOrderArray, so we're only using a the unique entries
        if (!$useAutomaticTestMode -and $settings.General.skipCoreOnError -and $numCoresWithError -gt 0 -and $numCoresWithError -eq $numUniqueAvailableCores) {
            # Also close the stress test program process to not let it run unnecessarily
            Close-StressTestProgram

            Write-ColorText($timestamp + ' - All Cores have thrown an error, aborting!') Yellow
            Exit-Script
        }


        # Show a different error message if we're using Automatic Test Mode and all cores have reached their maximum value
        if ($useAutomaticTestMode -and $numCoresWithErrorAndMaxVoltageValue -gt 0 -and $numCoresWithErrorAndMaxVoltageValue -eq $numUniqueAvailableCores) {
            Close-StressTestProgram

            $autoModeDescription = $(if ($useCurveOptimizer) { 'Curve Optimizer' } elseif ($useIntelVoltageAdjustment) { 'voltage offset' })

            Write-ColorText($timestamp + ' - All Cores have reached the maximum ' + $autoModeDescription + ' value and thrown an error, aborting!') Yellow
            Exit-Script
        }


        # Global counter
        $Script:startedIterations++


        Write-Text('')
        Write-ColorText($timestamp + ' - Iteration ' + $iteration) Yellow
        Write-ColorText('════════════════════════════════════════════════════════════════════════════════') Yellow



        Write-DebugText('The initial test order:')
        Write-DebugText($coreTestOrderArray -Join ', ')

        Write-DebugText('The initial number of available cores:        ' + $numAvailableCores)
        Write-DebugText('The initial number of unique available cores: ' + $numUniqueAvailableCores)



        # Build the available cores array for the various core test orders
        # We're leaving it in this loop because for random we want a different order on each iteration
        # and I like to have it all in one place instead of scattered around different places
        # None of these actually change the number and unique number of cores, at best only re-arranges them
        # Important for the $numAvailableCores and $numUniqueAvailableCores variable
        if ($coreTestOrderMode -eq 'alternate') {
            Write-VerboseText('Alternating test order selected, building the test order array...')

            # Start fresh
            $coreTestOrderArray = [System.Collections.ArrayList]::new()

            # If we had added a core from CoreFromAutoMode, we will need to push it to the front here again
            if ($useAutomaticTestModeWithResume -and $CoreFromAutoMode -gt -1) {
                [Void] $coreTestOrderArray.Add($CoreFromAutoMode)
            }

            # 0, $halfCores, 0+1, $halfCores+1, ...
            # TODO: Maybe find a better way to handle ignored cores, so that there's still an alternation, instead of just skipping it
            for ($i = 0; $i -lt $numPhysCores; $i++) {
                $currentCoreNumber = 0

                if ($null -ne $previousCoreNumber) {
                    if ($previousCoreNumber -lt $halfCores) {
                        $currentCoreNumber = [Int] ($previousCoreNumber + $halfCores)
                    }
                    else {
                        $currentCoreNumber = [Int] ($previousCoreNumber - $halfCores + 1)
                    }
                }

                $previousCoreNumber = $currentCoreNumber


                if (!$settings.General.coresToIgnore.Contains($currentCoreNumber)) {
                    [Void] $coreTestOrderArray.Add($currentCoreNumber)
                }
            }
        }

        # Randomized
        elseif ($coreTestOrderMode -eq 'random') {
            Write-VerboseText('Random test order selected, building the test order array...')

            # Only unique cores for the random order
            [System.Collections.ArrayList] $coreTestOrderArray = @(@($coreTestOrderArray) | Sort-Object -Unique | Sort-Object { Get-Random })

            Write-DebugText('The randomized test order:')
            Write-DebugText($coreTestOrderArray -Join ', ')

            # If we had added a core from CoreFromAutoMode, push that core to the front
            if ($useAutomaticTestModeWithResume -and $CoreFromAutoMode -gt -1) {
                Write-VerboseText('Moving the passed core to the beginning of the test order')

                [System.Collections.ArrayList] $coreTestOrderArrayOri = $coreTestOrderArray.Clone()
                [System.Collections.ArrayList] $coreTestOrderArray = @()

                $coreTestOrderArrayOri | ForEach-Object {
                    if ([Int] $_ -eq [Int] $CoreFromAutoMode) {
                        [Void] $coreTestOrderArray.Insert(0, [Int] $_)
                    }
                    else {
                        [Void] $coreTestOrderArray.Add([Int] $_)
                    }
                }

                $numAvailableCores       = $coreTestOrderArray.Count
                $numUniqueAvailableCores = @($coreTestOrderArray | Sort-Object | Get-Unique).Count

                Write-VerboseText('The test order with the core moved to the front:')
                Write-VerboseText($coreTestOrderArray -Join ', ')
            }
        }

        # Custom
        elseif ($coreTestOrderMode -eq 'custom') {
            Write-VerboseText('Custom test order selected, keeping the test order array...')
            # This was set above already, no need to change it
            # It also already doesn't include the ignored cores
        }

        # Sequential, do nothing
        else {
            Write-VerboseText('Sequential test order selected, keeping the test order array...')
            # This was set above already, no need to change it
            # It also already doesn't include the ignored cores
        }

        Write-VerboseText('The final test order:')
        Write-VerboseText($coreTestOrderArray -Join ', ')

        Write-DebugText('The number of available cores:         ' + $numAvailableCores)
        Write-DebugText('The number of unique available cores:  ' + $numUniqueAvailableCores)
        Write-DebugText('The number of cores with an error:     ' + $numCoresWithError)
        Write-DebugText('The number of cores with a WHEA error: ' + $numCoresWithWheaError)


        if (@($coreTestOrderArray).Count -lt 1) {
            Exit-WithFatalError('No valid core to test selected!')
        }


        # Iterate over each core
        # Named for loop
        :LoopCoreRunner for ($coreIndex = 0; $coreIndex -lt $numAvailableCores; $coreIndex++) {
            Write-DebugText('Trying to switch to a new core (' + ($coreIndex+1) + ' of ' + $numAvailableCores + ') [index ' + $coreIndex + ' of ' + ($numAvailableCores-1) + ']')

            $startDateThisCore                   = Get-Date
            $estimatedEndDateCore                = $startDateThisCore + (New-TimeSpan -Seconds $runtimePerCore)
            $timestamp                           = $startDateThisCore.ToString('HH:mm:ss')
            $expectedAffinities                  = $()
            $actualCoreNumber                    = [Int] $coreTestOrderArray[0]      # The coreTestOrderArray is reduced for each iteration, so this will always get the next core in line
            $cpuNumbersArray                     = @()
            $allPassedFFTs                       = [System.Collections.ArrayList]::new()
            $uniquePassedFFTs                    = [System.Collections.ArrayList]::new()
            $allPassedTests                      = [System.Collections.ArrayList]::new()
            $uniquePassedTests                   = [System.Collections.ArrayList]::new()
            $proceedToNextCore                   = $false
            $fftSizeOverflow                     = $false
            $coreSupportsOnly1T                  = $coresWithOneThread.Contains($actualCoreNumber)
            $coreStartDifference                 = New-TimeSpan -Start $scriptStartDate -End $startDateThisCore
            $numCoresWithError                   = $coresWithError.Count
            $numCoresWithWheaError               = $coresWithWheaError.Count
            $numCoresWithIncreasedVoltageValue   = $coresWithIncreasedVoltageValue.Count
            $numCoresWithErrorAndMaxVoltageValue = $coresWithErrorAndMaxVoltageValue.Count


            # Store our currently tested core in a global variable
            $Script:currentlyTestedCore = $actualCoreNumber


            Write-VerboseText('Still available cores:')
            Write-VerboseText($coreTestOrderArray -Join ', ')
            Write-VerboseText('The selected core to test: ' + $actualCoreNumber)


            # If the processor has a different architecture between the cores
            # E.g. performance cores with 2 threads and efficient cores with only 1 thread (Intel)
            if ($hasAsymmetricCoreThreads -and $coreSupportsOnly1T) {
                # We also need to set the expected and minimum CPU usage at this point, to account for cores that only support one thread
                $factorForExpectedUsage    = 1                                              # Even for two threads, only one CPU will be loaded
                $expectedUsageTotal        = [Math]::Round($expectedUsagePerCore * $factorForExpectedUsage, 2)
                $minProcessUsage           = [Math]::Round($expectedUsageTotal * $lowerLimitForProcessUsage, 2)
                $factorForMinProcessorTime = $lowerLimitForProcessUsage * $factorForExpectedUsage

                # All previous coresWithTwoThreads * 2 + all previous coresWithOneThread * 1
                # We do assume that the cores with only one thread all appear after the cores with two threads

                # Two cores: [0, 1, 2, 3, 4, 5]         -> CPU [0,1 - 2,3 - 4,5 - 6,7 - 8,9 - 10,11]
                # One Core:  [6, 7, 8, 9]               -> CPU [12, 13, 14, 15]
                # Core: 8
                # Index: 2
                # CPU: (5+1) * 2 + 2 -> 12 + 2 -> 14

                $cpuNumber        = ($coresWithTwoThreads[-1] + 1) * 2 + [Array]::indexOf($coresWithOneThread, $actualCoreNumber)
                $cpuNumbersArray += $cpuNumber
            }


            # All cores support the same amount of threads (either one or two)
            else {
                # We also need to set the expected and minimum CPU usage at this point, to account for cores that only support one thread
                # This is the "default" calculation
                $factorForExpectedUsage    = $settings.General.numberOfThreads     # Either one or two CPUs are being fully used
                $expectedUsageTotal        = [Math]::Round($expectedUsagePerCore * $factorForExpectedUsage, 2)
                $minProcessUsage           = [Math]::Round($expectedUsageTotal * $lowerLimitForProcessUsage, 2)
                $factorForMinProcessorTime = $lowerLimitForProcessUsage * $factorForExpectedUsage   # Either 50% of 100% of the measure time


                # If the number of threads is more than 1
                if ($settings.General.numberOfThreads -gt 1) {
                    for ($currentThread = 0; $currentThread -lt $settings.General.numberOfThreads; $currentThread++) {
                        # We don't care about Hyperthreading / SMT here, it needs to be enabled for 2 threads
                        $cpuNumber        = ($actualCoreNumber * 2) + $currentThread
                        $cpuNumbersArray += $cpuNumber
                    }
                }

                # Only one thread
                else {
                    # assignBothVirtualCoresForSingleThread is enabled, we want to use both virtual cores, but with only one thread
                    # The load should bounce back and forth between the two cores this way
                    # Hyperthreading needs to be enabled for this
                    if ($settings.General.assignBothVirtualCoresForSingleThread -and $isHyperthreadingEnabled) {
                        Write-VerboseText('assignBothVirtualCoresForSingleThread is enabled, choosing both virtual cores for the affinity')

                        for ($currentThread = 0; $currentThread -lt 2; $currentThread++) {
                            $cpuNumber        = ($actualCoreNumber * 2) + $currentThread
                            $cpuNumbersArray += $cpuNumber
                        }

                        # We shouldn't need to set minProcessUsage and factorForMinProcessorTime here, because this is only active for 1 numberOfThreads
                    }

                    # Setting not active, only one core for the load thread
                    else {
                        # If Hyperthreading / SMT is enabled, the tested CPU number is 0, 2, 4, etc
                        # Otherwise, it's the same value
                        $cpuNumber        = $actualCoreNumber * (1 + [Int] $isHyperthreadingEnabled)
                        $cpuNumbersArray += $cpuNumber
                    }
                }
            }


            # Always try to avoid CPU 0 for single threads if Hyperthreading is enabled, switch to CPU 1 instead
            if ($cpuNumbersArray[0] -eq 0 -and $cpuNumbersArray.Count -eq 1 -and $isHyperthreadingEnabled) {
                Write-VerboseText('Trying to avoid Core 0 / CPU 0, as this is mainly used by the OS')
                Write-VerboseText('Setting to CPU 1 instead, which is the second virtual CPU of Core 0')
                $cpuNumbersArray[0] = 1
            }


            $cpuNumberString = (($cpuNumbersArray | Sort-Object) -Join ' and ')


            # Skip if this core is in the ignored cores array
            # Note: This shouldn't happen anymore, as we have removed the cores from the availableCores array
            if ($settings.General.coresToIgnore -contains $actualCoreNumber) {
                # Ignore it silently
                Write-VerboseText('Core ' + $actualCoreNumber + ' (CPU ' + $cpuNumberString + ') is being ignored, skipping')

                # Remove this core from the array of still available cores
                [Void] $coreTestOrderArray.RemoveAt(0)
                continue
            }


            # Skip if this core is stored in the error core array and the flag is set
            if (!$useAutomaticTestMode -and $settings.General.skipCoreOnError -and $coresWithError -contains $actualCoreNumber) {
                Write-Text($timestamp + ' - Core ' + $actualCoreNumber + ' (CPU ' + $cpuNumberString + ') has previously thrown an error, skipping')

                # Remove this core from the array of still available cores
                [Void] $coreTestOrderArray.RemoveAt(0)
                continue
            }


            # Also skip this core if the maximum Curve Optimizer / voltage offset value has been reached
            if ($useAutomaticTestMode -and $settings.General.skipCoreOnError -and $coresWithErrorAndMaxVoltageValue -contains $actualCoreNumber) {
                Write-Text($timestamp + ' - Core ' + $actualCoreNumber + ' (CPU ' + $cpuNumberString + ') has reached the maximum value and has previously thrown an error, skipping')

                # Remove this core from the array of still available cores
                [Void] $coreTestOrderArray.RemoveAt(0)
                continue
            }



            # Apparently Aida64 doesn't like having the affinity set to 1
            # Possible workaround: Set it to 2 instead
            # This also poses a problem when testing two threads on core 0, so we're skipping this core for the time being
            if ($isAida64 -and $cpuNumbersArray[0] -eq 0 -and $cpuNumbersArray.Count -eq 1) {
                Write-ColorText('           Notice!') Black Yellow

                # If Hyperthreading / SMT is enabled
                # Note: this should already be handled above, we're trying to avoid CPU 0 altogether now
                if ($isHyperthreadingEnabled) {
                    Write-ColorText('           Apparently Aida64 doesn''t like running the stress test on the first thread of Core 0.') Black Yellow
                    Write-ColorText('           Setting it to thread 2 of Core 0 instead (Core 0 / CPU 1).') Black Yellow

                    $cpuNumbersArray[0] = 1
                    $cpuNumberString = 1
                }

                # For disabled Hyperthreading / SMT, there's not much we can do. So skipping it
                else {
                    Write-ColorText('           Apparently Aida64 doesn''t like running the stress test on Core 0 only.') Black Yellow
                    Write-ColorText('           Normally we''d fall back to thread 2 on Core 0, but since Hyperthreading / SMT is disabled, we cannot do this.') Black Yellow
                    Write-ColorText('           Therefore we''re skipping this core.') Black Yellow

                    Write-VerboseText('Skipping this core due to Aida64 not running correctly on Core 0 / CPU 0 and Hyperthreading / SMT is disabled')

                    # Remove this core from the array of still available cores
                    [Void] $coreTestOrderArray.RemoveAt(0)
                    continue
                }
            }

            # Aida64 running on CPU 0 and CPU 1 (2 threads)
            elseif ($isAida64 -and $cpuNumbersArray[0] -eq 0 -and $cpuNumbersArray.Count -eq 2) {
                Write-ColorText('           Notice!') Black Yellow
                Write-ColorText('           Apparently Aida64 doesn''t like running the stress test on the first thread of Core 0 (= CPU 0).') Black Yellow
                Write-ColorText('           You might see an error with "CPU usage too low" due to this.') Black Yellow
            }


            # All checks if this core can be tested have completed, we can now increase the number of started tests
            $numberOfStartedTests++


            # If $settings.General.restartTestProgramForEachCore is set, restart the stress test program for each core
            # Do not restart before the first core on the first iteration has been tested though
            if ($settings.General.restartTestProgramForEachCore -and $numberOfStartedTests -gt 1) {
                Write-VerboseText('restartTestProgramForEachCore is set, restarting the stress test program...')

                # Set the flag to only stop the stress test program if possible
                Close-StressTestProgram $true

                # If the delayBetweenCores setting is set, wait for the defined amount
                if ($settings.General.delayBetweenCores -gt 0) {
                    Write-Text('           Idling for ' + $settings.General.delayBetweenCores + ' seconds before proceeding to the next core...')

                    # Also adjust the expected end time for this delay
                    $estimatedEndDateCore += New-TimeSpan -Seconds $settings.General.delayBetweenCores

                    Start-Sleep -Seconds $settings.General.delayBetweenCores
                }


                # If we've set to use two threads and the processor has cores that don't support two threads, set the config file accordingly before starting the stress test process
                if ($settings.General.numberOfThreads -gt 1 -and $hasAsymmetricCoreThreads) {
                    Write-DebugText('The processor has cores that don''t support two threads')
                    Write-DebugText('Modifying the stress test config file accordingly before restarting')

                    $overrideNumberOfThreads = $(if ($coreSupportsOnly1T) { 1 } else { 2 })

                    Initialize-StressTestProgram $overrideNumberOfThreads

                    # Set the flag to only restart the stress test process? - Currently only applies to Aida64 though
                    # If the stress test program supports restarting only the process for the stress test,
                    # we should not set the flag here, so that we can properly switch between one and two threads (= $false).
                    # However, Aida64 is currently the only program that supports this, and it always starts 4 threads,
                    # so we don't need to restart the whole program
                    Start-StressTestProgram $true $overrideNumberOfThreads
                }


                # Regular behavior, all the cores support the requested number of threads (i.e. 1 or 2)
                else {
                    # Set the flag to only start the stress test program if possible
                    Start-StressTestProgram $true
                }
            }


            # Remove this core from the array of still available cores
            [Void] $coreTestOrderArray.RemoveAt(0)


            # This core has not thrown an error yet, run the test
            $startCoreDate = Get-Date
            $timestamp = $startCoreDate.ToString('HH:mm:ss')
            $coreString = $actualCoreNumber.ToString() + ' (CPU ' + $cpuNumberString + ')'
            Write-Text($timestamp + ' - Set to Core ' + $coreString)


            # Global variables
            $Script:numTestedCores++

            if (!$Script:testedCoresArray[$actualCoreNumber]) {
                $Script:testedCoresArray[$actualCoreNumber] = 0
            }

            $Script:testedCoresArray[$actualCoreNumber]++


            # Set the .automode file if we're in Automatic Test Mode with resuming
            if ($useAutomaticTestModeWithResume) {
                Set-AutoModeFile $actualCoreNumber
            }


            if ($canUseWindowsEventLog) {
                Write-AppEventLog -type 'core_started' -infoString1 $coreString
            }


            if ($coreSupportsOnly1T) {
                Write-VerboseText('!!! This core supports only one thread')

                # Prime95 doesn't play too well with 2 threads selected but only 1 available (e.g. Intel's E-Core)
                if ($settings.General.numberOfThreads -gt 1 -and $isPrime95 -and !$settings.General.restartTestProgramForEachCore -and $useAutomaticRuntimePerCore) {
                    Write-ColorText('           Notice!') Black Yellow
                    Write-ColorText('           This core seems to support only one thread, but testing with two threads has been configured.') Black Yellow
                    Write-ColorText('           The FFT detection will be thrown off by this, so it may take very long to finish this test,') Black Yellow
                    Write-ColorText('           or it may even not finish at all.') Black Yellow
                    Write-ColorText('           Additionally the tests for the following cores may also be affected by this.') Black Yellow
                    Write-ColorText('           See the notice at the start of the script for possible ways around this.') Black Yellow
                }
            }


            # Set the affinity to a specific core
            try {
                $expectedAffinities = Set-StressTestProgramAffinities $cpuNumbersArray
            }
            catch {
                # Apparently setting the affinity can fail on the first try, so make another attempt
                Write-VerboseText('Setting the affinity has failed, trying again...')
                Write-VerboseText('Error: ' + $_)

                Start-Sleep -Milliseconds 300

                try {
                    $expectedAffinities = Set-StressTestProgramAffinities $cpuNumbersArray
                }
                catch {
                    Close-StressTestProgram
                    Exit-WithFatalError -text ('Could not set the affinity to Core ' + $coreString + '!')
                }
            }


            # Check if the affinities were set correctly
            $checkingAffinities = Get-StressTestProgramAffinities

            # We may have changed from a core that supports two threads to a core that only supports one
            # In this case the checkingAffinities array only has one entry
            # Get-Unique returns a single integer if there's only one array entry, so we're specifically wrapping it inside a new array
            $affinitiesMatch = [bool]($null -eq (Compare-Object -ReferenceObject @($expectedAffinities | Sort-Object | Get-Unique) -DifferenceObject @($checkingAffinities | Sort-Object | Get-Unique)))

            if (!$affinitiesMatch) {
                Write-VerboseText('The affinity could NOT be set correctly!')
                Write-VerboseText(' - affinities trying to set: ' + $expectedAffinities)
                Write-VerboseText(' - actual affinities:        ' + $checkingAffinities)

                Exit-WithFatalError -text 'The affinities could not be set correctly!'
            }


            # Set the voltage for the currently selected core
            if ($setVoltageOnlyForTestedCore) {
                Write-VerboseText('Setting the voltage for the currently tested code')
                Set-NewVoltageValues
            }


            # Change the title
            $Host.ui.RawUI.WindowTitle = 'CoreCycler: Core ' + $actualCoreNumber


            # Set the process priority
            try {
                # PriorityClass values:
                # Idle
                # BelowNormal
                # Normal
                # AboveNormal
                # High
                # RealTime
                # $stressTestProcess.PriorityClass = 'High'
                # $stressTestProcess.PriorityClass = 'Idle'
                $stressTestProcess.PriorityClass = $stressTestProgramPriority

                # There's also a "SetPriority" property, which seems to be a WMI only property
                # Possible values:
                #    64 - Low
                # 16384 - Below normal
                #    32 - Normal
                # 32768 - Above normal
                #   128 - High
                #   256 - Realtime
                #
                # Return codes:
                #  0  - Successful completion
                #  2  - Access denied
                #  3  - Insufficient privilege
                #  8  - Unknown failure
                #  9  - Path not found
                # 21  - Invalid parameter
                # 22+ - Other

                # Get-CimInstance -ClassName win32_process -Filter 'Name="prime95.exe"'
                # $wmiStressTestProcess = Get-CimInstance -ClassName win32_process -Filter ('Handle="' + $stressTestProcess.Id + '"')
                # $setPriority = $wmiStressTestProcess.SetPriority(128)
                # $setPriority.ReturnValue
            }
            catch {
                Close-StressTestProgram
                Exit-WithFatalError -text 'Could not set the priority of the stress test process!'
            }

            # If this core is stored in the error core array and the skipCoreOnError setting is not set, display the amount of errors
            if (!$settings.General.skipCoreOnError -and $coresWithError -contains $actualCoreNumber) {
                $text  = '           Note: This core has previously thrown ' + $coresWithErrorsCounter[$actualCoreNumber] + ' error'
                $text += $(if ($coresWithErrorsCounter[$actualCoreNumber] -gt 1) { 's' })

                Write-Text($text)
            }

            if ($useAutomaticRuntimePerCore) {
                if ($isPrime95) {
                    Write-Text('           Running until all FFT sizes have been tested...')
                }
                elseif ($isYCruncherWithLogging) {
                    $estimatedRuntime = Get-EstimatedYCruncherRuntimePerCore
                    $formattedEstimatedTime = Get-FormattedRuntimePerCoreString $estimatedRuntime
                    Write-Text('           Running until all selected tests have been completed (around ' + $formattedEstimatedTime + ')...')
                }
            }
            else {
                Write-Text('           Running for ' + (Get-FormattedRuntimePerCoreString $settings.General.runtimePerCore) + '...')
            }


            # Get the current progress (core, iteration, total runtime)
            $totalRuntimeArray = @()

            if ($coreStartDifference.Days -gt 0) {
                $totalRuntimeArray += ($coreStartDifference.Days.ToString() + 'd')
            }

            $totalRuntimeArray += ($coreStartDifference.Hours.ToString().PadLeft(2, '0') + 'h')
            $totalRuntimeArray += ($coreStartDifference.Minutes.ToString().PadLeft(2, '0') + 'm')
            $totalRuntimeArray += ($coreStartDifference.Seconds.ToString().PadLeft(2, '0') + 's')
            $totalRunTimeString = $totalRuntimeArray -Join ' '

            Write-ColorText('           Progress ' + ($coreIndex+1) + '/' + $numAvailableCores + ' | Iteration ' + $iteration + '/' + $settings.General.maxIterations + ' | Runtime ' + $totalRunTimeString) DarkGray
            Write-DebugText('The number of cores with an error so far: ' + $numCoresWithError)

            if ($settings.General.lookForWheaErrors) {
                Write-DebugText('The number of cores with a WHEA error so far: ' + $numCoresWithWheaError)
            }

            # Make a check each x seconds
            # - to check the CPU power usage
            # - to check if all FFT sizes have passed
            # - to suspend and resume the stress test process
            for ($checkNumber = 1; $checkNumber -le $cpuCheckIterations; $checkNumber++) {
                $waitTime  = 0
                $timestamp = Get-Date -Format HH:mm:ss
                Write-DebugText('')
                Write-DebugText($timestamp + ' - Tick ' + $checkNumber + ' of max ' + $cpuCheckIterations)

                $nowDateTime         = Get-Date
                $differenceMax       = New-TimeSpan -Start $nowDateTime -End $estimatedEndDateCore
                $runtimeRemainingMax = [Math]::Round($differenceMax.TotalSeconds)

                Write-DebugText('           Remaining max runtime: ' + $runtimeRemainingMax + 's')

                # Make this the last iteration if the remaining time is close enough
                # Also reduce the sleep time here by 1 second, we add this back after suspending the stress test program
                if ($runtimeRemainingMax -le $tickInterval) {
                    $checkNumber = $cpuCheckIterations
                    $waitTime    = [Math]::Max(0, $runtimeRemainingMax - 2) # -2 instead of -1 due to the additional wait time after the suspension
                    Write-DebugText('           The remaining run time (' + $waitTime + ') is less than the tick interval (' + $tickInterval + ')')
                    Write-DebugText('           This will be the last interval')
                }
                else {
                    $waitTime = $tickInterval - 1
                }


                # Try to flush the disk write cache so that the log file is available in case of a crash
                if ($settings.Logging.flushDiskWriteCache -eq 1 -and $canUseFlushToDisk) {
                    Save-CachedDataToDisk
                }


                # Wait for the determined time
                if ($waitTime -gt 0) {
                    Start-Sleep -Seconds $waitTime
                }


                # Get the current CPU frequency if the setting to do so is enabled
                # According to some reports, this may interfere with Test-StressTestProgrammIsRunning, so it's disabled by default now
                if ($enableCpuFrequencyCheck) {
                    $currentCpuInfo = Get-CpuFrequency $cpuNumber
                    Write-VerboseText('           ...current CPU frequency: ~' + $currentCpuInfo.CurrentFrequency + ' MHz (' + $currentCpuInfo.Percent + '%)')
                }


                # Suspend and resume the stress test
                if ($settings.General.suspendPeriodically) {
                    $timestamp = Get-Date -Format HH:mm:ss
                    Write-DebugText($timestamp + ' - Suspending the stress test process for ' + $suspensionTime + ' milliseconds')

                    $suspended = Suspend-Process $stressTestProcess
                    Write-DebugText('           Suspended: ' + $suspended)

                    Start-Sleep -Milliseconds $suspensionTime

                    $timestamp = Get-Date -Format HH:mm:ss
                    Write-DebugText($timestamp + ' - Resuming the stress test process')

                    $resumed = Resume-Process -process $stressTestProcess
                    Write-DebugText('           Resumed: ' + $resumed)
                }


                # This is the additional sleep time after having suspended/resumed the stress test program
                # It's a failsafe for the CPU utilization check
                # We don't care if we're actually suspending or not
                Start-Sleep -Seconds 1


                # If we want to delay the first error check, do so, but keep in mind the remaining runtime (e.g. for very short runtimes)
                if ($delayFirstErrorCheck -and $checkNumber -eq 1) {
                    $nowDateTime         = Get-Date
                    $differenceMax       = New-TimeSpan -Start $nowDateTime -End $estimatedEndDateCore
                    $runtimeRemainingMax = [Math]::Round($differenceMax.TotalSeconds)


                    $timestamp = Get-Date -Format HH:mm:ss
                    Write-DebugText('')

                    if ($delayFirstErrorCheck -lt $runtimeRemainingMax) {
                        Write-DebugText($timestamp + ' - delayFirstErrorCheck has been set to ' + $delayFirstErrorCheck + 's, delaying...')
                        Start-Sleep -Seconds $delayFirstErrorCheck
                    }
                    else {
                        Write-DebugText($timestamp + ' - delayFirstErrorCheck has been set to ' + $delayFirstErrorCheck + 's,')
                        Write-DebugText('           but the remaining runtime for this core is less (' + $runtimeRemainingMax + 's), so ignoring')
                    }
                }


                # For Prime95, try to get the new log file entries
                # Also for y-cruncher with the logging wrapper
                # Also for Linpack
                # This sets the following variables:
                # - $previousFileSize -> [Int] The current file size of the log file (to check if it was updated since then)
                # - $lastFilePosition -> [Int] The position of the pointer within the log file
                # - $lineCounter      -> [Int] On which line of the log file we are
                # - $allLogEntries    -> [Array] All log entries
                # - $newLogEntries    -> [Array] All new log entries
                if ($isPrime95 -or $isYCruncherWithLogging -or $isLinpack) {
                    Get-NewLogfileEntries
                }


                # PRIME95
                # If the runtime per core is set to auto and we're running Prime95
                # We need to check if all the FFT sizes have been tested
                #
                # TODO:
                # There seems to be a problem with two threads, the FFT sizes sometimes seem to drift apart too much
                # and causes the test to never finish
                if ($useAutomaticRuntimePerCore -and $isPrime95) {
                    :LoopCheckForAutomaticRuntime while ($true) {
                        $timestamp = Get-Date -Format HH:mm:ss
                        $foundFFTSizeLines = @()

                        Write-DebugText($timestamp + ' - Automatic runtime per core selected')

                        # Only perform the check if the file size has increased
                        # The size has increased, so something must have changed
                        # It's either a new passed FFT entry, a [Timestamp], or an error
                        if ($newLogEntries.Count -le 0) {
                            Write-DebugText('           No new log file entries found')
                            break LoopCheckForAutomaticRuntime
                        }

                        # Check for an error, if we've found one, we don't even need to process any further
                        # Note: there is a potential to miss log entries this way
                        # However, since the script either stops at this point or the stress test program is restarted, we don't really need to worry about this
                        $errorResults = $newLogEntries | Where-Object { $_.Line -Match '.*error.*' }

                        if ($errorResults) {
                            Write-DebugText('           Found an error entry in the new log entries, proceed to the error check')
                            break LoopCheckForAutomaticRuntime
                        }


                        # Get only the passed FFTs lines
                        $lastPassedFFTSizeResults = $newLogEntries | Where-Object { $_.Line -Match '.*passed.*' }


                        # No passed FFT sizes found
                        if (!$lastPassedFFTSizeResults) {
                            Write-DebugText('           No passed FFT sizes found yet, assuming we''re at the very beginning of the test')
                            break LoopCheckForAutomaticRuntime
                        }


                        Write-DebugText('           The last passed FFT result lines:')
                        $lastPassedFFTSizeResults | ForEach-Object {
                            Write-DebugText('           - [Line ' + $_.LineNumber + '] ' + $_.Line)
                        }


                        # Check all the entries in the found FFT results
                        # There may have been some sort of hiccup in the result file generation or file check, where one FFT size is overlooked
                        # Start at the oldest line
                        foreach ($currentResultLineEntry in $lastPassedFFTSizeResults) {
                            # There's no previous entry, nothing to compare to
                            if (!$previousPassedFFTEntry) {
                                # Add it to the list whether it's a new FFT size or not, we're filtering later on for two threads
                                $foundFFTSizeLines += $currentResultLineEntry
                            }

                            # Not reached the line number of the last entry yet
                            elseif ($currentResultLineEntry.LineNumber -le $previousPassedFFTEntry.LineNumber) {
                                Write-DebugText('           Line number of previous entry not reached yet, skipping (Line ' + $currentResultLineEntry.LineNumber + ' <= ' + $previousPassedFFTEntry.LineNumber + ')')
                                continue
                            }

                            # A new line number has been reached
                            elseif ($currentResultLineEntry.LineNumber -gt $previousPassedFFTEntry.LineNumber) {
                                # If it's the same FFT size on a new line
                                # This could either be an expected double entry for 2 worker threads
                                # or a true back-to-back entry (or both)

                                # Add it to the list whether it's a new FFT size or not, we're filtering later on for two threads
                                $foundFFTSizeLines += $currentResultLineEntry
                            }
                        }


                        Write-DebugText('           All found FFT size lines ($foundFFTSizeLines):')
                        $foundFFTSizeLines | ForEach-Object {
                            Write-DebugText('           - [Line ' + $_.LineNumber + '] ' + $_.Line)
                        }


                        # Go through all newly found FFT entries
                        for ($currentLineIndex = 0; $currentLineIndex -lt $foundFFTSizeLines.Count; $currentLineIndex++) {
                            $currentResultLineEntry = $foundFFTSizeLines[$currentLineIndex]

                            # More recent Prime95 version add a "(thread x of y)" to the log output, which breaks the recognition
                            # Theoretically this would offer a new way to determine the failures, but it would require a larger rewrite
                            # So removing this is the lazy approach
                            # This log file format seems to depend on the "TortureHyperthreading" Prime95 setting
                            # Or not, it doesn't seem to appear anymore
                            $currentResultLineEntry.Line = $currentResultLineEntry.Line -Replace ' \(thread \d+ of \d+\)', ''

                            $insert = $false

                            Write-DebugText('')
                            Write-DebugText('Checking line ' + $currentResultLineEntry.LineNumber)
                            Write-DebugText(' -> ' + $currentResultLineEntry.Line)


                            # Check the log, depending on the selected amount of threads to be tested

                            # For one thread
                            # Or for two threads, but the core itself supports only one thread
                            # In the latter case, two threads will still run in Prime95, but we will consider every result of a thread as a successful pass,
                            # and don't wait for two passes (a "pair") of the same FFT size to be completed
                            if ($settings.General.numberOfThreads -eq 1 -or ($settings.General.numberOfThreads -gt 1 -and $coreSupportsOnly1T)) {
                                $insert = $true
                            }

                            # Two threads require a special treatment
                            # We're looking for a "pair" (i.e. two passes) of the same FFT sizes in the log
                            # But only if we're running on a core that actually supports two threads
                            # Otherwise it's handled like one thread (see above)
                            elseif ($settings.General.numberOfThreads -gt 1) {
                                $numLinesWithSameFFTSize = 1

                                # Does this line also appear in the last line of the log?
                                $curCheckIndex = $allFFTLogEntries.Count - 1

                                Write-DebugText(' -> $allFFTLogEntries.Count: ' + $allFFTLogEntries.Count)
                                Write-DebugText('           Looking for:  ' + $currentResultLineEntry.Line)

                                # For newer Prime95 versions, the lines do not match anymore
                                # Example:
                                # Self-test 4K (thread 2 of 2) passed!
                                # Self-test 4K (thread 1 of 2) passed!

                                # Go backwards through the log
                                # It may be that the FFT sizes do not immediately follow each other
                                # Limit the search area to x rows
                                $i = 0
                                $maxRowsToCheck = 6

                                while ($curCheckIndex -ge 0 -and $allFFTLogEntries[$curCheckIndex]) {
                                    $linesMatch = $currentResultLineEntry.Line -eq $allFFTLogEntries[$curCheckIndex].Line

                                    Write-DebugText('           Line ' + $curCheckIndex.ToString().PadLeft(6, ' ') + ':  ' + $allFFTLogEntries[$curCheckIndex].Line + '  -> Match: ' + $linesMatch)

                                    if ($linesMatch) {
                                        Write-DebugText('           Both lines match, increasing the numLinesWithSameFFTSize counter')
                                        $numLinesWithSameFFTSize++
                                        break
                                    }


                                    # Limit the search to x rows
                                    if ($i -eq $maxRowsToCheck) {
                                        Write-DebugText('           Matching line not found within ' + $maxRowsToCheck + ' rows, aborting')
                                        break
                                    }

                                    $curCheckIndex--
                                    $i++
                                }

                                Write-DebugText('           The number of lines with the same FFT size: ' + $numLinesWithSameFFTSize)

                                # If the number of same lines is uneven, we found the beginning of a pair
                                if ($numLinesWithSameFFTSize % 2 -ne 0) {
                                    # We're ignoring this line
                                    Write-DebugText('           Found the beginning of a pair')
                                    Write-DebugText('           - Ignoring this line')
                                }

                                # We've found a pair, insert this FFT size
                                else {
                                    Write-DebugText('           *** Found a pair ***')
                                    Write-DebugText('           - Inserting this FFT size')
                                    $insert = $true
                                }
                            }


                            $previousFFTLogEntry = $null
                            $previousFFTLogEntryLineNumber = 0

                            if ($allFFTLogEntries.Count -gt 1) {
                                $previousFFTLogEntry = $allFFTLogEntries | Select-Object -Last 1
                                $previousFFTLogEntryLineNumber = $previousFFTLogEntry.LineNumber
                            }

                            # Store the entry itself
                            Write-DebugText('           Line number of this entry:         ' + $currentResultLineEntry.LineNumber)
                            Write-DebugText('           Line number of the previous entry: ' + $previousFFTLogEntryLineNumber)

                            if (
                                $allFFTLogEntries.Count -eq 0 -or `
                                ($allFFTLogEntries.Count -gt 0 -and $currentResultLineEntry.LineNumber -ne $previousFFTLogEntryLineNumber)`
                            ) {
                                Write-DebugText('           + Adding this line to the allFFTLogEntries array')
                                [Void] $allFFTLogEntries.Add($currentResultLineEntry)
                            }


                            # Process and insert the FFT size
                            if ($insert) {
                                # IMPORTANT:
                                # There can be FFT sizes that are not divisible by 1024, and those will not have a "K" appended
                                # This can lead to confusion (e.g. in the sorting, or even possible duplicate matches), so we're multiplying every "K" value by 1024
                                $hasMatched = $currentResultLineEntry.Line -Match 'Self\-test (\d+)(K?) passed'

                                if ($hasMatched) {
                                    if ($Matches[2] -eq 'K') {
                                        $currentPassedFFTSize = [Int] $Matches[1] * 1024
                                    }
                                    else {
                                        $currentPassedFFTSize = [Int] $Matches[1]
                                    }
                                }

                                Write-DebugText('')
                                Write-DebugText('           Checking Line ' + $currentResultLineEntry.LineNumber)
                                Write-DebugText('           - The previous passed FFT size - old: ' + ($previousPassedFFTSize/1024) + 'K')
                                Write-DebugText('           - The current passed FFT size  - new: ' + ($currentPassedFFTSize/1024) + 'K')

                                # Enter the last passed FFT sizes arrays, both all and unique
                                [Void] $allPassedFFTs.Add($currentPassedFFTSize)

                                if (!($uniquePassedFFTs -contains $currentPassedFFTSize)) {
                                    [Void] $uniquePassedFFTs.Add($currentPassedFFTSize)
                                }


                                Write-DebugText('           - All passed FFTs:')
                                Write-DebugText('           - ' + ($allPassedFFTs -Join ', '))
                                Write-DebugText('           - All unique passed FFTs:')
                                Write-DebugText('           - ' + ($uniquePassedFFTs -Join ', '))

                                Write-VerboseText($timestamp + ' - The last passed FFT size: ' + ($currentPassedFFTSize/1024) + 'K')
                                Write-VerboseText('           The number of FFT sizes to test:        ' + $fftSubarray.Count)
                                Write-VerboseText('           The number of FFT sizes already tested: ' + $uniquePassedFFTs.Count)

                                # Store the entries to be able to compare to the previous value
                                $previousPassedFFTEntry = $currentResultLineEntry
                                $previousPassedFFTSize  = $currentPassedFFTSize


                                if ($proceedToNextCore -and !$fftSizeOverflow) {
                                    Write-DebugText('')
                                    Write-DebugText('           We didn''t check the log file in time to switch to the next core before another FFT size was tested.')
                                    Write-DebugText('           That''s nothing to worry about, it''s just a bit unfortunate, because the order of FFT sizes for the')
                                    Write-DebugText('           next core is now slightly shifted.')

                                    $fftSizeOverflow = $true
                                }

                                # This check might come too late, and so we're testing more FFT sizes than necessary
                                # Unfortunate, but no way around this if we want to correctly test all FFT sizes on each core
                                if ($uniquePassedFFTs.Count -eq $fftSubarray.Count) {
                                    $proceedToNextCore = $true
                                }
                            }
                        }


                        # Continue to the next core if the flag was set
                        if ($proceedToNextCore) {
                            Write-DebugText('proceedToNextCore is set!')

                            # Get the runtime for this core test
                            $endDateThisCore  = Get-Date
                            $differenceCore   = New-TimeSpan -Start $startDateThisCore -End $endDateThisCore
                            $runtimeArrayCore = @()

                            if ($differenceCore.Days -gt 0) {
                                $runtimeArrayCore += ($differenceCore.Days.ToString() + 'd')
                            }

                            $runtimeArrayCore += ($differenceCore.Hours.ToString().PadLeft(2, '0') + 'h')
                            $runtimeArrayCore += ($differenceCore.Minutes.ToString().PadLeft(2, '0') + 'm')
                            $runtimeArrayCore += ($differenceCore.Seconds.ToString().PadLeft(2, '0') + 's')
                            $runTimeStringCore = $runtimeArrayCore -Join ' '

                            Write-VerboseText('')
                            Write-VerboseText('           The number of unique FFT sizes matches the number of FFT sizes for the preset!')
                            Write-Text('           Test completed in ' + $runTimeStringCore)
                            Write-Text('           All FFT sizes have been tested for this core, proceeding to the next one')

                            if ($canUseWindowsEventLog) {
                                Write-AppEventLog -type 'core_finished' -infoString1 $coreString -infoString2 ('Test completed in ' + $runTimeStringCore)
                            }

                            continue LoopCoreRunner
                        }

                        Write-DebugText('')


                        # Break out of the while ($true) loop, we only want one iteration
                        break
                    }   # End :LoopCheckForAutomaticRuntime while ($true)
                }   # End if ($useAutomaticRuntimePerCore -and $isPrime95)



                # Y-CRUNCHER
                # If the runtime per core is set to auto and we're running y-cruncher with the logging functionality enabled
                # We need to check if all the selected tests have run
                # Note that the iterations in y-cruncher may not reflect the iterations in CoreCycler if there has been an error in-between
                elseif ($useAutomaticRuntimePerCore -and $isYCruncherWithLogging) {
                    :LoopCheckForAutomaticRuntime while ($true) {
                        $timestamp = Get-Date -Format HH:mm:ss
                        $foundPassedTestLines = @()

                        Write-DebugText($timestamp + ' - Automatic runtime per core selected')

                        # Only perform the check if the file size has increased
                        # The size has increased, so something must have changed
                        # It's either a new passed test entry, a new iteration, an error, or a restarted program
                        if ($newLogEntries.Count -le 0) {
                            Write-DebugText('           No new log file entries found')
                            break LoopCheckForAutomaticRuntime
                        }


                        # Check for an error, if we've found one, we don't even need to process any further
                        # Note: there is a potential to miss log entries this way
                        # However, since the script either stops at this point or the stress test program is restarted, we don't really need to worry about this
                        $errorResults = $newLogEntries | Where-Object { $_.Line -Match '.*error\(s\).*' } | Select-Object -Last 1

                        if ($errorResults) {
                            Write-DebugText('           Found an error entry in the new log entries, proceed to the error check')
                            break LoopCheckForAutomaticRuntime
                        }


                        # Get only the passed test lines
                        # Note: the new entries do not have the "Running XYZ:" part, so the test itself does not even appear
                        # We need to get the "line" directly before to get the actual test
                        $lastPassedTestResults = $newLogEntries | Where-Object { $_.Line -Match '.*Passed.*' }


                        # No passed tests found
                        if (!$lastPassedTestResults) {
                            Write-DebugText('           No passed tests found yet, assuming we''re at the very beginning of the run')
                            break LoopCheckForAutomaticRuntime
                        }


                        Write-DebugText('           The last passed test lines:')
                        $lastPassedTestResults | ForEach-Object {
                            Write-DebugText('           - [Line ' + $_.LineNumber + '] ' + $_.Line)
                        }


                        # Check all the entries in the found test results
                        # There may have been some sort of hiccup in the result file generation or file check, where one test is overlooked
                        # Start at the oldest line
                        foreach ($currentResultLineEntry in $lastPassedTestResults) {
                            # There's no previous entry, nothing to compare to
                            if (!$previousPassedTestEntry) {
                                # Add it to the list whether it's a new test or not
                                $foundPassedTestLines += $currentResultLineEntry
                            }

                            # Not reached the line number of the last entry yet
                            elseif ($currentResultLineEntry.LineNumber -le $previousPassedTestEntry.LineNumber) {
                                Write-DebugText('           Line number of previous entry not reached yet, skipping (Line ' + $currentResultLineEntry.LineNumber + ' <= ' + $previousPassedTestEntry.LineNumber + ')')
                                continue
                            }

                            # A new line number has been reached
                            elseif ($currentResultLineEntry.LineNumber -gt $previousPassedTestEntry.LineNumber) {
                                $foundPassedTestLines += $currentResultLineEntry
                            }
                        }


                        Write-DebugText('           All found passed test lines:')
                        $foundPassedTestLines | ForEach-Object {
                            Write-DebugText('           - [Line ' + $_.LineNumber + '] ' + $_.Line)
                        }


                        for ($currentLineIndex = 0; $currentLineIndex -lt $foundPassedTestLines.Count; $currentLineIndex++) {
                            $currentResultLineEntry = $foundPassedTestLines[$currentLineIndex]

                            $previousLogEntry = $null
                            $previousLogEntryLineNumber = 0

                            if ($allTestLogEntries.Count -gt 1) {
                                $previousLogEntry = $allTestLogEntries | Select-Object -Last 1
                                $previousLogEntryLineNumber = $previousLogEntry.LineNumber
                            }

                            Write-DebugText('')
                            Write-DebugText('           Checking line ' + $currentResultLineEntry.LineNumber)
                            Write-DebugText('           ' + $currentResultLineEntry.Line)

                            # Store the entry itself
                            Write-DebugText('           Line number of this entry:         ' + $currentResultLineEntry.LineNumber)
                            Write-DebugText('           Line number of the previous entry: ' + $previousLogEntryLineNumber)

                            if (
                                $allTestLogEntries.Count -eq 0 -or `
                                ($allTestLogEntries.Count -gt 0 -and $currentResultLineEntry.LineNumber -ne $previousLogEntryLineNumber)`
                            ) {
                                Write-DebugText('           + Adding this line to the allTestLogEntries array')
                                [Void] $allTestLogEntries.Add($currentResultLineEntry)
                            }


                            # Process and insert the test
                            # Note: the new entries do not have the "Running XYZ:" part, so the test itself does not even appear
                            # We need to get the "line" directly before to get the actual test
                            # So this line looks like this:
                            # Passed  Test Time:  65.252 seconds  ( 1.088 minutes )
                            $foundTestLine = $null
                            $currentPassedTest = $null


                            Write-DebugText('           Trying to get the passed test')
                            Write-DebugText('           Looking for ->')
                            Write-DebugText('           ' + $currentResultLineEntry.Line)

                            $hasMatched = $currentResultLineEntry.Line -Match 'Running ([a-z0-9]+):.*'

                            if ($hasMatched) {
                                $currentPassedTest = $Matches[1]
                            }

                            # If the line itself doesn't include the test name, we now try to get the passed test from the last entry up
                            else {
                                Write-DebugText('           Test not showing up in current line, searching the log entries for the passed test')

                                for ($x = $allLogEntries.Count-1; $x -ge 0; $x--) {
                                    Write-DebugText('           >>> [' + $x + '] ' + $allLogEntries[$x])

                                    if ($allLogEntries[$x] -eq $currentResultLineEntry.Line) {
                                        if ($x -gt 0) {
                                            $foundTestLine = $allLogEntries[$x-1]
                                            break
                                        }
                                    }
                                }

                                Write-DebugText('           Found line with test:')
                                Write-DebugText('           ' + $foundTestLine)

                                $hasMatched = $foundTestLine -Match 'Running ([a-z0-9]+):.*'

                                if ($hasMatched) {
                                    $currentPassedTest = $Matches[1]
                                }
                            }


                            if (!$currentPassedTest) {
                                Write-DebugText('           Couldn''t find the currently passed test, possible detection error?')
                                break LoopCheckForAutomaticRuntime
                            }


                            Write-DebugText('')
                            Write-DebugText('           Checked Line ' + $currentResultLineEntry.LineNumber)
                            Write-DebugText('           - The previous passed test - old: ' + $previousPassedTest)
                            Write-DebugText('           - The current passed test  - new: ' + $currentPassedTest)


                            # Enter the last passed test arrays, both all and unique
                            [Void] $allPassedTests.Add($currentPassedTest)

                            if (!($uniquePassedTests -contains $currentPassedTest)) {
                                [Void] $uniquePassedTests.Add($currentPassedTest)
                            }


                            Write-DebugText('           - All passed tests:')
                            Write-DebugText('           - ' + ($allPassedTests -Join ', '))
                            Write-DebugText('           - All unique passed tests:')
                            Write-DebugText('           - ' + ($uniquePassedTests -Join ', '))

                            Write-VerboseText($timestamp + ' - The last passed test: ' + $currentPassedTest)
                            Write-VerboseText('           The number of tests to run:      ' + $settings.yCruncher.tests.Count)
                            Write-VerboseText('           The number of tests already run: ' + $uniquePassedTests.Count)

                            # Store the entries to be able to compare to the previous value
                            $previousPassedTestEntry = $currentResultLineEntry
                            $previousPassedTest      = $currentPassedTest


                            # This check might come too late, and so we're testing more tests than necessary
                            # Unfortunate, but no way around this if we want to correctly test all test sizes on each core
                            if ($uniquePassedTests.Count -eq $settings.yCruncher.tests.Count) {
                                $proceedToNextCore = $true
                            }
                        }


                        # Continue to the next core if the flag was set
                        if ($proceedToNextCore) {
                            # Get the runtime for this core test
                            $endDateThisCore  = Get-Date
                            $differenceCore   = New-TimeSpan -Start $startDateThisCore -End $endDateThisCore
                            $runtimeArrayCore = @()

                            if ($differenceCore.Days -gt 0) {
                                $runtimeArrayCore += ($differenceCore.Days.ToString() + 'd')
                            }

                            $runtimeArrayCore += ($differenceCore.Hours.ToString().PadLeft(2, '0') + 'h')
                            $runtimeArrayCore += ($differenceCore.Minutes.ToString().PadLeft(2, '0') + 'm')
                            $runtimeArrayCore += ($differenceCore.Seconds.ToString().PadLeft(2, '0') + 's')
                            $runTimeStringCore = $runtimeArrayCore -Join ' '


                            Write-VerboseText('')
                            Write-VerboseText('           The number of unique test names matches the number of the selected test names!')
                            Write-Text('           Test completed in ' + $runTimeStringCore)
                            Write-Text('           All tests have been run for this core, proceeding to the next one')

                            if ($canUseWindowsEventLog) {
                                Write-AppEventLog -type 'core_finished' -infoString1 $coreString -infoString2 ('Test completed in ' + $runTimeStringCore)
                            }

                            continue LoopCoreRunner
                        }

                        Write-DebugText('')


                        # Break out of the while ($true) loop, we only want one iteration
                        break
                    }   # End :LoopCheckForAutomaticRuntime while ($true)
                }   # End if ($useAutomaticRuntimePerCore -and $isYCruncherWithLogging)



                # Check if the stress test process is still running or if there has been an error
                try {
                    Test-StressTestProgrammIsRunning -coreNumber $actualCoreNumber -coreStartDate $startDateThisCore
                }

                # Some error happened in or with the stress test program
                catch {
                    $params = @{
                        'checkType'          = 'TICK'
                        'actualCoreNumber'   = $actualCoreNumber
                        'coreTestOrderArray' = $coreTestOrderArray
                        'coreIndex'          = [Ref] $coreIndex
                        'ExceptionObj'       = $_
                        'ErrorObj'           = $Error
                    }

                    Resolve-StressTestProgrammIsRunningError @params


                    # Continue to the next core
                    continue LoopCoreRunner
                }   # End: catch
            }   # End: for ($checkNumber = 1; $checkNumber -le $cpuCheckIterations; $checkNumber++)




            # Wait for the remaining runtime
            Start-Sleep -Seconds $runtimeRemaining

            # One last check
            try {
                Write-VerboseText('One last error check before finishing this core')

                # Give it half a second
                Start-Sleep -Milliseconds 500

                if ($isPrime95 -or $isYCruncherWithLogging -or $isLinpack) {
                    Get-NewLogfileEntries
                }

                Test-StressTestProgrammIsRunning -coreNumber $actualCoreNumber -coreStartDate $startDateThisCore
            }

            # When an exception is thrown, the stress test process is not running anymore
            catch {
                $params = @{
                    'checkType'          = 'LAST_ERROR_CHECK'
                    'actualCoreNumber'   = $actualCoreNumber
                    'coreTestOrderArray' = $coreTestOrderArray
                    'coreIndex'          = [Ref] $coreIndex
                    'ExceptionObj'       = $_
                    'ErrorObj'           = $Error
                }

                Resolve-StressTestProgrammIsRunningError @params


                # An error has been thrown, do not display the test completed summary
                # Instead, continue to the next core right away
                continue LoopCoreRunner
            }   # End: catch


            # Get the runtime for this core test
            $endDateThisCore  = Get-Date
            $differenceCore   = New-TimeSpan -Start $startDateThisCore -End $endDateThisCore
            $runtimeArrayCore = @()

            if ($differenceCore.Days -gt 0) {
                $runtimeArrayCore += ($differenceCore.Days.ToString() + 'd')
            }

            $runtimeArrayCore += ($differenceCore.Hours.ToString().PadLeft(2, '0') + 'h')
            $runtimeArrayCore += ($differenceCore.Minutes.ToString().PadLeft(2, '0') + 'm')
            $runtimeArrayCore += ($differenceCore.Seconds.ToString().PadLeft(2, '0') + 's')
            $runTimeStringCore = $runtimeArrayCore -Join ' '

            Write-Text('           Test completed in ' + $runTimeStringCore)

            if ($canUseWindowsEventLog) {
                Write-AppEventLog -type 'core_finished' -infoString1 $coreString -infoString2 ('Test completed in ' + $runTimeStringCore)
            }
        }   # End: :LoopCoreRunner for ($coreIndex = 0; $coreIndex -lt $numAvailableCores; $coreIndex++)


        Write-VerboseText('──────────────────────────────────')
        Write-VerboseText('Iteration complete')
        Write-VerboseText('──────────────────────────────────')


        # Global counter
        $Script:completedIterations++


        # Print out the cores that have thrown an error so far
        if ($numCoresWithError -gt 0) {
            Write-Text('')

            if ($settings.General.skipCoreOnError) {
                Write-ColorText('The following cores have thrown an error: ' + (($coresWithError | Sort-Object) -Join ', ')) Cyan
            }
            else {
                Write-ColorText('The following cores have thrown an error:') Cyan

                $coreWithTwoDigitsHasError = $false

                foreach ($entry in $coresWithErrorsCounter.GetEnumerator()) {
                    if ($entry.Name -gt 9 -and $entry.Value -gt 0) {
                        $coreWithTwoDigitsHasError = $true
                        break
                    }
                }

                foreach ($entry in ($coresWithErrorsCounter.GetEnumerator() | Sort-Object -Property Name)) {
                    # No error, skip
                    if ($entry.Value -lt 1) {
                        continue
                    }

                    $corePadding = $(if ($coreWithTwoDigitsHasError) { ' ' } else { '' })
                    $coreText  = $(if ($entry.Name -lt 10) { $corePadding })
                    $coreText += $entry.Name.ToString()

                    $textErrors      = 'error'
                    $textIterations  = 'iteration'

                    $textErrors     += $(if ($entry.Value -gt 1) { 's' })
                    $textIterations += $(if ($iteration -gt 1) { 's' })

                    Write-ColorText('    - Core ' + $coreText + ': ' + $entry.Value.ToString() + ' ' + $textErrors + ' in ' + $iteration + ' ' + $textIterations) Cyan
                }
            }

            Write-Text('')
        }


        # Show the starting and current Curve Optimizer values
        if ($useCurveOptimizer -and $numCoresWithIncreasedVoltageValue -gt 0) {
            $coCoresString    = ((0..($numPhysCores-1)) | ForEach-Object { ('C' + $_.ToString()).PadLeft(4, ' ') }) -Join ' |'
            $startingCoString = ($voltageStartingValues | ForEach-Object { $_.ToString().PadLeft(4, ' ') }) -Join ' |'
            $currentCoString  = ($voltageCurrentValues | ForEach-Object { $_.ToString().PadLeft(4, ' ') }) -Join ' |'

            Write-ColorText('Curve Optimizer:') Cyan
            Write-ColorText('Core            ' + $coCoresString) Cyan
            Write-ColorText('Starting values ' + $startingCoString) Cyan
            Write-ColorText('Current values  ' + $currentCoString) Cyan
            Write-Text('')
        }

        # Show the starting and current voltage offset values
        if ($useIntelVoltageAdjustment -and $voltageStartingValues[0] -ne $voltageCurrentValues[0]) {
            Write-ColorText('Voltage offset starting value: ' + $voltageStartingValues[0] + 'mv') Cyan
            Write-ColorText('Voltage offset current value:  ' + $voltageCurrentValues[0]  + 'mv') Cyan
            Write-Text('')
        }
    }   # End for ($iteration = 1; $iteration -le $settings.General.maxIterations; $iteration++)


    # The CoreCycler has finished
    $timestamp = Get-Date -Format HH:mm:ss
    Write-ColorText($timestamp + ' - CoreCycler finished!') Green

    if ($canUseWindowsEventLog) {
        Write-AppEventLog -type 'script_finished'
    }

    Close-StressTestProgram
    Exit-Script
}


# Catch any errors that have been thrown and have not fired Exit-WithFatalError yet
catch {
    # Special handling if the settings couldn't be imported
    if (!$settings -or !$settings.Logging) {
        Write-Host('Error in the main functionality block!') -ForegroundColor Red
        Write-Host($Error | Out-String) -ErrorAction Ignore
        Write-Host($_.Exception | Format-List -Force | Out-String) -ErrorAction Ignore
        Write-Host($_.InvocationInfo | Format-List -Force | Out-String) -ErrorAction Ignore
    }
    else {
        Write-VerboseText('Error in the main functionality block!')
        Write-VerboseText($Error | Out-String) -ErrorAction Ignore
        Write-VerboseText($_.Exception | Format-List -Force | Out-String) -ErrorAction Ignore
        Write-VerboseText($_.InvocationInfo | Format-List -Force | Out-String) -ErrorAction Ignore
    }

    if ($canUseWindowsEventLog) {
        $errorString  = $Error | Out-String -ErrorAction Ignore
        $errorString += [Environment]::NewLine + ($_.Exception | Format-List -Force | Out-String -ErrorAction Ignore)
        $errorString += [Environment]::NewLine + ($_.InvocationInfo | Format-List -Force | Out-String -ErrorAction Ignore)
        Write-AppEventLog -type 'script_error' -infoString1 $errorString
    }

    $lineNumber = $(if (($_ | Get-Member InvocationInfo) -and ($_.InvocationInfo | Get-Member ScriptLineNumber)) { $_.InvocationInfo.ScriptLineNumber } else { (Get-ScriptLineNumber) })

    Exit-WithFatalError -text $_ -lineNumber $lineNumber
}


# This should execute even if CTRL+C is pressed
# Although probably no output is generated for it anymore
# Maybe the user wants to check the stress test program output after terminating the script
finally {
    Write-DebugText('')
    Write-DebugText('┌─────────────────────────┐')
    Write-DebugText('│    THE FINALLY BLOCK    │')
    Write-DebugText('└─────────────────────────┘')
    Write-DebugText('')

    $processCPUPercentage = 0

    $timestamp = Get-Date -Format HH:mm:ss
    Write-VerboseText($timestamp + ' - Terminating the script...')


    # Try to re-enable the close button
    $null = [ConsoleWindowMenu]::AppendMenu($parentMainWindowMenuHandle, [ConsoleWindowMenu]::MF_STRING, [ConsoleWindowMenu]::SC_CLOSE, "Close")

    # Try to restore our original console mode
    $null = [ChangeConsoleMode]::SetMode($consoleMode)

    # Re-enable sleep
    [Windows.PowerUtil]::StayAwake($false)

    # Destroy the reason to block a shutdown
    if ($parentMainWindowHandle -ne [System.IntPtr]::Zero) {
        $shutdownBlockReasonDestroyRetVal = [ShutdownBlock]::ShutdownBlockReasonDestroy($parentMainWindowHandle)
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()

        if ($shutdownBlockReasonDestroyRetVal) {
            Write-VerboseText('Successfully destroyed the shutdown block reason: (' + $shutdownBlockReasonDestroyRetVal + ')')
        }
        else {
            Write-VerboseText('Could not destroy the shutdown block reason! (Return value: ' + $shutdownBlockReasonDestroyRetVal + ')')

            if ($errorCode -gt 0) {
                Write-DebugText('Error Code: ' + $errorCode + ' - Line: ' + (Get-ScriptLineNumber))
                $errorResult = Get-DotNetErrorMessage $errorCode
                Write-VerboseText($errorResult.errorMessage)
            }
        }
    }


    if ($canUseWindowsEventLog) {
        $infoString  = 'The log files for this run are stored in:' + [Environment]::NewLine
        $infoString += $logFilePathAbsolute + $logFileName + [Environment]::NewLine

        if ($stressTestLogFileName) {
            $infoString += $logFilePathAbsolute + $stressTestPrograms[$settings.General.stressTestProgram]['displayName'] + ': ' + $stressTestLogFileName
        }

        $finalSummary = (Show-FinalSummary -ReturnText)

        Write-AppEventLog -type 'script_terminated' -infoString1 $infoString -infoString2 $finalSummary
    }


    # The script has ended (in one way or another), so we don't need the reboot startup task and file anymore
    Remove-AutoModeScheduledTask
    Remove-AutoModeFile


    # Don't do anything after a fatal error
    if ($fatalError) {
        Write-DebugText('Exit-WithFatalError was called, skipping the rest')
        exit
    }


    # Exit-Script has been called (no CTRL+C)
    if ($scriptExit) {
        # Show the final summary
        Show-FinalSummary
        exit
    }


    # Below this point should be a regular end of the script or CTRL+C was pressed


    # Set the window title
    $Host.UI.RawUI.WindowTitle = ('CoreCycler ' + $version + ' terminating')

    Write-ColorText($timestamp + ' - Terminating the script...') Red


    if ($enablePerformanceCounters) {
        # If the stress test program is still running and using enough CPU power, close it
        if ($processCounterPathTime) {
            $processCPUPercentage = [Math]::Round(((Get-Counter $processCounterPathTime -ErrorAction Ignore).CounterSamples.CookedValue) / $numLogicalCores, 2)
        }


        Write-VerboseText('Checking CPU usage: ' + $processCPUPercentage + '% (expected: ' + $expectedUsageTotal + '%, lower limit: ' + $minProcessUsage + '%)')

        # Close only if we're using still enough CPU power
        if ($processCPUPercentage -ge $minProcessUsage) {
            Write-VerboseText('The stress test program is still using enough CPU power, so we can try to close it')
            Write-Text('           Trying to close the stress test program...')
            Close-StressTestProgram

            Write-ColorText('Please check if the selected stress test program "' + $selectedStressTestProgram + '" is still running!') Yellow
        }
        else {
            Write-ColorText('The stress test program seems to have stopped.') Yellow
            Write-ColorText('Not killing the process so you can check if there was some error.') Yellow

            Write-ColorText('Please make sure to close "' + $selectedStressTestProgram + '" after you checked it!') Yellow
        }
    }


    else {
        Write-VerboseText('Checking if the process is still active')
        $checkProcess = $null

        if ($stressTestProcessId) {
            $checkProcess = Get-Process -Id $stressTestProcessId -ErrorAction Ignore
        }

        if ($checkProcess) {
            Write-VerboseText('The stress test process is still running')
            Write-VerboseText('Checking if the process is still using CPU power')

            # CPU(s): The amount of processor time that the process has used on all processors, in seconds.
            $firstCpuValue = $checkProcess.UserProcessorTime.TotalSeconds
            Start-Sleep -Milliseconds 500
            $secondCpuValue = $checkProcess.UserProcessorTime.TotalSeconds

            $diffCpuValue = $secondCpuValue - $firstCpuValue

            Write-DebugText('First CPU Value:  ' + $firstCpuValue)
            Write-DebugText('Second CPU Value: ' + $secondCpuValue)
            Write-DebugText('Difference:       ' + $diffCpuValue)

            if ($diffCpuValue -gt 0.2) {
                Write-VerboseText('The stress test program is still using enough CPU power, so we can try to close it')
                Write-Text('           Trying to close the stress test program...')
                Close-StressTestProgram

                Write-ColorText('Please check if the selected stress test program "' + $selectedStressTestProgram + '" is still running!') Yellow
            }
            else {
                # Maybe the process was suspended?
                Write-DebugText('The stress test program isn''t using enough CPU power, maybe it''s suspended')

                $suspendedThreads = @($checkProcess.Threads | Select-Object -Property ThreadState, WaitReason | Where-Object -FilterScript { $_.ThreadState -eq 'Wait' -and $_.WaitReason -eq 'Suspended' })

                Write-DebugText('$checkProcess.Threads.Count: ' + $checkProcess.Threads.Count)
                Write-DebugText('$suspendedThreads.Count:     ' + $suspendedThreads.Count)

                # Do we need to have the counts to be equal at this point?
                # I suppose not. Resume any thread that is suspended
                #if ($checkProcess.Threads.Count -eq $suspendedThreads.Count) {
                if ($suspendedThreads.Count -gt 0) {
                    Write-DebugText('There''s at least one suspended thread')

                    $null = Resume-Process -process $checkProcess -ignoreError $true

                    $firstCpuValue = $checkProcess.UserProcessorTime.TotalSeconds
                    Start-Sleep -Milliseconds 500
                    $secondCpuValue = $checkProcess.UserProcessorTime.TotalSeconds

                    $diffCpuValue = $secondCpuValue - $firstCpuValue

                    Write-DebugText('First CPU Value:  ' + $firstCpuValue)
                    Write-DebugText('Second CPU Value: ' + $secondCpuValue)
                    Write-DebugText('Difference:       ' + $diffCpuValue)

                    if ($diffCpuValue -gt 0.2) {
                        Write-VerboseText('The stress test program is still using enough CPU power, so we can try to close it')
                        Write-Text('           Trying to close the stress test program...')
                        Close-StressTestProgram

                        Write-ColorText('Please check if the selected stress test program "' + $selectedStressTestProgram + '" is still running!') Yellow
                    }
                    else {
                        Write-DebugText('We tried to resume, it didn''t change anything')
                    }
                }
            }
        }
        else {
            Write-VerboseText('The stress test process is not running anymore')
            Write-ColorText('The stress test program seems to have stopped.') Yellow
            Write-ColorText('Not killing the process so you can check if there was some error.') Yellow

            Write-ColorText('Please make sure to close "' + $selectedStressTestProgram + '" after you checked it!') Yellow
        }
    }


    Write-ColorText('Check for these processes:') Yellow
    Write-ColorText(' - ' + $stressTestPrograms[$settings.General.stressTestProgram]['processName'] + '.' + $stressTestPrograms[$settings.General.stressTestProgram]['processNameExt']) Cyan

    if ($stressTestPrograms[$settings.General.stressTestProgram]['processName'] -ne $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad']) {
        $processNameForLoad = $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad']

        # If the process name doesn't already have a file extension, add the one from the processNameExt
        if ($processNameForLoad[-4] -ne '.') {
            $processNameForLoad = $processNameForLoad + '.' + $stressTestPrograms[$settings.General.stressTestProgram]['processNameExt']
        }

        Write-ColorText(' - ' + $processNameForLoad) Cyan
    }


    # Show the final summary
    Show-FinalSummary
}
