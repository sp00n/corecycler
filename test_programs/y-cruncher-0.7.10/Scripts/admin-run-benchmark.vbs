'Used by HWBOT Submitter to run y-cruncher as admin when requested by the user.

Set UAC = CreateObject("Shell.Application")
UAC.ShellExecute "run-benchmark.cmd", "", "", "runas", 1
