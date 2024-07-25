--------------
- CORECYCLER -
--------------
https://github.com/sp00n/corecycler



WHAT?
-----
A PowerShell script to test the stability for single core loads.
Modern CPUs can adjust their CPU frequency depending on their load, and have mechanism that allow them to clock higher
when only one or two cores are loaded ("boost" clock).
With this script you can test the stability for each core, which helps you to validate if your Ryzen "PBO" resp.
"Curve Optimizer" settings are actually stable. It also works to test Intel's "Active-Core" Turbo-Boost settings.



HOW?
----
Double click the "Run CoreCycler.bat" file.



DANGER!
-------
I do not take any responsibility if you damage your computer using this script! Temperatures while using a stress test
can become very high, especially if the cooling solution is suboptimal. And although modern CPUs should automatically
throttle or shut down if the temperature becomes too high, there's a certain risk of degradation for your chip if it's
running at it max temperature for a prolonged period of time.
Also, using PBO *technically* voids the warranty of a Ryzen CPU, so use it at your own risk!



DESCRIPTION
-----------
This script will run your selected stress test (Prime95, y-cruncher, Aida64) with only one (or two) worker threads and
sets the affinity of the stress test process alternating to each physical core, cycling through all of them. This way
you can test the stability of your Curve Optimizer / Active-Core setting for each core individually, much more
thoroughly than e.g. with Cinebench or the Windows Repair, and much easier than manually setting the affinity of the
process via the Task Manager.
It will still need a lot of time though. If, for example, you're after a 12h "prime-stable" setup which is common for 
regular overclocks, you'd need to run this script for 12x12 = 144 hours on a 5900X with 12 physical cores, because 
each core is tested individually, and so each core also needs to complete this 12 hour test individually. Respectively, 
on a 5600X with its 6 physical cores this would be "only" 6x12 = 72 hours.

Unfortunately such an all-core stress test with Prime95 or other stress tests is not effective for testing single-core
stability, because the cores cannot boost as high if all of them are stres tested, and therefore you won't be able to
detect instabilities that only occur at a higher clock speed.
For example, with my 5900X I was able to run a Prime95 all-core stress test for 24 hours with an additional Boost
Override of +75 MHz and a Curve Optimizer setting of -30 on all cores. However, when using this script, and with +0 MHz
Boost Override, I needed to go down to -9 on one core to have it run stable (on the other hand, another core was still
happy with a -30 setting even in this case).

