REM  Routine to copy the local MYOB to the Server for Backup with a log file
Robocopy C:\PremierClassic\Data G:\GROUP\ACCOUNTS\PremierClassic\Backups /S /E /R:2 /W:10 /NP /TEE /LOG:G:\GROUP\ACCOUNTS\PremierClassic\Backups\zMYOBBU.LOG

rem Pause
