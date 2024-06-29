'Used by HWBOT Submitter to set the platform clock.

Set UAC = CreateObject("Shell.Application")
UAC.ShellExecute "run-bcd-clock.cmd", "", "", "runas", 1
