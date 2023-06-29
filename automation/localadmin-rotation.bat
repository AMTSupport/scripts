@echo off
Setlocal
REM Change the following two lines for each client
If "%1" == "" GOTO ERROR
REM check for default arg 
IF "%1" == "-logfile" GOTO ERROR

set password=%1
echo LocalAdmin password script - Password = %1


net user LocalAdmin %password% >nul
if %errorlevel% == 0 GOTO R1

net user LocalAdmin %password% /add /Y >nul
net localgroup administrators LocalAdmin /add >nul
wmic UserAccount where Name='LocalAdmin' set PasswordExpires=False >nul
wmic useraccount where name='LocalAdmin' set disabled=false >nul
if %errorlevel% == 0 goto R2
echo Something went wrong
goto END

:ERROR
Echo Update Failed - Invalid password argument %1
goto END

:R1
Echo Password updated
goto END

:R2
Echo Account Added

:END

ENDLOCAL

