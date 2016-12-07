
title SEL Manager installation
cd %appdata%
bitsadmin /transfer "SEL Download" https://raw.githubusercontent.com/sel-project/sel-manager/master/manager.d %appdata%\manager.d
rdmd --build-only manager.d
rename manager.exe sel.exe
del manager.d
if exist "C:\Windows\System32\sel.exe" del C:\Windows\System32\sel.exe
if exist "C:\Windows\SysWOW64\sel.exe" del C:\Windows\SysWOW64\sel.exe
copy sel.exe C:\Windows\System32
if exist "C:\Windows\SysWOW64" copy sel.exe C:\Windows\SysWOW64
del sel.exe
sel update utils
pause
