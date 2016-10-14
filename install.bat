
cd %appdata%
bitsadmin /transfer "SEL Download" https://raw.githubusercontent.com/sel-project/sel-manager/master/manager.d manager.d
rdmd --build-only manager.d
rename manager.exe sel.exe
del manager.d
del C:\Windows\System32\sel.exe
move sel.exe C:\Windows\System32