When you start the script for the first time, it will generate a config.ini file, in which you can then change various
settings, e.g. which mode the stress test program should run in (e.g. for Prime95 SSE, AVX, AVX2, CUSTOM, where SSE
causes the highest boost clock, because it's the lightest load on the processor of all the settings), how long an
individual core should be stressed for before it cycles to the next one, if certain cores should be ignored, etc.
For each setting there's also a description in the config.ini file.

As a starting point for Ryzen systems you could set the Curve Optimizer to e.g. -15 or -20 for each core and then wait
and see which core runs through fine and which throws an error. Then you could increase the setting for those that have
thrown an error by e.g. 2 or 3 points (e.g. from -15 to -13) and decrease those that were fine by 2 or 3 further into
the negative (-15 to -17). Once you've crossed a certain point however there is no way around modifying the value by a
single point up/down  and letting the script run for a long time to find the very last instabilities.

By the way, by default it is configured so that only one thread is stressed for each core if Hyperthreading / SMT is
enabled, as the boost clock is higher this way, compared to if both (virtual) threads would be stressed. But there is a
setting in the config.ini to enable testing with two threads as well.



INCLUDED SOFTWARE
-----------------
The script itself is a PowerShell script, but it uses other, inlcuded software to do the actual stress testing, for
example Prime95, y-cruncher, and Intel's Linpack.
You can also move your own copy of the stress test programs in to the respective folders in the /test_programs/
directory (e.g. /test_programs/p95 for Prime95, /test_programs/y-cruncher for y-cruncher, etc).
For example if you want to be on the safe side (good choice!) or want to use a dedicated version.
However be aware that the stress test programs can change their settings from time to time, so if you include a version
that has not been tested with CoreCycler, it may not work as intended or not even start at all.

To download Prime95, go to the official site: at https://www.mersenne.org/download/
To download y-cruncher, go to the official site at: http://www.numberworld.org/y-cruncher/#Download
To download Linpack, go to the official site at: https://www.intel.com/content/www/us/en/developer/tools/oneapi/onemkl-download.html
To download older versions of Linpack, you can use the Internet Archive:
https://web.archive.org/web/*/https://registrationcenter-download.intel.com/*
And filter for e.g. "mkl .exe" to get a list of all archived Linpack versions.

CoreCycler also supports Aida64, which however is NOT directly included due to its license.
You need to download the >>>Portable Engineer<<< version yourself and extract it into the /test_programs/aida64 folder.
It has to be the Portable Engineer version, because the regular "Extreme" edition doesn't support starting the stress
test from the command line.
To download Aida64 Portable Engineer, go to the official site at: https://www.aida64.com/downloads
You can use the trial version for up to 30 days, which should give you enough time to find your stable settings.



TROUBLESHOOTING & FAQ
---------------------
Q: What does "Set to Core X (CPU Y)" (e.g. "Set to Core 6 (CPU 12)") mean?
A: CoreCycler - as the name suggests - cycles through your cores and informs you on which core it is currently running.
   When Hyperthreading / Simultaneous Multithreading (SMT) is enabled, each physical core contains two "virtual" CPUs,
   effectively doubling the amount of CPUs available to you (at least for Ryzen and Intel P-Cores).
   Since Cores and CPUs generally start with 0 (zero-based), as seen in the BIOS and in the Task Manager, CoreCycler
   also uses this format. So "Core 0" means your first core, and "CPU 0" the first virtual CPU.
   "Core 6 (CPU 12)" respectively means it's running on the 7th core (remember, zero-based!) and 13th virtual CPU.

Q: The core I select in Ryzen Master isn't the same as here!
A: Yes, Ryzen Master starts it's core numbering with 1. Only AMD knows why, it's not the industry standard.
   In the BIOS the core numbering starts with a 0, in Windows Task Manager the CPU numbering starts with a 0, in Intel
   Extreme Tuning Utility the numbering starts with 0, and therefore also in CoreCycler the numbering starts with a 0.
   Blame AMD for breaking this naming convention.

Q: My computer crashes when running this program!
A: Very likely your Boost or Curve Optimizer setting is unstable. Reduce your clock speed, increase your voltage, resp.
   change the CO setting to a higher or more precisely less negative value (e.g. from -15 to -12) and try again.

Q: How long should I run this for?
A: Basically as long as you can. If you aim for a "12h prime-stable setup", you'd need to run every single core for 
   12 hours, which for a processor with 12 cores like the 5900X would sum up to a total of 144 hours of stress testing.
   Of course, you can also settle for less - that's totally up to you.

Q: Which setting should I use to test?
A: Short answer: as many as cou can.
   Long answer: I've defaulted this to Prime95 without AVX and AVX2 and "Huge" FFTs. The reason behind this is that 
   this *should* produce the least amount of heat and therefore the highest boost clock. But you should eventually run 
   all of the tests to make sure that you're really error free.
   Also switching from Prime95 to y-cruncher, Linpack or Aida64 produces different load scenarios, which can prove useful
   in detecting instabilities.
   For y-cruncher, "04-P4P" and "19-ZN2 ~ Kagari" seem to produce the fastest results, at least for Ryzen CPUs.

Q: Why are you using SSE? AVX stresses the CPU much more!
A: Yes, AVX/AVX2/AVX512 does stress the CPU more than the SSE mode. However, it is exactly this additional load on the
   core wich prevents the boost clock from reaching its maximum (because it is temperature and load dependent), and so
   you can't really detect these edge cases which eventually can cause an error sooner or later. So, while being
   somewhat counterintuitive, the SSE mode with its lighter load is actually the one that can find stability problems,
   which tests using AVX/AVX2 simply cannot.
   On the other hand, not testing the AVX/AVX2 instructions will also not test the transistors associated with these
   instructions, so you're not "fully" testing your chip. So you should indeed test both scenarios, light load / SEE
   and heavy load with AVX/AVX2.
   You can change the mode to SSE, AVX, AVX2 or AVX512 for Prime95 and Aida64 in the config.ini, and for y-cruncher you
   can select different test modes which require different instruction sets.

Q: What settings can I change?
A: The /configs/default.config.ini contains details and an explanation for each setting, so take a look there.

Q: When starting the tool I see a "FATAL ERROR: Could not access the Windows Performance Process Counter!" message!
A: For some stress test programs the script needs to check the CPU utilization to determine if here has been an error.
   For this, the tool requires the Windows Performance Process Counter (PerfProc) to work correctly. It may have been
   disabled, you can check this with either 
   lodctr.exe /q:PerfProc
   or with 
   reg.exe query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\PerfProc\Performance /s
   and look for a "Disable Performance Counters" entry with a value larger than 0.
   There are various tutorials on how to re-enable the Performance Counter on the web, here are some links:
   https://leansentry.zendesk.com/hc/en-us/articles/360038645792-How-to-Fix-performance-counter-issues
   https://docs.microsoft.com/en-us/troubleshoot/windows-server/performance/manually-rebuild-performance-counters

   I've also included a batch file in the /tools/ directory (enable_performance_counter.bat), which _should_ perform 
   all these actions for you, but no guarantees that it will actually work!

Q: When starting the tool I see a "FATAL ERROR: Could not get the localized Performance Process Counter name!" message!
A: See above. You probably need to re-enable the Windows Performance Process Counter (PerfProc).

Q: When starting the tool I see a "FATAL ERROR: .NET could not be found or the version is too old!" message!
A: This tool requires the .NET Framework with at least version 3.5. You can download .NET here:
   https://dotnet.microsoft.com/en-us/download/dotnet-framework/net481
   https://dotnet.microsoft.com/en-us/download/dotnet

Q: I have overclocked my RAM and I see errors when running this program, but I'm sure my CPU is fine!
A: The errors may actually come from your overclocked RAM and not your CPU directly.
   Best practice for overclocking is to separately test the memory overclock and the CPU overclock, i.e. test your CPU 
   while your memory runs at stock speeds.
   After you're sure that both overclocks are stable on their own, you can combine them and check for instabilities 
   again.

Q: My script freezes! It appears to be running but I see no new output!
A: PowerShell scripts seem to freeze when you select some text or click with the mouse into the terminal window (which
   selects the current position of your cursor). Try to hit Return and see if the execution continues.
   See e.g. here: https://stackoverflow.com/questions/3204423/long-running-powershell-script-freezes




LICENSE AND ALL THAT STUFF
--------------------------
This script is provided under the "CC BY-NC-SA" Creative Commons license. Or to put it in their words:
"This license lets others remix, adapt, and build upon your work non-commercially, as long as they credit you and 
license their new creations under the identical terms."


You are free to:
   Share - copy and redistribute the material in any medium or format
   Adapt - remix, transform, and build upon the material
   The licensor cannot revoke these freedoms as long as you follow the license terms.

Under the following terms:
   - Attribution
     You must give appropriate credit, provide a link to the license, and indicate if changes were made.
     You may do so in any reasonable manner, but not in any way that suggests the licensor endorses you or your use.
   - NonCommercial
     You may not use the material for commercial purposes.
   - ShareAlike
     If you remix, transform, or build upon the material, you must distribute your contributions under the same license
     as the original.
   - No additional restrictions
     You may not apply legal terms or technological measures that legally restrict others from doing anything the
     license permits.



You can find the full license text here:
https://creativecommons.org/licenses/by-nc-sa/4.0/
https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode

And also in the included LICENSE file.


So feel free to share it, modify it and adapt it to your needs, but if you find any bugs, errors or have improvement 
ideas, please let me know at:

https://github.com/sp00n/corecycler



The licenses of all included programs remain unaffected by this and retain their original, included license!
- Prime95
  https://www.mersenne.org/legal/

- y-cruncher
  http://www.numberworld.org/y-cruncher/license.html

- Linpack (current version)
  https://www.intel.com/content/www/us/en/developer/tools/oneapi/onemkl.html

- Linpack (all included versions)
  2024.2.1.0 (2024.2.0.662) - https://web.archive.org/web/20240722184607/https://registrationcenter-download.intel.com/akdlm/IRC_NAS/7816a8cf-2378-4d49-bfa6-6013a3d7be6a/w_onemkl_p_2024.2.0.662_offline.exe
  2021.4.1.0 (2021.4.0.640) - https://web.archive.org/web/20211115133152/https://registrationcenter-download.intel.com/akdlm/irc_nas/18230/w_onemkl_p_2021.4.0.640_offline.exe
  2019.0.3.1 (2019.3.203)   - https://web.archive.org/web/20190509182800/https://registrationcenter-download.intel.com/akdlm/irc_nas/tec/15247/w_mkl_2019.3.203.exe
  2018.0.3.1 (2018.3.011)   - https://web.archive.org/web/20220412021802/https://registrationcenter-download.intel.com/akdlm/irc_nas/9752/w_mklb_p_2018.3.011.zip

- WriteConsoleToWriteFileWrapper
  https://github.com/sp00n/WriteConsoleToWriteFileWrapperDll?tab=MIT-1-ov-file
  https://github.com/sp00n/WriteConsoleToWriteFileWrapperExe?tab=MIT-1-ov-file

- BoostTester.sp00n
  https://github.com/sp00n/BoostTester?tab=Unlicense-1-ov-file

- CoreTunerX
  https://github.com/CXWorld/CoreTunerX?tab=License-1-ov-file

- PBO2Tuner
  https://www.overclock.net/threads/corecycler-tool-for-testing-curve-optimizer-settings.1777398/post-29337788



Happy testing!
sp00n
