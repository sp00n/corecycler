<##
 # Get the duration of each iteration for a specific FFT size
 # Helps to find a suitable value for the runtimePerCore setting
 #>

# The directory of where the log file can be found
# You can use an absolute or relative path from where this script is located
$logFileDirectory = '..\logs\'


# The name of the log file to analyze
$logFileName = ''


# The script tries to autodetect the FFT preset and test mode used in the log file, but you can specify them here
$testMode  = '' # SSE, AVX, AVX
$fftPreset = '' # Smallest, Small, Large, Huge, All


# The FFT size array to be able to analyze the log file
$allFFTSizes = @{
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
        Smallest   = @{ Min =    4; Max =    20; }  # Originally   4 ...   21
        Small      = @{ Min =   40; Max =   240; }  # Originally  36 ...  248
        Large      = @{ Min =  448; Max =  8192; }  # Originally 426 ... 8192
        Huge       = @{ Min = 8960; Max = 32768; }  # New addition
        All        = @{ Min =    4; Max = 32768; }
        Moderate   = @{ Min = 1344; Max =  4096; }
        Heavy      = @{ Min =    4; Max =  1344; }
        HeavyShort = @{ Min =    4; Max =   160; }
    }

    AVX = @{
        Smallest   = @{ Min =    4; Max =    21; }  # Originally   4 ...   21
        Small      = @{ Min =   36; Max =   240; }  # Originally  36 ...  248
        Large      = @{ Min =  448; Max =  8192; }  # Originally 426 ... 8192
        Huge       = @{ Min = 8960; Max = 32768; }  # New addition
        All        = @{ Min =    4; Max = 32768; }
        Moderate   = @{ Min = 1344; Max =  4096; }
        Heavy      = @{ Min =    4; Max =  1344; }
        HeavyShort = @{ Min =    4; Max =   160; }
    }

    AVX2 = @{
        Smallest   = @{ Min =    4; Max =    21; }  # Originally   4 ...   21
        Small      = @{ Min =   36; Max =   240; }  # Originally  36 ...  248
        Large      = @{ Min =  448; Max =  8192; }  # Originally 426 ... 8192
        Huge       = @{ Min = 8960; Max = 51200; }  # New addition
        All        = @{ Min =    4; Max = 51200; }
        Moderate   = @{ Min = 1344; Max =  4096; }
        Heavy      = @{ Min =    4; Max =  1344; }
        HeavyShort = @{ Min =    4; Max =   160; }
    }
}


