--------------
- CORECYCLER -
--------------
https://github.com/sp00n/corecycler



WHAT?
-----
A stability test script for PBO & Curve Optimizer stability testing on AMD Ryzen processors.
It probably also works on Intel, but I haven't tested that.



HOW?
----
Double click the "Run CoreCycler.bat" file.



DANGER!
-------
I do not take any responsibility if you damage your computer using this script! Temperatures with Prime95 can become 
very high, especially if the cooling solution is suboptimal. And although Ryzen should automatically shut down if the 
temperature becomes too high, it's really not advisable to let it come to this and you should try to stay below 90°C.
Also, PBO technically voids the warranty of your CPU, so use it at your own risk!



INCLUDED SOFTWARE
-----------------
The script itself is a PowerShell script, but it uses the included Prime95 version 30.8b17 to actually do the stress 
testing. You can also move your own copy of Prime95 into the /test_programs/p95 directory if you want to be on the 
safe side (good choice!).
To download Prime95, go to the official site at https://www.mersenne.org/download/ (however, the 30.5 version used 
here is at the time of writing only available through their forum).

Beginning with version 0.8 it also supports Aida64 and y-Cruncher, however it does NOT include Aida64 by default.
You need to download the >>>Portable Engineer<<< version yourself and extract into the /test_programs/aida64 folder. It 
has to be the Portable Engineer version, because the regular "Extreme" edition doesn't support starting the stress test 
from the command line.
To download Aida64 Portable Engineer, go here: https://www.aida64.com/downloads
You can use the trial version for up to 30 days, which should give you enough time to find your stable setting for PBO.

Y-Cruncher is included, and can be downloaded here: http://www.numberworld.org/y-cruncher/#Download



DEUTSCH
-------
Mit diesem kleinen Script kann man die Einstellungen des Curve Optimizer für jeden einzelnen Kern seiner CPU auf
Stabilität überprüfen. Das Script startet Prime95 mit einem Worker-Thread und setzt die "Affinity" von Prime95
abwechselnd auf die einzelnen Kerne, d.h. es wird immer nur ein einziger Kern gleichzeitig belastet, wodurch sehr gut
die Stabilität der Curve Optimizer Einstellung ausgetestet werden kann.
Die bisherigen Stabilitätstests mit PBO und dem Curve Optimizer waren entweder nicht zuverlässig (Cinebench, 
Windows Repair) oder mit sehr viel Arbeit verbunden (manuell die Affinity über den Task Manager setzen, warten, neu 
setzen, etc) oder gleich beides. Mit diesem Script braucht man eigentlich nur noch Zeit - davon allerdings doch recht 
viel. Da immer nur ein Kern gleichzeitig getestet werden kann, bräuchte man für einen 12 Stunden "Prime-stable" 
Stabilitätstest, wie man ihn bei normalen Overclocks gerne macht, bereits 12x12 = 144 Stunden bei einem 5900X. Bei 
einem 5600X mit seinen 6 physischen Kernen dann entsprechend "nur" 6x12 = 72 Stunden.
Solch ein All-Core Test mit Prime95 ist leider nicht effektiv mit dem Curve Optimizer, da die Kerne dann nicht so hoch 
takten können, und man so eventuelle Instabilitäten nicht erkennen kann. Bei meiner CPU konnte ich z.B. den Curve 
Optimizer auf -30 auf allen Kernen und +75 MHz Boost stellen und damit problemlos 24 Stunden Prime95 durchlaufen lassen,
während ich bei diesem Einzeltest dann bei +0 MHz Boost einen der Kerne nur noch mit -9 stabil laufen lassen konnte 
(ein anderer dagegen lief auch beim Einzeltest noch mit -30 weiter).

Beim ersten Start des Scripts wird automatisch eine config.ini angelegt (die config.default.ini wird kopiert). In 
dieser kann man einige Parameter ändern, z.B. welcher Modus beim Testen ausgeführt wird (SSE, AVX, AVX2, CUSTOM, wobei 
SSE den höchsten Takt produziert, da es die CPU am wenigsten belastet), wie lange ein einzelner Kern getestet werden 
soll, bevor es zum nächsten geht, ob bestimmte Kerne ignoriert werden sollen, etc. Für jedes Setting ist in der Datei 
auch eine Beschreibung vorhanden.

Als Startpunkt am Anfang könnte man im Curve Optimizer jeden Kern auf z.B. auf -15 oder -20 setzen und dann schauen, 
welcher Kern durchläuft und welcher davon einen Fehler wirft. Die Kerne mit Fehler könnte man dann z.B. um 2 oder 3 
Punkte nach oben setzen (also z.B. von -15 auf -13), die fehlerfreien dagegen 2 oder 3 weiter ins Negative (-15 auf 
-17). Ab einem gewissen Punkt kommt man aber nicht daran vorbei, nur noch um einen Punkt nach oben/unten zu korrigieren 
und das Tool sehr lange laufen zu lassen, um auch die letzten Instabilitäten herauszufiltern.

Es ist übrigens beabsichtigt, dass bei aktiviertem Hyperthreading / SMT nur der erste Thread eines jeden Kerns belastet 
wird, da dabei ein höherer Takt erreicht wird, wie wenn beide (virtuellen) Threads eines Kerns belastet würden. Man 
kann in der config.ini allerdings auch die Anzahl der Threads auf 2 setzen, wenn man das möchte, dann werden beide 
belastet.



