@echo off
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v DisableOSUpgrade /t REG_DWORD /d 1 /f

reg add "HKLM\Software\Policies\Microsoft\Windows\Gwx" /v DisableGwx /t REG_DWORD /d 1 /f 