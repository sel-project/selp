![SEL Logo](http://i.imgur.com/jPfQuZ0.png)

__Windows and Linux manager for SEL servers and generic Minecraft and Minecraft: Pocket Edition command-line utilities__


## Requirements

SEL Manager and SEL itself are written in [D](https://dlang.org/) and they need the [DMD Compiler](https://dlang.org/dmd-windows.html) to be compiled. The installation is very easy and you can find more on the [download page](https://dlang.org/download.html).

Additionally, the Linux's install script uses the wget command, you can install it using `sudo apt-get install wget` if you haven't it already.

## Installation

#### Windows

Download [install.bat](https://raw.githubusercontent.com/sel-project/sel-manager/master/install.bat) and run it as administrator.

#### Linux

Download [install.sh](https://raw.githubusercontent.com/sel-project/sel-manager/master/install.sh) and run it as superuser.

```
wget https://raw.githubusercontent.com/sel-project/sel-manager/master/install.sh
sudo bash install.sh
```

## Available commands

`sel <command> [<options>]`

* about

	`sel about <server>`
	
	Prints informations about a compiled server, like SEL's version and Minecraft and Minecraft: Pocket Edition supported protocols.
	
* build

 	`sel build <server> [<options>]`
	
	Compiles a server.
	
	The options will be passes to the RDMD compiler.
	For example, you can use `-compiler=ldc` to compile using [LDC](https://wiki.dlang.org/LDC) or `-release` to compile in release mode.
	
	The `-force=false` switch will exit without compiling if an executable file already exists.
	
* connect

	`sel connect <server> [<node-name>=node] [<ip>=127.0.0.1] [<port>=28232] [<main-node>=true]`
	
	Connects a node to an hub.
	
* console

	`sel console <ip>[:<port>]`
	
	Connects to a server using the external console protocol, if the server supports it.
	
	With the `-version` switch is also possible to change the version of the external console. If this is not specified, the latest version supported by SEL is used.
	
* delete

	`sel delete <server> [<delete-files>=true]`
	
	Deletes a server from the SEL Manager's list and, optionally, from the device.
	
	:warning: This action cannot be undone!
	
* init

	`sel init <server> [<type>=full] [<options>]`
	
	Creates a new SEL Server, giving it a new name that will be used with other commands to manage it.
	
	Available types:
	
	* hub
		
		The network part of a SEL Server. It can work as a proxy and is started using the `sel start` command. An hub alone doesn't provide what is needed to a server to work and it will need at least one connected node to work properly.
	
	* node
	
		The world-related part of a SEL Server. It needs to connected to an hub in order to work and that action can be done using the `sel connect` command.
	
	* full
	
		A full server is composed by an hub and a node that runs simultaneosly on the same machine. It can be started using `sel start` and the hub-node connection is done automatically.
		
	Available options:
	
	* path
	
		```
		path=.
		path=../example
		path=%appdata%/example
		```
	
		Specifies the installation path for the server. By default it is `%appdata%\sel\<server-name>` on Windows and `~/sel/<server-name>` on Linux. If the path already exists every file needed by SEL will be overwritten.
	
	* version
	
		Specifies the version of SEL Server to be used. It can be a version in format `major.minor.release` (e.g. `1.0.0`), `latest` (for the latest version) or `none` (nothing will be downloaded and the source code should be moved in the installation folder manually).
	
	* edu
	
		Used only as `-edu` indicates that the server is used for Minecraft: Education Edition. This version is easier to use, having less configuration options.
	
* list

	`sel list`
	
	Prints a list of the servers managed by SEL Manager on the device.
	
* locate

	`sel locate <server>`
	
	Prints the location of a server managed by SEL Manager.
	
	On linux systems it can be used to cd to the server: `cd $(sel locate example)`.
	
* ping

	`sel ping <ip>[:<port>] [<options>]`
	
	Performs a ping to a Minecraft or a Minecraft: Pocket Edition server and prints the obtained informations.
	
	The `-json` switch will print the informations in json format.
	
* query

	`sel query <ip>[:<port>] [<options>]`
	
	Performs a [query](http://wiki.vg/Query) to a Minecraft or a Minecraft: Pocket Edition server which support the protocol and has it enabled. If no port is given either port 25565 (Minecraft's default port) and 19132 (Minecraft: Pocket Edition's default port) will be used.
	
	The `-json` switch will print the informations in json format.
	
* rcon

	`sel rcon <ip>[:<port>=25575] <password>`
	
	Connects to a Minecraft or Minecraft: Pocket Edition server using the [RCON](http://wiki.vg/RCON) protocol.
	
* start

	`sel start <server>`
	
	Starts an hub or full SEL Server.
	
* update

	`sel update sel`
	
	Updates SEL Manager and its installed components.
	
	:warning: This command must be launched with administrator rights to work properly.
	
	`sel update utils`
	
	Updates [sel-utils](https://github.com/sel-project/sel-utils), JSON files and libraries used by SEL.
	
	It's reccomended to run this command every time Minecraft or Minecraft: Pocket Edition is updated, in order to keep SEL servers updated.
	
	`sel update <server> [<version>=latest]`
	
	Changes the version of a SEL Server. The version format is the same specified in the `init` command.
