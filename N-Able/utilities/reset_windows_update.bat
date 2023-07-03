%Windir%\system32\net.exe stop bits 
%Windir%\system32\net.exe stop wuauserv
%Windir%\system32\net.exe stop cryptsvc
 
reg delete HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate /v AccountDomainSid /f
reg delete HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate /v PingID /f
reg delete HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate /v SusClientId /f
reg delete HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate /v SusClientValidation /f
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" /v LastWaitTimeout /f
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" /v DetectionStartTime /f
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" /v NextDetectionTime /f
 
if exist %Windir%\system32\atl.dll %Windir%\system32\regsvr32.exe /s %Windir%\system32\atl.dll  
if exist %Windir%\system32\jscript.dll %Windir%\system32\regsvr32.exe /s %Windir%\system32\jscript.dll 
if exist %Windir%\system32\softpub.dll  %Windir%\system32\regsvr32.exe /s %Windir%\system32\softpub.dll  
if exist %Windir%\system32\wuapi.dll %Windir%\system32\regsvr32.exe /s %Windir%\system32\wuapi.dll 
if exist %Windir%\system32\wuaueng.dll  %Windir%\system32\regsvr32.exe /s %Windir%\system32\wuaueng.dll  
if exist %Windir%\system32\wuaueng1.dll  %Windir%\system32\regsvr32.exe /s %Windir%\system32\wuaueng1.dll  
if exist %Windir%\system32\wucltui.dll  %Windir%\system32\regsvr32.exe /s %Windir%\system32\wucltui.dll  
if exist %Windir%\system32\wups.dll  %Windir%\system32\regsvr32.exe /s %Windir%\system32\wups.dll  
if exist %Windir%\system32\wups2.dll  %Windir%\system32\regsvr32.exe /s %Windir%\system32\wups2.dll  
if exist %Windir%\system32\wuweb.dll  %Windir%\system32\regsvr32.exe /s %Windir%\system32\wuweb.dll  
if exist %windir%\system32\iuengine.dll %windir%\system32\regsvr32.exe /s iuengine.dll
if exist %windir%\system32\wuauserv.dll %windir%\system32\regsvr32.exe /s wuauserv.dll
if exist %windir%\system32\cdm.dll %windir%\system32\regsvr32.exe /s cdm.dll
if exist %windir%\system32\msxml2r.dll %windir%\system32\regsvr32.exe /s msxml2r.dll
if exist %windir%\system32\msxml3r.dll %windir%\system32\regsvr32.exe /s msxml3r.dll
if exist %windir%\system32\msxml.dll  %windir%\system32\regsvr32.exe /s msxml.dll
if exist %windir%\system32\msxml3.dll %windir%\system32\regsvr32.exe /s msxml3.dll
if exist %windir%\system32\msxmlr.dll %windir%\system32\regsvr32.exe /s msxmlr.dll
if exist %windir%\system32\msxml2.dll %windir%\system32\regsvr32.exe /s msxml2.dll
if exist %windir%\system32\qmgr.dll %windir%\system32\regsvr32.exe /s qmgr.dll
if exist %windir%\system32\qmgrprxy.dll %windir%\system32\regsvr32.exe /s qmgrprxy.dll
if exist %windir%\system32\iuctl.dll %windir%\system32\regsvr32.exe /s iuctl.dll
 
 
del C:\Windows\WindowsUpdate.log /S /Q
rd /s /q %windir%\softwareDistribution
sleep 5
%Windir%\system32\net.exe start cryptsvc
%Windir%\system32\net.exe start bits 
%Windir%\system32\net.exe start wuauserv 

 
sc sdset wuauserv D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)
sc sdset bits D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)
 
wuauclt.exe /resetauthorization
wuauclt.exe /detectnow 
wuauclt.exe /reportnow
 
exit /B 0