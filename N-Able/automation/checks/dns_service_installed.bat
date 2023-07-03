@echo off
sc query DNS > null
IF %ERRORLEVEL% == 0  echo "Yes - DNS service installed" 
IF not %ERRORLEVEL% ==  0 echo "NO - DNS service NOT installed"