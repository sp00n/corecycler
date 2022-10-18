In this directory are some helpful tools that you might find interesting.



analyze_prime95_logfile.ps1
---------------------------
This is a PowerShell script that can be used to analyze Prime95 log files.
It will try to determine the amount of FFT iterations and how long the various iterations have taken.

Usage example:
.\analyze_prime95_logfile.ps1 "E:\CoreCycler\logs\Prime95_2022-10-18_13-01-31_SSE_ALL_FFT_4K-32768K.txt"



BoostTester.exe
---------------
https://github.com/jedi95/BoostTester

Simple tool for generating loads that should trigger maximum CPU boost clocks.

This is helpful to check the maximum possible boost clock on the various cores. It generates a very light load so the cores
should boost as high as they can. Unfortunately there is no error checking for this tool.



CoreTunerX.exe
--------------
https://github.com/CXWorld/CoreTunerX

This tool reads the Windows CPU cores rating from the event viewer and saves them in a text document (results.txt).
The read out values have no unit and are only used to compare the cores of this one CPU with each other, not with other CPUs.

How to interpret the performance numbers:
The higher the score, the higher the priority from the windows sheduler.



enable_performance_counter.bat
------------------------------
Sometimes the Perfomance Counters can corrupt on a Windows installation, which breaks CoreCycler.
This batch file tries to fix/reset these Performance Counters.
It requires Administator priviliges and will try to get them / complain otherwise.



PBO2Tuner
---------
by PJVol from overclock.net
https://www.overclock.net/threads/5800x3d-owners.1798046/page-85#post-29009118
https://drive.google.com/file/d/1YHB68AGz0TVBDlN8Mj-UBOmB4XBVmkfe/view

This tool can set the Curve Optimizer, PPT, TDC, EDC, Max Boost and FIT Scalar values from within Windows.
It can be run either with a GUI or using the command line (e.g. on startup), as seen below.

It also works for Ryzen 5800X3D processors, where CO values are normally not available in the BIOS.


Command Line Usage:
"C:/path/to/PBO/PBO2Tuner.exe" <CO0> <CO1> <CO2> ... <COn> <PPT> <TDC> <EDC> <Fmax> <Scalar>

If using command line arguments, a full set of CO value arguments is mandatory. The other values are optional.
Limits for PPT, TDC, EDC, anf Fmax are not applied if set to zero or omitted.
A Scalar value of 0 is applied if provided (not the default 1 value).
Any additional command line arguments are ignored.

Examples: (8-core CPU)
PBO2Tuner.exe -5 -5 -5 -5 -5 -5 -5 -5 0 0 100        // Set CO to -5 on all cores and EDC to 100A
PBO2Tuner.exe -5 -5 -5 -5 -5 -5 -5 -5 100            // CO -5, PPT 100A
PBO2Tuner.exe -5 -5 -5 -5 -5 -5 -5 -5 0 90 0 4400 0  // CO -5, TDC 90A, Fmax 4400mhz and Scalar 0
PBO2Tuner.exe -10 -10 -10 -10 -10 -10 -10 -10        // Set only CO values, all cores to -10 