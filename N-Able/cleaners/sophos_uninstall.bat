net stop "SAVService"
net stop "Sophos AutoUpdate Service"
"C:\Program Files\Sophos\Sophos Endpoint Agent\uninstallcli.exe"
:Sophos AutoUpdate XG Endpoint (5.13.51) Server (5.13.51)
MsiExec.exe /qn /X{7CD26A0C-9B59-4E84-B5EE-B386B2F7AA16} REBOOT=ReallySuppress
MsiExec.exe /qn /X{BCF53039-A7FC-4C79-A3E3-437AE28FD918} REBOOT=ReallySuppress
MsiExec.exe /qn /X{9D1B8594-5DD2-4CDC-A5BD-98E7E9D75520} REBOOT=ReallySuppress
MsiExec.exe /qn /X{AFBCA1B9-496C-4AE6-98AE-3EA1CFF65C54} REBOOT=ReallySuppress
MsiExec.exe /qn /X{E82DD0A8-0E5C-4D72-8DDE-41BB0FC06B3E} REBOOT=ReallySuppress
MsiExec.exe /qn /X{72E136F7-3751-422E-AC7A-1B2E46391909} REBOOT=ReallySuppress
:Sophos Anti-Virus Endpoint 10.8.2.342
MsiExec.exe /qn /X{8123193C-9000-4EEB-B28A-E74E779759FA} REBOOT=ReallySuppress
MsiExec.exe /qn /X{36333618-1CE1-4EF2-8FFD-7F17394891CE} REBOOT=ReallySuppress
MsiExec.exe /qn /X{DFDA2077-95D0-4C5F-ACE7-41DA16639255} REBOOT=ReallySuppress
MsiExec.exe /qn /X{CA3CE456-B2D9-4812-8C69-17D6980432EF} REBOOT=ReallySuppress
MsiExec.exe /qn /X{CA524364-D9C5-4804-92DE-2800BDAC1AA4} REBOOT=ReallySuppress
MsiExec.exe /qn /X{3B998572-90A5-4D61-9022-00B288DD755D} REBOOT=ReallySuppress
MsiExec.exe /qn /X{4BAF6F55-FFE4-4A3A-8367-CC2EBB0F11C3} REBOOT=ReallySuppress
MsiExec.exe /qn /X{BA8752FE-75E5-43DD-9913-23509EFEB409} REBOOT=ReallySuppress
:Sophos Anti-Virus Server 10.8.1.316
MsiExec.exe /qn /X{72E30858-FC95-4C87-A697-670081EBF065} REBOOT=ReallySuppress
MsiExec.exe /qn /X{66967E5F-43E8-4402-87A4-04685EE5C2CB} REBOOT=ReallySuppress
MsiExec.exe /qn /X{2519A41E-5D7C-429B-B2DB-1E943927CB3D} REBOOT=ReallySuppress
MsiExec.exe /qn /X{6654537D-935E-41C0-A18A-C55C2BF77B7E} REBOOT=ReallySuppress
:Sophos System Protection
MsiExec.exe /qn /X{934BEF80-B9D1-4A86-8B42-D8A6716A8D27} REBOOT=ReallySuppress
MsiExec.exe /qn /X{1093B57D-A613-47F3-90CF-0FD5C5DCFFE6} REBOOT=ReallySuppress
:Sophos Network Threat Protection Endpoint (1.6.196) Server (1.5.213)
MsiExec.exe /qn /X{604350BF-BE9A-4F79-B0EB-B1C22D889E2D} REBOOT=ReallySuppress
:Sophos Health Endpoint (2.0.7.80) Server (2.0.6.828)
MsiExec.exe /qn /X{A5CCEEF1-B6A7-4EB4-A826-267996A62A9E} REBOOT=ReallySuppress
MsiExec.exe /qn /X{D5BC54B8-1DA1-44F4-AE6F-86E05CDB0B44} REBOOT=ReallySuppress
MsiExec.exe /qn /X{E44AF5E6-7D11-4BDF-BEA8-AA7AE5FE6745} REBOOT=ReallySuppress
:Sophos Diagnostic Utility Endpoint (1.21.0.0) Server (1.21.0.0)
MsiExec.exe /qn /X{4627F5A1-E85A-4394-9DB3-875DF83AF6C2} REBOOT=ReallySuppress
:Heartbeat
MsiExec.exe /qn /X{DFFA9361-3625-4219-82C2-9EF011E433B1} REBOOT=ReallySuppress
:Sophos Management Communications System Endpoint (4.8.5) Server (4.8.5)
MsiExec.exe /qn /X{A1DC5EF8-DD20-45E8-ABBD-F529A24D477B} REBOOT=ReallySuppress
MsiExec.exe /qn /X{1FFD3F20-5D24-4C9A-B9F6-A207A53CF179} REBOOT=ReallySuppress
MsiExec.exe /qn /X{D875F30C-B469-4998-9A08-FE145DD5DC1A} REBOOT=ReallySuppress
MsiExec.exe /qn /X{2C14E1A2-C4EB-466E-8374-81286D723D3A} REBOOT=ReallySuppress
:Sophos Management Communications System Endpoint (4.9.204)
"C:\Program Files (x86)\Sophos\Management Communication System\Endpoint\uninstall.exe" /uninstall /quiet
"C:\Program Files\Sophos\Management Communication System\Endpoint\uninstall.exe" /uninstall /quiet
:UI
MsiExec.exe /qn /X{D29542AE-287C-42E4-AB28-3858E13C1A3E} REBOOT=ReallySuppress
:Sophos Endpoint Firewall Endpoint (1.1.0.0) Server (1.1.0.0)
MsiExec.exe /qn /X{2831282D-8519-4910-B339-2302840ABEF3} REBOOT=ReallySuppress
:Sophos Endpoint Self Help Endpoint (2.0.103) Server (2.0.103)
MsiExec.exe /qn /X{4EFCDD15-24A2-4D89-84A4-857D1BF68FA8} REBOOT=ReallySuppress
MsiExec.exe /qn /X{BB36D9C2-6AE5-4AB2-BC91-ECD247092BD8} REBOOT=ReallySuppress
:Sophos Lockdown 7.1.1.1
MsiExec.exe /qn /X{77F92E90-ED4F-4CFF-8F60-3E3E4AEB705C} REBOOT=ReallySuppress
:Sophos File Scanner Endpoint (1.3.10) Server (1.2.0)
"C:\Program Files\Sophos\Sophos File Scanner\Uninstall.exe" 
:Sophos Standalone Engine Endpoint (1.2.15) Server (1.2.3)
"C:\Program Files\Sophos\Sophos Standalone Engine\uninstall.exe" 
:Sophos ML Engine
"C:\Program Files\Sophos\Sophos ML Engine\uninstall.exe"
:Sophos Endpoint Agent 2.0.0 
"C:\Program Files\Sophos\Sophos Endpoint Agent\uninstallgui.exe" 
:Sophos Clean Endpoint (3.8.5.111) Server (3.8.4.189)
"C:\Program Files (x86)\Sophos\Clean\uninstall.exe" 
:Sophos Endpoint Defense Endpoint (2.0.0.394) Server (1.5.1.6)
"C:\Program Files\Sophos\Endpoint Defense\uninstall.exe"
:HMPA (managed)
"C:\Program Files (x86)\HitmanPro.Alert\hmpalert.exe" /uninstall /quiet
:HMPA 1.0.0.699
"C:\Program Files (x86)\HitmanPro.Alert\uninstall.exe" 
:HMPA 3.7.14.265
"C:\Program Files\HitmanPro\HitmanPro.exe" /uninstall /quiet