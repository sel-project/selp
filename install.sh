#!/bin/bash

# clear components
rm -r ~/.sel/components

# download and compile manager
wget https://raw.githubusercontent.com/sel-project/sel-manager/master/manager.d
rdmd --build-only manager.d

# move to /usr/bin/
mv manager sel
mv sel /usr/bin

# update libraries
sel update libs