# The full path of the log file
$folder   = (Resolve-Path $logFileDirectory).ToString()
$folder  += $(if ($folder.SubString($folder.Length-1) -ne '\') { '\' })
$filePath = (Resolve-Path $logFileDirectory).ToString() + $logFileName

if (!$filePath -or $filePath.Length -eq 0 -or !(Test-Path $filePath -PathType leaf)) {
    Write-Host('ERROR: Could not find the provided log file!') -ForegroundColor Red
    Write-Host($filePath) -ForegroundColor Yellow

    Read-Host -Prompt 'Press Enter to exit'
    exit
}


$allFFTSizesInLogfile       = @()
$allUniqueFFTSizesInLogfile = @()
$selectedFFTSizesArray      = @()
$allFFTSizesInLogifle       = @()
$foundFFTSizesIteration     = @()
$foundFFTSizesUnique        = @()
$foundTestModesMinMax       = @()
$detectedTestModesFFT       = @()
$detectedFftPreset          = $null
$autodetectedTestMode       = $false
$autodetectedFftPreset      = $false
$foundTestModesMinMax       = @()
$detectedTestModesFFT       = @()
$testModesToCheck           = @()
$logfile                    = Get-Content $filePath
$regexFFT                   = '^Self\-test (\d+)K passed!$'
$regexTime                  = '^\[(.*)]$'
$curLineNumber              = 0
$startLineNumber            = 1
$startOfNewIteration        = $true
$months                     = @('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec')
$iterations                 = @()
$durations                  = @()


# Autodetect the FFT size
if (!$testMode -or $testMode.Length -eq 0 -or !$fftPreset -or $fftPreset.Length -eq 0) {
    Write-Host ('')
    Write-Host ('Autodetecting the used FFT preset and test mode in the log file') -ForegroundColor Blue
    Write-Host ('---------------------------------------------------------------') -ForegroundColor Blue

    Write-Host -NoNewline ('Analyzing log file: ....... ') -ForegroundColor Cyan
    Write-Host ($filePath) -ForegroundColor Yellow



    # If no preset was provided 
    foreach ($line in $logfile) {
        if ($line -match $regexFFT) {
            $allFFTSizesInLogfile += [Int]$matches[1]
        }
    }

    $allUniqueFFTSizesInLogfile = $allFFTSizesInLogfile | Select -Unique

    $minFoundFFTSize = ($allFFTSizesInLogfile | Measure -Min).Minimum
    $maxFoundFFTSize = ($allFFTSizesInLogfile | Measure -Max).Maximum


    Write-Host -NoNewline ('Minimum FFT Size found: ... ') -ForegroundColor Cyan
    Write-Host ($minFoundFFTSize) -ForegroundColor Yellow
    Write-Host -NoNewline ('Maximum FFT Size found: ... ') -ForegroundColor Cyan
    Write-Host ($maxFoundFFTSize) -ForegroundColor Yellow

    # If there was a test mode provided
    if ($testMode -and $testMode.Length -gt 0) {
        $testModesToCheck += $testMode
    }
    else {
        # First check SSE, then AVX, then AVX2
        $testModesToCheck = @('SSE', 'AVX', 'AVX2')
    }

    # No FFT preset was provided
    if (!$fftPreset -or $fftPreset.Length -eq 0) {
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
    if ($testMode -and $testMode.Length -gt 0 -and !$detectedTestModesFFT.Contains($testMode)) {
        Write-Host ('ERROR: The provided test mode doesn''t match the data in the log file!') -ForegroundColor Red

        Read-Host -Prompt 'Press Enter to exit'
        exit
    }


    if (!$testMode -or $testMode.Length -eq 0) {
        $autodetectedTestMode = $true
        
        Write-Host -NoNewline ('Autodetected Test Mode: ... ') -ForegroundColor Cyan
        Write-Host ($detectedTestModesFFT -Join ' or ') -ForegroundColor Yellow        
    }
    else {
        Write-Host -NoNewline ('Provided Test Mode: ....... ') -ForegroundColor Cyan
        Write-Host ($testMode) -ForegroundColor Yellow
    }


    if ($detectedFftPreset -and $detectedFftPreset.Length -gt 0) {
        $autodetectedFftPreset = $true

        Write-Host -NoNewline ('Autodetected FFT Preset: .. ') -ForegroundColor Cyan
        Write-Host ($fftPreset) -ForegroundColor Yellow
    }
    else {
        Write-Host -NoNewline ('Provided FFT Preset: ...... ') -ForegroundColor Cyan
        Write-Host ($fftPreset) -ForegroundColor Yellow
    }

    Write-Host ('')
    
    if ($detectedTestModesFFT.Length -gt 1) {
        Write-Host ('Warning! More than one possible test mode found!') -ForegroundColor Red
        Write-Host ('')
    }

    Write-Host ('')


    # No test mode was provided, and there's more than one possible candidate
    # Set the test mode to the first entry if no test mode was provided
    if (!$testMode -or $testMode.Length -eq 0) {
        $testMode = $detectedTestModesFFT[0]
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


foreach ($line in $logfile) {
    $curLineNumber++

    if ($line -match $regexFFT) {
        $fftSize = [Int]$matches[1]
        $matches.Clear()

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

        # If all FFT sizes have been found for this iteration
        if ($foundFFTSizesUnique.Length -eq $selectedFFTSizesArray.Length) {
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
            if ($logfile[$startLineNumber-1] -match $regexTime) {
                $startDateStr = $matches[1]
            }
            # 1 line below
            elseif ($logfile[$startLineNumber] -match $regexTime) {
                $startDateStr = $matches[1]
            }
            # 2 lines above
            elseif ($logfile[$startLineNumber-2] -match $regexTime) {
                $startDateStr = $matches[1]
            }
            # 2 lines below
            elseif ($logfile[$startLineNumber+1] -match $regexTime) {
                $startDateStr = $matches[1]
            }
            # 3 lines above
            elseif ($logfile[$startLineNumber-3] -match $regexTime) {
                $startDateStr = $matches[1]
            }
            # 3 lines below
            elseif ($logfile[$startLineNumber+2] -match $regexTime) {
                $startDateStr = $matches[1]
            }

            $matches.Clear()

            # End time
            # 1 line above
            if ($logfile[$curLineNumber-1] -match $regexTime) {
                $startDateStr = $matches[1]
            }
            # 1 line below
            elseif ($logfile[$curLineNumber] -match $regexTime) {
                $endDateStr = $matches[1]
            }
            # 2 lines above
            elseif ($logfile[$curLineNumber-2] -match $regexTime) {
                $endDateStr = $matches[1]
            }
            # 2 lines below
            elseif ($logfile[$curLineNumber+1] -match $regexTime) {
                $endDateStr = $matches[1]
            }
            # 3 lines above
            elseif ($logfile[$curLineNumber-3] -match $regexTime) {
                $endDateStr = $matches[1]
            }
            # 3 lines below
            elseif ($logfile[$curLineNumber+2] -match $regexTime) {
                $endDateStr = $matches[1]
            }

            $matches.Clear()

            
            if (!$startDateStr -or !$endDateStr) {
                continue
            }


            if ($startDateStr) {
                # Sun Mar 14 23:34:00 2021
                $startDateArr = $startDateStr.Split(' ')
                $month        = (([Array]::indexOf($months, $startDateArr[1]) + 1).toString()).PadLeft(2, '0')
                $day          = $startDateArr[2].toString().PadLeft(2, '0')
                $conStartStr  = $startDateArr[4] + '-' + $month + '-' + $day + ' ' + $startDateArr[3]
                $startDate    = Get-Date -Date $conStartStr
            }

            if ($endDateStr) {
                # Sun Mar 14 23:34:00 2021
                $endDateArr = $endDateStr.Split(' ')
                $month      = (([Array]::indexOf($months, $endDateArr[1]) + 1).toString()).PadLeft(2, '0')
                $day        = $endDateArr[2].toString().PadLeft(2, '0')
                $conEndStr  = $endDateArr[4] + '-' + $month + '-' + $day + ' ' + $endDateArr[3]
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
                'allTestedFFTSizes'       = $foundFFTSizesIteration -Join ', '
                'allTestedFFTSizesUnique' = ($foundFFTSizesUnique | sort) -Join ', '
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
    Write-Host -NoNewline ('Detected Test Mode: .... ') -ForegroundColor Cyan
    Write-Host ($detectedTestModesFFT -Join ' or ') -ForegroundColor Yellow
}
else {
    Write-Host -NoNewline ('Selected Test Mode: .... ') -ForegroundColor Cyan
    Write-Host ($testMode) -ForegroundColor Yellow    
}

if ($autodetectedFftPreset) {
    Write-Host -NoNewline ('Detected FFT Preset: ... ') -ForegroundColor Cyan
    Write-Host ($fftPreset) -ForegroundColor Yellow
}
else {
    Write-Host -NoNewline ('Selected FFT Preset: ... ') -ForegroundColor Cyan
    Write-Host ($fftPreset) -ForegroundColor Yellow   
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