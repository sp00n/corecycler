<#
.AUTHOR
    sp00n
.DESCRIPTION
    Get the duration of each iteration for a specific FFT size
    Helps to find a suitable value for the runtimePerCore setting
.LINK
    Helps to find a suitable value for the runtimePerCore setting
.LICENSE
    Creative Commons "CC BY-NC-SA"
    https://creativecommons.org/licenses/by-nc-sa/4.0/
    https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode
.NOTES
    Instead of providing the log file in this file, you can also pass the name in the command line
    E.g. .\analyze_prime95_logfile.ps1 "Prime95_results.txt"
    The passed argument will always take precedence over the one provided in this file
#>

# The directory of where the log file can be found
# You can use an absolute or relative path from where this script is located
$logFileDirectory = '..\logs\'


# The name of the log file to analyze
$logFileName = ''

# The script tries to autodetect the FFT preset and test mode used in the log file, but you can specify them here
$testMode        = 'auto'   # "auto" or SSE, AVX, AVX
$fftPreset       = 'auto'   # "auto" or Smallest, Small, Large, Huge, All
$numberOfThreads = 'auto'   # "auto" or the number of threads used (1 or 2)


# If there was a log file passed as an argument, use this instead of the provided one here
if ($args[0]) {
    $logFileName = $args[0]
}


