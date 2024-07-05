Linpack Xtreme v1.1.5 by Regeneration

Linpack Xtreme is a console front-end with the latest build of Linpack
(Intel Math Kernel Library Benchmarks 2018.3.011). Linpack is a benchmark
and the most aggressive stress testing software available today. Best used
to test stability of overclocked PCs. Linpack tends to crash unstable PCs
in a shorter period of time compared to other stress testing applications.

Linpack solves a dense (real*8) system of linear equations (Ax=b), measures
the amount of time it takes to factor and solve the system, converts that
time into a performance rate, and tests the results for accuracy. The
generalization is in the number of equations (N) it can solve, which is
not limited to 1000. Linpack uses partial pivoting to assure the accuracy
of the results.

Linpack Xtreme was created because Prime95 is no longer effective like it
used to be. LinX, IntelBurnTest, OCCT use outdated Linpack binaries from
2012. Modern hardware requires modern stress testing methodology with
support for the latest instructions sets.

Make sure to keep an eye on the temperatures as Linpack generates excessive
amount of stress like never seen before.

Revision history:
v1.1.5
- Additional optimization for AMD CPUs.

v1.1.4
- Fixed a crash on AMD Ryzen processors.
- Updated CPUID HWMonitor to version 1.43.

v1.1.3
- Improved detection of AMD Ryzen 3000 series.
- Some bug fixes.

v1.1.2
- AVX2 is now forced on AMD Ryzen processors.
- Updated CPUID HWMonitor to version 1.41.

v1.1.1
- Added /residualcheck command-line switch. This improves error detection
on legacy Intel CPUs. It is enabled by default on AMD CPUs.

v1.1.0
- Added stress test profiles of 14GB and 30GB.
- Added quick and extended benchmark profiles.
- Fixed false positive hardware errors.
- Some minor changes.

v1.0.0
- Improved error detection.
- Improved thread count detection.
- Changed benchmark preset to run just once but for a longer period.

v0.9.6
- Fixed core count detection for multi-processor systems.

v0.9.5
- Improved cross-platform benchmarking.

v0.9.4
- Improved thread affinity.
- Disabled HT/SMT on the benchmark mode.
- Updated CPUID HWMonitor to version 1.37.

v0.9.3
- Additional optimization for AMD CPUs.

v0.9.2
- Added several optimizations for AMD CPUs.
- Improved multithreading efficiency for the benchmark.
- Fixed insufficient memory error on 32-bit systems.
- Updated CPUID HWMonitor to version 1.36.
- Some minor changes.

v0.9.1
- Improved benchmark accuracy.

v0.9
- Some bug fixes.

v0.8
- Added benchmark feature.
- Added option to specify amount of threads.
- Changed the project name.

v0.7
- Fixed a bug with error detection on AMD CPUs.

v0.6
- Linpack now stops and beeps if any errors are detected.

v0.5
- Separated x86 and x64 code.
- Reduced maximum allowed memory for x86.

v0.4
- Added option to use 6GB of RAM.
- Added option for unlimited runs.
- Added option to disable sleep mode.
- Added CPUID HWMonitor to the package.

v0.3
- Added support for AMD CPUs.

v0.2
- Fixed a problem with affinity and thread allocation.

v0.1
- Initial release.

Website:
https://www.ngohq.com/linpack-xtreme.html
