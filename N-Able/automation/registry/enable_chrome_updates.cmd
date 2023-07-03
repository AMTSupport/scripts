@echo off
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Google\Update" /v Update{8A69D345-D564-463C-AFF1-A69D9E530F96} /t REG_DWORD /d 1 /f
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Google\Update" /v Update{4DC8B4CA-1BDA-483E-B5FA-D3C12E15B62D} /t REG_DWORD /d 1 /f
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Google\Update" /v Update{8BA986DA-5100-405E-AA35-86F34A02ACBF} /t REG_DWORD /d 1 /f
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Google\Update" /v UpdateDefault /t REG_DWORD /d 1 /f