# The FFT size array to be able to analyze the log file
$allFFTSizes = @{
    SSE = @(
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

    AVX = @(
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
        # 32768K = 33554432 seems to be the maximum FFT size possible for AVX
        9175040, 9437184, 9830400, 10485760, 11010048, 11796480, 12582912, 13107200, 13762560, 14155776, 14680064, 15728640, 16384000, 16515072, 16777216, 18350080,
        18874368, 19660800, 20971520, 22020096, 22937600, 23592960, 25165824, 26214400, 27525120, 29360128, 31457280, 32768000, 33554432
    )

    AVX2 = @(
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
        # 65536K = 67108864 seems to be the maximum FFT size possible for AVX2
        8601600, 8847360, 9175040, 9830400, 10485760, 10616832, 11468800, 11796480, 12582912, 13107200, 13762560, 14745600, 15728640, 16056320,
        16515072, 16777216, 17203200, 17694720, 18350080, 18874368, 19267584, 19660800, 20643840, 20971520, 21233664, 22020096, 22478848, 22937600,
        24084480, 24772608, 25165824, 25690112, 26214400, 27525120, 28311552, 28901376, 29491200, 31457280, 32112640, 33030144, 33718272, 35389440,
        37748736, 38535168, 39321600, 41287680, 41943040, 42467328, 44040192, 47185920, 48168960, 49545216, 50331648, 51380224, 55050240, 56623104,
        57802752, 58720256, 62914560, 67108864
    )
}

# The min and max values for the various presets
# Note that the actually tested sizes differ from the originally provided min and max values
# depending on the selected test mode (SSE, AVX, AVX2)
$FFTMinMaxValues = @{
    SSE = @{
        Smallest   = @{ Min =    4096; Max =    21504; }  # Originally   4 ...   21
        Small      = @{ Min =   36864; Max =   245760; }  # Originally  36 ...  248
        Large      = @{ Min =  458752; Max =  8388608; }  # Originally 426 ... 8192
        Huge       = @{ Min = 9175040; Max = 33554432; }  # New addition
        All        = @{ Min =    4096; Max = 33554432; }
        Moderate   = @{ Min = 1376256; Max =  4194304; }
        Heavy      = @{ Min =    4096; Max =  1376256; }
        HeavyShort = @{ Min =    4096; Max =   163840; }
    }

    AVX = @{
        Smallest   = @{ Min =    4096; Max =    21504; }  # Originally   4 ...   21
        Small      = @{ Min =   36864; Max =   245760; }  # Originally  36 ...  248
        Large      = @{ Min =  458752; Max =  8388608; }  # Originally 426 ... 8192
        Huge       = @{ Min = 9175040; Max = 33554432; }  # New addition
        All        = @{ Min =    4096; Max = 33554432; }
        Moderate   = @{ Min = 1376256; Max =  4194304; }
        Heavy      = @{ Min =    4096; Max =  1376256; }
        HeavyShort = @{ Min =    4096; Max =   163840; }
    }

    AVX2 = @{
        Smallest   = @{ Min =    4096; Max =    21504; }  # Originally   4 ...   21
        Small      = @{ Min =   36864; Max =   245760; }  # Originally  36 ...  248
        Large      = @{ Min =  458752; Max =  8388608; }  # Originally 426 ... 8192
        Huge       = @{ Min = 9175040; Max = 52428800; }  # New addition
        All        = @{ Min =    4096; Max = 52428800; }
        Moderate   = @{ Min = 1376256; Max =  4194304; }
        Heavy      = @{ Min =    4096; Max =  1376256; }
        HeavyShort = @{ Min =    4096; Max =   163840; }
    }

    AVX512 = @{
        Smallest   = @{ Min =    4608; Max =    21504; }  # Originally   4 ...   21
        Small      = @{ Min =   36864; Max =   245760; }  # Originally  36 ...  248
        Large      = @{ Min =  458752; Max =  8388608; }  # Originally 426 ... 8192
        Huge       = @{ Min = 9175040; Max = 67108864; }  # New addition
        All        = @{ Min =    4608; Max = 67108864; }
        Moderate   = @{ Min = 1376256; Max =  4194304; }
        Heavy      = @{ Min =    4608; Max =  1376256; }
        HeavyShort = @{ Min =    4608; Max =   163840; }
    }

    # The limits apprently have changed for Prime95 30.8
    <#
    AVX512 = @{
        Smallest   = @{ Min =    4; Max =    42; }  # Originally   4 ...   42
        Small      = @{ Min =   73; Max =   455; }  # Originally  73 ...  455
        Large      = @{ Min =  780; Max =  8192; }  # Originally 780 ... 8192
        Huge       = @{ Min = 8400; Max = 65536; }  # New addition
        All        = @{ Min =    4; Max = 65536; }
        Moderate   = @{ Min = 1344; Max =  4096; }
        Heavy      = @{ Min =    4; Max =  1344; }
        HeavyShort = @{ Min =    4; Max =   160; }
    }
    #>
}


# If the log file name contains back slashes, ignore the $logFileDirectory variable
if ( $logFileName -notcontains '\' ) {
    $filePath = $logFileName
}
else {
    # The full path of the log file
    $folder   = (Resolve-Path $logFileDirectory).ToString()
    $folder  += $(if ($folder.SubString($folder.Length-1) -ne '\') { '\' })
    $filePath = (Resolve-Path $logFileDirectory).ToString() + $logFileName
}


if ( $logFileName.Length -eq 0 ) {
    Write-Host('ERROR: No log file provided!') -ForegroundColor Red
    Write-Host('       Please change the "$logFileName" variable in the script or just') -ForegroundColor Red
    Write-Host('       add the name/path of the log file to the command line.') -ForegroundColor Red
    Write-Host('');
    Write-Host('Example: .\analyze_prime95_logfile.ps1 "Prime95_Log_File.txt"') -ForegroundColor Yellow
    Write-Host($filePath) -ForegroundColor Yellow

    Read-Host -Prompt 'Press Enter to exit'
    exit    
}


if (!$filePath -or $filePath.Length -eq 0 -or !(Test-Path $filePath -PathType leaf)) {
    Write-Host('ERROR: Could not find the provided log file!') -ForegroundColor Red
    Write-Host('');
    Write-Host('The provided log file was:') -ForegroundColor Red
    Write-Host($filePath) -ForegroundColor Yellow

    Read-Host -Prompt 'Press Enter to exit'
    exit
}


$allFFTSizesInLogfile        = @()
$allUniqueFFTSizesInLogfile  = @()
$selectedFFTSizesArray       = @()
$allFFTSizesInLogifle        = @()
$foundFFTSizesIteration      = @()
$foundFFTSizesUnique         = @()
$foundTestModesMinMax        = @()
$detectedTestModesFFT        = @()
$detectedFftPreset           = $null
$detectedNumberOfThreads     = $null
$autodetectedTestMode        = $false
$autodetectedFftPreset       = $false
$autodetectedNumberOfThreads = $false
$foundTestModesMinMax        = @()
$detectedTestModesFFT        = @()
$testModesToCheck            = @()
$logfile                     = Get-Content $filePath
$regexFFT                    = '^Self\-test (\d+)(K?) passed!$'
$regexTime                   = '^\[(.*)]$'
$curLineNumber               = 0
$startLineNumber             = 1
$startOfNewIteration         = $true
$months                      = @('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec')
$iterations                  = @()
$durations                   = @()


# Set the testMode, fftPreset and numberOfThreads to 'auto' if they're not set at all
$testMode        = $(if (!$testMode        -or $testMode.Length -eq 0)        { 'auto' } else { $testMode })
$fftPreset       = $(if (!$fftPreset       -or $fftPreset.Length -eq 0)       { 'auto' } else { $fftPreset })
$numberOfThreads = $(if (!$numberOfThreads -or $numberOfThreads.Length -eq 0) { 'auto' } else { $numberOfThreads })


# Autodetect the FFT size
if ($testMode -eq 'auto' -or $fftPreset -eq 'auto') {
    Write-Host ('')
    Write-Host ('Autodetecting the used FFT preset and test mode in the log file') -ForegroundColor Blue
    Write-Host ('---------------------------------------------------------------') -ForegroundColor Blue

    Write-Host -NoNewline ('Analyzing log file: ............... ') -ForegroundColor Cyan
    Write-Host ($filePath) -ForegroundColor Yellow



    # If no preset was provided 
    foreach ($line in $logfile) {
        if ($line -Match $regexFFT) {
            if ($matches[2] -eq "K") {
                $curFFTSize = [Int64]$matches[1] * 1024
            }
            else {
                $curFFTSize = [Int64]$matches[1]
            }

            $allFFTSizesInLogfile += $curFFTSize
        }
    }

    # Try to detect if one or two threads were used
    # For two threads, there should be multiple instances where the same FFT sizes appears back-to-back
    # We shouldn't need to worry about FFT "drift", as the threads run on the same core with the same speed
    if ($numberOfThreads -eq 'auto' -or $numberOfThreads -gt 2 -or $numberOfThreads -lt 1) {
        $hitsForBackToBack = 0

        # Check the first 50 lines to determine if we have back-to-back entries
        for ($i = 1; $i -le 50; $i++) {
            if ($allFFTSizesInLogfile[$i] -eq $allFFTSizesInLogfile[$i-1]) {
                $hitsForBackToBack++
            }
        }

        #'hitsForBackToBack: ' + $hitsForBackToBack

        # Let's set a totally arbitrary limit at 5
        if ($hitsForBackToBack -gt 5) {
            $detectedNumberOfThreads = 2
        }
        else {
            $detectedNumberOfThreads = 1
        }
    }


    $allUniqueFFTSizesInLogfile = $allFFTSizesInLogfile | Select -Unique

    $minFoundFFTSize = ($allFFTSizesInLogfile | Measure -Min).Minimum
    $maxFoundFFTSize = ($allFFTSizesInLogfile | Measure -Max).Maximum
    $minFoundFFTSizeDisplay = if ($minFoundFFTSize % 1024 -eq 0) { ($minFoundFFTSize/1024).toString() + 'K' } else { $minFoundFFTSize }
    $maxFoundFFTSizeDisplay = if ($maxFoundFFTSize % 1024 -eq 0) { ($maxFoundFFTSize/1024).toString() + 'K' } else { $maxFoundFFTSize }

    Write-Host -NoNewline ('Minimum FFT Size found: ........... ') -ForegroundColor Cyan
    Write-Host ($minFoundFFTSizeDisplay) -ForegroundColor Yellow
    Write-Host -NoNewline ('Maximum FFT Size found: ........... ') -ForegroundColor Cyan
    Write-Host ($maxFoundFFTSizeDisplay) -ForegroundColor Yellow

    # If there was a test mode provided
    if ($testMode -ne 'auto') {
        $testModesToCheck += $testMode
    }
    else {
        # First check SSE, then AVX, then AVX2, then AVX512
        $testModesToCheck = @('SSE', 'AVX', 'AVX2', 'AVX512')
    }

    # No FFT preset was provided
    if ($fftPreset -eq 'auto') {
        # Go through the provided or all of the test modes
        foreach ($testModeBeingChecked in $testModesToCheck) {
            # Check if the min and max values match
            foreach ($fftSizeEntry in $FFTMinMaxValues[$testModeBeingChecked].GetEnumerator()) {
                if ($fftSizeEntry.Value['Min'] -eq $minFoundFFTSize -and $fftSizeEntry.Value['Max'] -eq $maxFoundFFTSize) {
                    $foundTestModesMinMax += $testModeBeingChecked
                    $detectedFftPreset = $fftSizeEntry.Name # This should not change, so we don't need to save all found presets
                }
            }
        }

        if (!$detectedFftPreset) {
            Write-Host ('ERROR: Could not find a matching FFT preset!') -ForegroundColor Red

            Read-Host -Prompt 'Press Enter to exit'
            exit
        }

        $fftPreset = $detectedFftPreset
    }

    # Check the provided FFT preset
    else {
        # Go through the provided or all of the test modes
        foreach ($testModeBeingChecked in $testModesToCheck) {
            # Check if the min and max values match
            foreach ($fftSizeEntry in $FFTMinMaxValues[$testModeBeingChecked][$fftPreset]) {
                if ($fftSizeEntry['Min'] -eq $minFoundFFTSize -and $fftSizeEntry['Max'] -eq $maxFoundFFTSize) {
                    $foundTestModesMinMax += $testModeBeingChecked
                    $detectedFftPreset = $fftSizeEntry.Name # This should not change, so we don't need to save all found presets
                }
            }
        }
    }



    # Check if all the FFT sizes are correct
    foreach ($testModeBeingChecked in $testModesToCheck) {
        if (!$foundTestModesMinMax.Contains($testModeBeingChecked)) {
            continue
        }

        # Get the sub array
        $startKey = [Array]::indexOf($allFFTSizes[$testModeBeingChecked], $FFTMinMaxValues[$testModeBeingChecked][$fftPreset]['Min'])
        $endKey   = [Array]::indexOf($allFFTSizes[$testModeBeingChecked], $FFTMinMaxValues[$testModeBeingChecked][$fftPreset]['Max'])
        $fftSubarray = $allFFTSizes[$testModeBeingChecked][$startKey..$endKey]
        
        $missing1 = $fftSubarray | Where {$allUniqueFFTSizesInLogfile -NotContains $_}
        $missing2 = $allUniqueFFTSizesInLogfile | Where {$fftSubarray -NotContains $_}


        <#
        ''
        'testModeBeingChecked:'
        $testModeBeingChecked

        'fftSubarray:'
        $fftSubarray -Join ', '

        ''
        'allUniqueFFTSizesInLogfile:'
        ($allUniqueFFTSizesInLogfile | Sort-Object) -Join ', '

        'Do the arrays match?'

        
        'missing1:'
        ' - Length: ' + $missing1.Length
        $missing1 -Join ', '


        'missing2:'
        ' - Length: ' + $missing2.Length
        $missing2 -Join ', '
        '-------------------------------------'
        #>

        
        # Found a matching hit
        if ($missing1.Length -eq 0 -and $missing2.Length -eq 0) {
            $detectedTestModesFFT += $testModeBeingChecked
        }
    }


    # No matching test mode found
    if ($detectedTestModesFFT.Length -eq 0) {
        Write-Host ('ERROR: Could not find a matching FFT preset!') -ForegroundColor Red

        Read-Host -Prompt 'Press Enter to exit'
        exit
    }

    # If more than one test mode was found, abort, because we cannot be sure
    # if ($detectedTestModesFFT.Length -gt 1) {
    #     Write-Host ('ERROR: Found more than one matching FFT preset!') -ForegroundColor Red
    #     Write-Host -NoNewline ('Possible matches: ') -ForegroundColor Blue
    #     Write-Host ($detectedTestModesFFT -Join ', ') -ForegroundColor Yellow

    #     Read-Host -Prompt 'Press Enter to exit'
    #     exit
    # }


    # A test mode was provided, check if it appears in the detected modes
    if ($testMode -ne 'auto' -and !$detectedTestModesFFT.Contains($testMode)) {
        Write-Host ('ERROR: The provided test mode doesn''t match the data in the log file!') -ForegroundColor Red

        Read-Host -Prompt 'Press Enter to exit'
        exit
    }


    if ($testMode -eq 'auto') {
        $autodetectedTestMode = $true
        
        Write-Host -NoNewline ('Autodetected Test Mode: ........... ') -ForegroundColor Cyan
        Write-Host ($detectedTestModesFFT -Join ' or ') -ForegroundColor Yellow        
    }
    else {
        Write-Host -NoNewline ('Provided Test Mode: ............... ') -ForegroundColor Cyan
        Write-Host ($testMode) -ForegroundColor Yellow
    }


    if ($detectedFftPreset -and $detectedFftPreset.Length -gt 0) {
        $autodetectedFftPreset = $true

        Write-Host -NoNewline ('Autodetected FFT Preset: .......... ') -ForegroundColor Cyan
        Write-Host ($fftPreset) -ForegroundColor Yellow
    }
    else {
        Write-Host -NoNewline ('Provided FFT Preset: .............. ') -ForegroundColor Cyan
        Write-Host ($fftPreset) -ForegroundColor Yellow
    }


    if ($detectedNumberOfThreads -and $detectedNumberOfThreads.Length -gt 0) {
        $autodetectedNumberOfThreads = $true

        Write-Host -NoNewline ('Autodetected Number of Threads: ... ') -ForegroundColor Cyan
        Write-Host ($detectedNumberOfThreads) -ForegroundColor Yellow
    }
    else {
        Write-Host -NoNewline ('Provided FFT Number of Threads: ... ') -ForegroundColor Cyan
        Write-Host ($numberOfThreads) -ForegroundColor Yellow
    }


    Write-Host ('')
    
    if ($detectedTestModesFFT.Length -gt 1) {
        Write-Host ('Warning! More than one possible test mode found!') -ForegroundColor Red
        Write-Host ('')
    }

    Write-Host ('')


    # No test mode was provided, and there's more than one possible candidate
    # Set the test mode to the first entry if no test mode was provided
    if ($testMode -eq 'auto') {
        $testMode = $detectedTestModesFFT[0]
    }

    if ($numberOfThreads -eq 'auto') {
        $numberOfThreads = $detectedNumberOfThreads
    }
}



# Get the selected FFT size array
try {
    $startKey = [Array]::indexOf($allFFTSizes[$testMode], $FFTMinMaxValues[$testMode][$fftPreset]['Min'])
    $endKey   = [Array]::indexOf($allFFTSizes[$testMode], $FFTMinMaxValues[$testMode][$fftPreset]['Max'])
    $selectedFFTSizesArray = $allFFTSizes[$testMode][$startKey..$endKey]
}
catch {
    Write-Host ('Error! Could not find the correct start and end FFT size for the selected test mode!') -ForegroundColor Red
    $fftPreset
    Read-Host -Prompt 'Press Enter to exit'
    exit
}


$previousFFTSize = -1


# Now process the FFT sizes
foreach ($line in $logfile) {
    $curLineNumber++
    
    if ($line -Match $regexFFT) {
        if ($matches[2] -eq "K") {
            $fftSize = [Int64]$matches[1] * 1024
        }
        else {
            $fftSize = [Int64]$matches[1]
        }
        
        $matches.Clear()

        #'Current FFT Size:  ' + ($fftSize/1024) + '  (Length of unique FFT array: ' + $foundFFTSizesUnique.Length + ')'
        #'Previous FFT Size: ' + $previousFFTSize

        # Compare the FFT size to the previous one
        # If we're on two threads, ignore this FFT size if it's the same as the previous one
        if ($numberOfThreads -eq 2) {
            if ($fftSize -eq $previousFFTSize) {
                #'Back-to-back FFT size found! - ' + $fftSize + ' <-> ' + $previousFFTSize
                
                # Reset the previous FFT size so that we can catch if there are actually two "real" FFTs with the same size back-to-back
                # It can happen if e.g. one iteration ends with the same FFT size that the next one starts with
                # (23040K seems to be a candidate for this in the Huge preset)
                $previousFFTSize = -1

                # Skip
                continue
            }

            else {
                $previousFFTSize = $fftSize
            }
        }

        else {
            $previousFFTSize = $fftSize
        }

        # Store the found FFT size
        $foundFFTSizesIteration += $fftSize
        
        # Store only unique FFT sizes
        if (!$foundFFTSizesUnique.Contains($fftSize)) {
            $foundFFTSizesUnique += $fftSize
        }
        else {
            #'Duplicate entry found!'
            #$fftSize
        }


        #'Current FFT Size:  ' + ($fftSize/1024) + '  (Length of unique FFT array: ' + $foundFFTSizesUnique.Length + ')'


        # If all FFT sizes have been found for this iteration
        if ($foundFFTSizesUnique.Length -eq $selectedFFTSizesArray.Length) {
            ''
            'Found a full iteration'
            'Length of unique FFT array: ' + $foundFFTSizesUnique.Length
            ''

            # Look for the start and end time
            $startDate    = $null
            $endDate      = $null
            $startDateStr = $null
            $endDateStr   = $null
            $conStartStr  = $null
            $conEndStr    = $null
            $duration     = $null

            # Start time
            # 1 line above
            if ($logfile[$startLineNumber-1] -Match $regexTime) {
                $startDateStr = $matches[1]
            }
            # 1 line below
            elseif ($logfile[$startLineNumber] -Match $regexTime) {
                $startDateStr = $matches[1]
            }
            # 2 lines above
            elseif ($logfile[$startLineNumber-2] -Match $regexTime) {
                $startDateStr = $matches[1]
            }
            # 2 lines below
            elseif ($logfile[$startLineNumber+1] -Match $regexTime) {
                $startDateStr = $matches[1]
            }
            # 3 lines above
            elseif ($logfile[$startLineNumber-3] -Match $regexTime) {
                $startDateStr = $matches[1]
            }
            # 3 lines below
            elseif ($logfile[$startLineNumber+2] -Match $regexTime) {
                $startDateStr = $matches[1]
            }

            $matches.Clear()

            # End time
            # 1 line above
            if ($logfile[$curLineNumber-1] -Match $regexTime) {
                $startDateStr = $matches[1]
            }
            # 1 line below
            elseif ($logfile[$curLineNumber] -Match $regexTime) {
                $endDateStr = $matches[1]
            }
            # 2 lines above
            elseif ($logfile[$curLineNumber-2] -Match $regexTime) {
                $endDateStr = $matches[1]
            }
            # 2 lines below
            elseif ($logfile[$curLineNumber+1] -Match $regexTime) {
                $endDateStr = $matches[1]
            }
            # 3 lines above
            elseif ($logfile[$curLineNumber-3] -Match $regexTime) {
                $endDateStr = $matches[1]
            }
            # 3 lines below
            elseif ($logfile[$curLineNumber+2] -Match $regexTime) {
                $endDateStr = $matches[1]
            }

            $matches.Clear()

            
            if (!$startDateStr -or !$endDateStr) {
                continue
            }


            if ($startDateStr) {
                # Sun Mar 14 23:34:00 2021
                # Thu Apr  1 01:41:21 2021
                $startDateArr = $startDateStr -Split '\s+'
                $month        = (([Array]::indexOf($months, $startDateArr[1].ToString().Trim()) + 1).ToString()).PadLeft(2, '0')
                $day          = $startDateArr[2].ToString().Trim().PadLeft(2, '0')
                $conStartStr  = $startDateArr[4].ToString().Trim() + '-' + $month + '-' + $day + ' ' + $startDateArr[3].ToString().Trim()
                $startDate    = Get-Date -Date $conStartStr
            }

            if ($endDateStr) {
                # Sun Mar 14 23:34:00 2021
                # Thu Apr  1 01:41:21 2021
                $endDateArr = $endDateStr -Split '\s+'
                $month      = (([Array]::indexOf($months, $endDateArr[1].ToString().Trim()) + 1).ToString()).PadLeft(2, '0')
                $day        = $endDateArr[2].ToString().Trim().PadLeft(2, '0')
                $conEndStr  = $endDateArr[4].ToString().Trim() + '-' + $month + '-' + $day + ' ' + $endDateArr[3].ToString().Trim()
                $endDate    = Get-Date -Date $conEndStr
            }

            if ($startDate -and $endDate) {
                $duration = New-Timespan -Start $startDate -End $endDate
                $durations += $duration
            }

            # Does the sorted FFT size order match the actual order?
            $isOrderEqual = @(Compare-Object $foundFFTSizesIteration $selectedFFTSizesArray -SyncWindow 0).Length -eq 0

            $iterations += @{
                'startString'             = $startDateStr
                'endString'               = $endDateStr
                'startDate'               = $startDate.ToString('yyyy-MM-dd HH:mm:ss')
                'endDate'                 = $endDate.ToString('yyyy-MM-dd HH:mm:ss')
                'duration'                = $duration
                'startLineNumber'         = $startLineNumber
                'endLineNumber'           = $curLineNumber
                'numberOfFFTSizes'        = $foundFFTSizesIteration.Length
                'numberOfFFTSizesUnique'  = $foundFFTSizesUnique.Length
                'allTestedFFTSizes'       = ($foundFFTSizesIteration | ForEach-Object -Process { if ($_ % 1024 -eq 0) { (($_/1024).ToString()+"K") } else { $_ } }) -Join ', '
                'allTestedFFTSizesUnique' = ($foundFFTSizesUnique | sort | ForEach-Object -Process { if ($_ % 1024 -eq 0) { (($_/1024).ToString()+"K") } else { $_ } }) -Join ', '
                'isFFTSizeOrderIsEqual'   = $isOrderEqual
            }

           
            # Restart the iteration
            $startOfNewIteration = $true
            $startLineNumber = $curLineNumber
            $foundFFTSizesUnique = @()
            $foundFFTSizesIteration = @()
        }
    }
}



if ($detectedTestModesFFT.Length -eq 0) {
    Write-Host ('')
    Write-Host ('----------------------------------------------------------------------------') -ForegroundColor Cyan
    Write-Host -NoNewline ('Log file analyzed: ..... ') -ForegroundColor Cyan
    Write-Host ($filePath) -ForegroundColor Yellow
    Write-Host -NoNewline ('Selected Test Mode: .... ') -ForegroundColor Cyan
    Write-Host ($testMode) -ForegroundColor Yellow
    Write-Host -NoNewline ('Selected FFT Preset: ... ') -ForegroundColor Cyan
    Write-Host ($fftPreset) -ForegroundColor Yellow
    Write-Host ('----------------------------------------------------------------------------') -ForegroundColor Cyan
    Write-Host ('')
}


Write-Host ('The various iterations:') -ForegroundColor Blue
Write-Host ('-----------------------') -ForegroundColor Blue

for ($i = 1; $i -le $iterations.Length; $i++) {
    $entry = $iterations[$i-1]

    Write-Host ('')
    Write-Host ('Iteration ' + $i) -ForegroundColor Yellow
    Write-Host ('----------------------------------------------------------------------------') -ForegroundColor Cyan
    Write-Host ('Found all FFT sizes for this iteration') -ForegroundColor Cyan
    #Write-Host -NoNewline ('Approximate Starting Time: .................. ') -ForegroundColor Cyan
    #Write-Host ($entry['startString']) -ForegroundColor Green
    #Write-Host -NoNewline ('Approximate Ending Time: .................... ') -ForegroundColor Cyan
    #Write-Host ($entry['endString']) -ForegroundColor Green
    Write-Host -NoNewline ('Approximate Starting Time: .................. ') -ForegroundColor Cyan
    Write-Host ($entry['startDate']) -ForegroundColor Green
    Write-Host -NoNewline ('Approximate Ending Time: .................... ') -ForegroundColor Cyan
    Write-Host ($entry['endDate']) -ForegroundColor Green
    Write-Host -NoNewline ('Approximate Duration: ....................... ') -ForegroundColor Cyan
    Write-Host ($entry['duration']) -ForegroundColor Green
    Write-Host -NoNewline ('Starting Line: .............................. ') -ForegroundColor Cyan
    Write-Host ($entry['startLineNumber']) -ForegroundColor Green
    Write-Host -NoNewline ('Ending Line: ................................ ') -ForegroundColor Cyan
    Write-Host ($entry['endLineNumber']) -ForegroundColor Green
    Write-Host -NoNewline ('Number of FFT Sizes in this iteration: ...... ') -ForegroundColor Cyan
    Write-Host ($entry['numberOfFFTSizes']) -ForegroundColor Green
    Write-Host -NoNewline ('Unqiue number of FFT Sizes in this iteration: ') -ForegroundColor Cyan
    Write-Host ($entry['numberOfFFTSizesUnique']) -ForegroundColor Green
    Write-Host -NoNewline ('Is the order of the FFT sizes the same: ..... ') -ForegroundColor Cyan
    
    if ($entry['isFFTSizeOrderIsEqual']) {
        Write-Host ('YES') -ForegroundColor Green
    }
    else {
        Write-Host ('NO') -ForegroundColor Red
    }
    
    # Print out the found FFT sizes if the order is not equal
    if (!$entry['isFFTSizeOrderIsEqual']) {
        Write-Host ('')
        Write-Host ('The order in which the FFT sizes were tested until all of them appeared:') -ForegroundColor Cyan
        Write-Host ($entry['allTestedFFTSizes']) -ForegroundColor Green
        Write-Host ('')
        Write-Host ('The sorted and unique FFT sizes in this iteration:') -ForegroundColor Cyan
        Write-Host ($entry['allTestedFFTSizesUnique']) -ForegroundColor Green
    }

    Write-Host ('')
}


Write-Host ('')
Write-Host ('')
Write-Host ('Summary') -ForegroundColor Blue
Write-Host ('----------------------------------------------------------------------------') -ForegroundColor Cyan
Write-Host -NoNewline ('Log file analyzed: ..... ') -ForegroundColor Cyan
Write-Host ($filePath) -ForegroundColor Yellow


if ($autodetectedTestMode) {
    Write-Host -NoNewline ('Detected Test Mode: ........... ') -ForegroundColor Cyan
    Write-Host ($detectedTestModesFFT -Join ' or ') -ForegroundColor Yellow
}
else {
    Write-Host -NoNewline ('Selected Test Mode: ........... ') -ForegroundColor Cyan
    Write-Host ($testMode) -ForegroundColor Yellow    
}

if ($autodetectedFftPreset) {
    Write-Host -NoNewline ('Detected FFT Preset: .......... ') -ForegroundColor Cyan
    Write-Host ($fftPreset) -ForegroundColor Yellow
}
else {
    Write-Host -NoNewline ('Selected FFT Preset: .......... ') -ForegroundColor Cyan
    Write-Host ($fftPreset) -ForegroundColor Yellow   
}

if ($autodetectedNumberOfThreads) {
    Write-Host -NoNewline ('Detected Number of Threads: ... ') -ForegroundColor Cyan
    Write-Host ($numberOfThreads) -ForegroundColor Yellow
}
else {
    Write-Host -NoNewline ('Selected Number of Threads: ... ') -ForegroundColor Cyan
    Write-Host ($numberOfThreads) -ForegroundColor Yellow   
}


if ($detectedTestModesFFT.Length -gt 1) {
    Write-Host ('')
    Write-Host ('Warning! More than one possible test mode found!') -ForegroundColor Red
}


Write-Host ('----------------------------------------------------------------------------') -ForegroundColor Cyan

Write-Host ('')
Write-Host ('The duration of the various iterations:') -ForegroundColor Cyan
Write-Host ('---------------------------------------') -ForegroundColor Cyan

$padLeftLength = ($durations.Length).ToString().Length

for ($i = 1; $i -le $durations.Length; $i++) {
    $entry = $durations[$i-1]
    Write-Host -NoNewline ($i.ToString().PadLeft($padLeftLength, '0') + ': ') -ForegroundColor Cyan
    Write-Host ($entry.ToString()) -ForegroundColor Green
}

Write-Host ('--------------------------') -ForegroundColor Cyan
Write-Host -NoNewline ('Minimum duration: ') -ForegroundColor Cyan
Write-Host (($durations | Measure -Min).Minimum) -ForegroundColor Green
Write-Host -NoNewline ('Maximum duration: ') -ForegroundColor Cyan
Write-Host (($durations | Measure -Max).Maximum) -ForegroundColor Green
Write-Host ('--------------------------') -ForegroundColor Cyan