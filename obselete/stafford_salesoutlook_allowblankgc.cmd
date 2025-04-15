@echo off
 
reg add "HKCU\SOFTWARE\Microsoft\Office\9.0\Outlook\Options\SalesOutlook" /v AllowBlankGC /t REG_DWORD /d 0 /f