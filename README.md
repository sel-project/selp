![SEL Logo](http://i.imgur.com/jPfQuZ0.png)

__Windows and Linux manager for SEL servers and generic Minecraft and Minecraft: Pocket Edition command-line utilities__


## Requirements

SEL Manager and SEL itself are written in [D](https://dlang.org/) and they need the [DMD Compiler](https://dlang.org/dmd-windows.html) to be compiled. The installation is very easy and you can find more on the [download page](https://dlang.org/download.html).

Additionally, the Linux's install script uses the wget command, you can install it using `sudo apt-get install wget` if you haven't it already.

## Installation

#### Windows

Download [install.bat](https://raw.githubusercontent.com/sel-project/sel-manager/sel-server-2/install.bat) and run it as administrator.

#### Linux

Download [install.sh](https://raw.githubusercontent.com/sel-project/sel-manager/sel-server-2/install.sh) and run it as superuser.

```
wget https://raw.githubusercontent.com/sel-project/sel-manager/sel-server-2/install.sh
sudo bash install.sh
```

## Available commands

`sel <command> [options]`

`sel <server> <command> [options]`

**Jump to**: [about](#about), [build](#build), [connect](#connect),

* about

	`sel about <server> [--json]`
	
	Prints informations about a server.
	
* build

 	`sel build <server> [-release] [dub-options]`
	
	Compiles a server using [dub](https://code.dlang.org/getting_started).
	
	The options will be passed to the compiler.
	For example, you can use `--compiler=ldc2` to compile using [LDC](https://wiki.dlang.org/LDC) or `-release` to compile in release mode.
	
* connect

	`sel connect <server> [--ip=localhost] [--port=28232] [--name=<server>] [--password=] [--main=true] [--loop]`
	
	Connects a node to an hub.

	Available options:

	* ip

		```
		--ip=192.168.1.24
		--ip=::1
		--ip=sel.example.com
		```

		Indicates the ip of the hub. If not specified the node will try to connect to the local machine using the address `127.0.0.1`.

	* port

		Indicates the port of the hub.

	* name

		Indicates the name of the node that will be used by the hub and other nodes connected to it to identify this node.
		It should be lowercase and composed only by latin letters and numbers.
		
	* password
	
		Password of the hub, if required.

	* main

		Indicates whether or not the hub should send newly connected players to the node (`-main=true`) or not (`-main=false`). If not the hub will only send players to the node when transferred, either via command or node's plugin.
		This option is set to `true` if not specified.
	
* console

	`sel console <ip>[:port=19134] [-protocol=2]`
	
	Connects to a server using the [external console](https://sel-project.github.io/sel-utils/externalconsole/2.html) protocol with the indicated version, if the server supports it and has it enabled.

* delete

	`sel delete <server> [delete-files=true]`
	
	Deletes a server from the SEL Manager's list and, optionally, from the device.
	
	:warning: This action cannot be undone!
	
* init

	`sel init <server> [--type=lite] [--path=sel/<server>] [--version=latest] [--user=sel-project] [--repo=sel-server] [-edu] [-realm] [--local]`
	
	Creates a new SEL Server, giving it a new name that will be used with other commands to manage it.
	
	Available types:
	
	* hub
		
		The network part of a SEL server. It can work as a proxy and it's started using the `sel start` command. An hub alone doesn't provide what is needed to a server to fully work and it will need at least one connected node to work properly.
	
	* node
	
		The gameplay-related part of a SEL server. It needs to be connected to an hub in order to work, action that can be done using the `sel connect` command.
	
	* lite
	
		A lite server is composed by an hub and a node that run on a single application using message-passing instead of sockets. It can be started using `sel start`.
		
	Available options:
	
	* path
	
		```
		--path=.
		--path=../example
		--path=%appdata%/example
		```
	
		Specifies the installation path for the server. By default it's `Documents\sel\<server>` on Windows and `~/sel/<server>` on Linux. If the path already exists every file needed by SEL will be overwritten.
	
	* version
	
		Specifies the version of SEL Server to be used. It can be a version in format `major.minor.patch` (e.g. `--version=1.0.0`), `latest` (for the latest version), `none` (nothing will be downloaded and the source code should be moved in the installation folder manually) or a branch, for example `~master` or `~test-new-api`.
	
	* user
	
	* repo
	
	* edu
	
		Indicates that the server is used for Minecraft: Education Edition. This version is easier to use, having less configuration options.
		
	* realm
	
		Indicates that the server is used as a realm, with only one world and no plugins.
	
* list

	`sel list`
	
	Prints a list of the servers managed by SEL Manager on the device.
	
* locate

	`sel locate <server>`
	
	Prints the location of a server managed by SEL Manager.
	
	On linux systems it can be used to cd to the server: `cd $(sel locate example)`.
	
* open

	`sel open <server>`
	
	Opens the system's file explorer to the location of the server.
	
* ping

	`sel ping <ip>[:port] [-json] [-raw]`
	
	Performs a ping to a Minecraft or a Minecraft: Pocket Edition server and prints the obtained informations.

	Available options:

	* json

		Prints the received informations in JSON format.

	* raw

		Prints the received informations without parsing them (in JSON for Minecraft and in semicolon-separated format in Minecraft: Pocket Edition).

	* game

		`-game=pc` or `-game=pe`

		Specifies the game to ping. If no game is specified both Minecraft and Minecraft: Pocket Edition are pinged.

	* send-timeout

		Specifies the socket's send timeout in milliseconds.

	* recv-timeout

		Specifies the socket's receive timeout in milliseconds.
	
* query

	`sel query <ip>[:port] [-json]`
	
	Performs a [query](http://wiki.vg/Query) to a Minecraft or a Minecraft: Pocket Edition server which support the protocol and has it enabled. If no port is given either port 25565 (Minecraft's default port) and 19132 (Minecraft: Pocket Edition's default port) will be used.
	
	The `-json` switch will print the informations in json format.
	
* rcon

	`sel rcon <ip>[:port=25575] <password>`
	
	Connects to a Minecraft or Minecraft: Pocket Edition server using the [RCON](http://wiki.vg/RCON) protocol.

* shortcut (posix only)

	`sel shortcut <server>`

	Creates a shortcut to a server to easily run server-related commands.

	```
	sel shortcut example
	example build
	example start
	```

	:warning: This command must be executed as superuser.

* social

	`sel social <ip>[:port]`

	Retrieves and prints social (website and social accounts) informations about a SEL server or a server that supports the social JSON protocol.
	
* start

	`sel start <server> [--loop]`
	
	Starts an hub or a full SEL Server.
	
	The `-loop` switch will restart the server when it's stopped without being killed.
	
* update
	
	`sel update <server> [--version=latest] [--user=current] [--repo=current]`
	
	Changes the version of a SEL Server. The version/user/repo format is the same specified in the [init](#init) command.