ENGLISH
-------
This little script will run Prime95 with only one worker thread and sets the affinity of the Prime95 process 
alternating to each physical core, cycling through all of them. This way you can test the stability of your Curve 
Optimizer setting for each core individually, much more thoroughly than e.g. with Cinebench or the Windows Repair, and 
much easier than manually setting the affinity of the process via the Task Manager.
It will still need a lot of time though. If, for example, you're after a 12h "prime-stable" setup which is common for 
regular overclocks, you'd need to run this script for 12x12 = 144 hours on a 5900X with 12 physical cores, because 
each core is tested individually, and so each core also needs to complete this 12 hour test individually. Respectively, 
on a 5600X with its 6 physical cores this would be "only" 6x12 = 72 hours.
Unfortunately such an all-core stress test with Prime95 is not effective for testing Curve Optimizer settings, because 
the cores cannot boost as high if all of them are stres tested, and therefore you won't be able to detect instabilities 
that occur at a higher clock speed. For example, with my CPU I was able to run a Prime95 all-core stress test for 
24 hours with an additional Boost Override of +75 MHz and a Curve Optimizer setting of -30 on all cores. However, when 
using this script, and with +0 MHz Boost Override, I needed to go down to -9 on one core to have it run stable (on the 
other hand, another core was still happy with a -30 setting even in this case).

When you start the script for the first time, it will copy the included config.default.ini to config.ini, in which you 
then can change various settings, e.g. which mode Prime95 should run in (SSE, AVX, AVX2, CUSTOM, where SSE causes the 
highest boost clock, because it's the lightest load on the processor of all the settings), how long an individual core 
should be stressed for before it cycles to the next one, if certain cores should be ignored, etc. For each setting 
there's also a description in the config.ini file.

As a starting point you could set the Curve Optimizer to e.g. -15 or -20 for each core and then wait and see which core 
runs through fine and which throws an error. Then you could increase the setting for those that have thrown an error by 
e.g. 2 or 3 points (e.g. from -15 to -13) and decrease those that were fine by 2 or 3 further into the negative (-15 to 
-17). Once you've crossed a certain point however there is no way around modifying the value by a single point up/down 
and letting the script run for a long time to find the very last instabilities.

By the way, it is intended that only one thread is stressed for each core if Hyperthreading / SMT is enabled, as the 
boost clock is higher this way, compared to if both (virtual) threads would be stressed. However, there is a setting 
in the config.ini to enable two threads as well.



TROUBLESHOOTING & FAQ
---------------------
Q: My computer crashes when running this program!
A: Very likely your Curve Optimizer setting is unstable. Change the settings to a higher resp. less negative value
   (e.g. from -15 to -12) and try again.

Q: How long should I run this for?
A: Basically as long as you can. If you aim for a "12h prime-stable setup", you'd need to run every single core for 
   12 hours, which for a processor with 12 cores like the 5900X would sum up to a total of 144 hours of stress testing.
   Of course, you can also settle for less—that's totally up to you.

Q: Which setting should I use?
A: Short answer: all of them.
   Long answer: I've defaulted this to Prime95 without AVX and AVX2 and "Huge" FFTs. The reason behind this is that 
   this *should* produce the least amount of heat and therefore the highest boost clock. But you should eventually run 
   all of the tests to make sure that you're really error free.
   Also switching from Prime95 to y-Cruncher or Aida64 produces different load scenarios, which can prove useful in 
   detecting instabilities.

Q: Why are you using SSE? AVX stresses the CPU much more!
A: Yes, AVX/AVX2 does stress the CPU more than the SSE mode. However, it is exactly this additional load on the core 
   wich prevents the boost clock from reaching its maximum (because it is temperature and load dependent), and so you 
   can't really detect these edge cases which eventually can cause an error sooner or later. So, while being somewhat 
   counterintuitive, the SSE mode with its lighter load is actually the one that finds the most stability problems.
   However, you can change the mode to AVX or AVX2 in the config.ini if you're happy with only AVX/AVX2 stability.

Q: What settings can I change?
A: The config.ini contains details and an explanation for each setting, so take a look there.

Q: When starting the tool I only see a "FATAL ERROR: Could not access the Windows Performance Process Counter!" message!
A: The tool requires the Windows Performance Process Counter (PerfProc) to work correctly. It may have been disabled, 
   you can check this with either 
   lodctr.exe /q:PerfProc
   or with 
   reg.exe query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\PerfProc\Performance /s
   and look for a "Disable Performance Counters" entry with a value larger than 0.
   There are various tutorials on how to re-enable the Performance Counter on the web, here are some links:
   https://leansentry.zendesk.com/hc/en-us/articles/360038645792-How-to-Fix-performance-counter-issues
   https://docs.microsoft.com/en-us/troubleshoot/windows-server/performance/manually-rebuild-performance-counters

   I've also included a batch file in the /tools/ directory (enable_performance_counter.bat), which _should_ perform 
   all these actions for you, but no guarantees that it will actually work!

Q: When starting the tool I only see a "FATAL ERROR: Could not get the localized Performance Process Counter name!" message!
A: See above. You probably need to re-enable the Windows Performance Process Counter (PerfProc).

Q: When starting the tool I only see a "FATAL ERROR: .NET could not be found or the version is too old!" message!
A: This tool requires the .NET Framework with at least version 3.5. You can download it here:
   https://docs.microsoft.com/en-us/dotnet/framework/install/dotnet-35-windows-10

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

You can find the full license text here:
https://creativecommons.org/licenses/by-nc-sa/4.0/
https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode


So feel free to share it, modify it and adapt it to your needs, but if you find any bugs, errors or have improvement 
ideas, please let me know at 

https://github.com/sp00n/corecycler


The licenses of all included programs remain unaffected by this and retain their original, included license!


Happy testing!
sp00n
