
title SEL Manager installation
cd %appdata%
bitsadmin /transfer "SEL Download" https://raw.githubusercontent.com/sel-project/sel-manager/master/manager.d %appdata%\manager.d
rdmd --build-only manager.d
rename manager.exe sel.exe
del manager.d
if exist "%windir%\System32\sel.exe" del %windir%\System32\sel.exe
if exist "%windir%\SysWOW64\sel.exe" del %windir%\SysWOW64\sel.exe
copy sel.exe %windir%\System32
if exist "%windir%\SysWOW64" copy sel.exe %windir%\SysWOW64
del sel.exe
pause
