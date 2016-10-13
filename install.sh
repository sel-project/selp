#!/bin/bash

# download and compile manager
wget https://raw.githubusercontent.com/Kripth/sel-manager/master/manager.d
rdmd --build-only manager.d

# move to /usr/bin/
mv manager sel
mv sel /usr/bin