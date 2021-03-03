CORECYCLER
----------
Test script for PBO & Curve Optimizer stability testing



QUICK INSTRUCTIONS
------------------
Double click the "Run CoreCycler.bat" file.



INCLUDED SOFTWARE
-----------------
The script itself is a PowerShell script, but it uses the included Prime95 version 30.4b9 to actually do the stress 
testing. If you don't trust me (and you shouldn't!), you can move your own copy of Prime95 into the /p95 directory.
To download Prime95, go to the official site at https://www.mersenne.org/download/ (however, the 30.4 version used 
here is at the time of writing this only available through their forum).



DEUTSCH
-------
Mit diesem kleinen Script kann man die Einstellungen des Curve Optimizer für jeden einzelnen Kern seiner CPU auf
Stabilität überprüfen. Das Script startet Prime95 mit einem Worker-Thread und setzt die "Affinity" von Prime95
abwechselnd auf den einzelnen Kern, d.h. es wird immer nur ein einziger Kern gleichzeitig belastet, wodurch sehr gut
die Stabilität ausgetestet werden kann.
Die bisherigen Stabilitätstests mit PBO und dem Curve Optimizer waren entweder nicht zuverlässig (Cinebench, 
Windows Repair) oder mit sehr viel Arbeit verbunden (manuell die Affinity über den Task Manager setzen, warten, neu 
setzen, etc) oder gleich beides. Mit diesem Script braucht man eigentlich nur noch Zeit - allerdings sehr viel Zeit.
Da immer nur ein Kern getestet wird, und man z.B. 12h "Prime-stable" erreichen will, müsste man jeden Kern für 12h 
testen. Bei z.B. dem 5900X mit 12 Kernen / 24 Threads würde das dann 12*12, also 144 Stunden dauern, damit jeder Kern 
für 12 Stunden auf Stabilität getestet wurde.
Ein All-Core Test mit Prime95 ist leider nicht effektiv mit dem Curve Optimizer, da die Kerne dann nicht so hoch 
takten können, und man so eventuelle Instabilitäten nicht erkennen kann. Bei meiner CPU konnte ich z.B. -30 auf allen 
Kernen und +75 MHz Boost problemlos 24 Stunden mit Prime95 laufen lassen, während ich bei diesem Einzeltest dann einen 
der Kerne nur auf -9 und Boost +0 stabil laufen lassen konnte (ein anderer dagegen lief auch dann noch mit -30 weiter).

In der config.ini kann man einige Parameter ändern, z.B. welcher Modus beim Testen ausgeführt wird (SSE, AVX, AVX2, 
wobei SSE den höchsten Takt produziert), wie lange ein einzelner Kern getestet werden soll, bevor es zum nächsten geht, 
ob bestimmte Kerne ignoriert werden sollen, etc. Für jedes Setting ist dort auch eine Beschreibung vorhanden.

Es ist übrigens beabsichtigt, dass bei aktiviertem Hyperthreading / SMT nur der erste Thread eines jeden Kerns belastet 
wird, da dabei ein höherer Takt erreicht wird, wie wenn beide (virtuellen) Threads eines Kerns belastet würden. Man 
kann in der config.ini allerdings auch die Anzahl der Threads auf 2 setzen, wenn man das möchte, dann werden beide 
belastet.



ENGLISH
-------
This little script will run Prime95 with only one worker thread and sets the affinity of the Prime95 process 
alternating to each physical core. This way you can test the stability of your Curve Optimizer setting for each core 
individually, much more thoroughly than e.g. with Cinebench or the Windows Repair, and much easier than manually 
setting the affinity of the process via the Task Manager.
It will still need a lot of time though. If for example you're after a 12h "prime-stable" setup, you'd need to run 
this script for 12*12 = 144 hours on a 5900X with 12 cores / 24 threads, because each core is tested individually, 
and so each core also needs to complete this 12 hour test individually.
Unfortunately such an all-core test with Prime95 is not effective with using the Curve Optimizer, because the cores 
cannot boost as high if all cores are stressed, and therefore you won't be able to detect instabilities that occur at 
a higher clock speed. For example, with my CPU I was able to run Prime95 for 24 hours with a -30 setting on all cores 
and a Boost Override of +75. However, when using this script, I needed to go down to -9 on one core and set the Boost 
to +0 to have it run stable (on the other hand, another core was still happy with -30).

Included is a config.ini file, in which you can change various settings, e.g. which mode Prime95 should run in (SSE, 
AVX, AVX2, where SSE causes the highest boost clock), how long an individual core should be stressed for before it 
cycles to the next one, if certain cores should be ignored, etc. Each setting also has a description in that file.

By the way, it is intended that only one thread is stressed for each core if Hyperthreading / SMT is enabled, as the 
boost clock is higher this way, compared to if both (virtual) threads would be stressed. However, there is a setting 
in the config.ini to enable two threads as well.