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

`sel <command> [options]`

* about

	`sel about <server> [-json]`
	
	Prints informations about a compiled server, like SEL's version and Minecraft and Minecraft: Pocket Edition supported protocols.
	
	The `-json` switch will print the informations in json format.
	
* build

 	`sel build <server> [rdmd-options]`
	
	Compiles a server using [rdmd](https://dlang.org/rdmd.html) tool.
	
	The options will be passed to the compiler.
	For example, you can use `--compiler=ldc2` to compile using [LDC](https://wiki.dlang.org/LDC) or `-release` to compile in release mode.

* clear

	`sel clear <server>`

	Clears a server's cache.
	
* compress

	`sel compress <source> <archive> [-level=6] [-alg=gzip] [-plugin]`
	
	Creates a sel archive.
	
	Available options:
	
	* level
	
		Indicates the level of compression (0-9). If this option is not set the compression level will be 6.
		
	* alg
	
		Indicates the algorithm that will be used for the compression (`gzip` or `deflate`).
		
	* plugin
	
		Indicates that the compression can be used as plugin.
	
* connect

	`sel connect <server> [-ip=localhost] [-port=28232] [-name=<server>] [-password=] [-main=true]`
	
	Connects a node to an hub.

	Available options:

	* ip

		```
		-ip=192.168.1.24
		-ip=::1
		-ip=sel.example.com
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

* convert

	`sel convert <format-from> <format-to> <location-from> [location-to=.]`

	Converts a world to another format.

	Available formats:

	* [Anvil](http://minecraft.gamepedia.com/Anvil_file_format)

		Minecraft's world format since 1.2.

	* [LevelDB](http://minecraft.gamepedia.com/Pocket_Edition_level_format#LevelDB_format)

		Minecraft: Pocket Edition's format since 1.0.0 (also known as 0.17).

	* sel-be

		SEL's format with big-endian data types.

	* sel-le

		SEL's format with little-endian data types.

	* sel

		SEL's format with the machine's endianness.

	:warning: This feature is not fully supported yet and may not work properly

	:warning: Only blocks are converted. Tiles and entities will be supported in the future.
	
* delete

	`sel delete <server> [delete-files=true]`
	
	Deletes a server from the SEL Manager's list and, optionally, from the device.
	
	:warning: This action cannot be undone!
	
* init

	`sel init <server> [type=full] [-version=latest] [-path=sel/<server>] [-edu] [-realm]`
	
	Creates a new SEL Server, giving it a new name that will be used with other commands to manage it.
	
	Available types:
	
	* hub
		
		The network part of a SEL server. It can work as a proxy and it's started using the `sel start` command. An hub alone doesn't provide what is needed to a server to fully work and it will need at least one connected node to work properly.
	
	* node
	
		The gameplay-related part of a SEL server. It needs to be connected to an hub in order to work, action that can be done using the `sel connect` command.
	
	* full
	
		A full server is composed by an hub and a node that run simultaneously on the same machine. It can be started using `sel start` and the hub-node connection is done automatically.
		
	Available options:
	
	* path
	
		```
		-path=.
		-path=../example
		-path=%appdata%/example
		```
	
		Specifies the installation path for the server. By default it's `Documents\sel\<server>` on Windows and `~/sel/<server>` on Linux. If the path already exists every file needed by SEL will be overwritten.
	
	* version
	
		Specifies the version of SEL Server to be used. It can be a version in format `major.minor.release` (e.g. `-version=1.0.0`), `latest` (for the latest version), `none` (nothing will be downloaded and the source code should be moved in the installation folder manually) or `github` (for the latest version from sel-server's github repository).
	
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
		
* plugin

	`sel <server> plugin add <plugin>`
	
		Adds a plugin to a server, if it is a node or a full server. The plugin must be compressed using `sel compress` command with the `-plugin` switch.
		
		The plugin is download from the the [sel-plugins](https://github.com/sel-project/sel-plugins9 repository.
	
	`sel <server> plugin update <plugin>`
	
		Updates a plugin, if it is installed through a .ssa file and in its `package.json` file there's a `release` field.
	
	`sel <server> plugin remove <plugin>`
	
		Removes a plugin if installed through a .ssa file.
	
* query

	`sel query <ip>[:port] [-json]`
	
	Performs a [query](http://wiki.vg/Query) to a Minecraft or a Minecraft: Pocket Edition server which support the protocol and has it enabled. If no port is given either port 25565 (Minecraft's default port) and 19132 (Minecraft: Pocket Edition's default port) will be used.
	
	The `-json` switch will print the informations in json format.
	
* rcon

	`sel rcon <ip>[:port=25575] <password>`
	
	Connects to a Minecraft or Minecraft: Pocket Edition server using the [RCON](http://wiki.vg/RCON) protocol.

* shortcut (Linux only)

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

	`sel start <server> [-loop]`
	
	Starts an hub or a full SEL Server.
	
	The `-loop` switch will restart the server when it's stopped without being killed.
	
* uncompress

	`sel uncompress <archive> <destination>`
	
	Decompress a sel archive created with the `sel compress` command.
	
* update
	
	`sel update utils`
	
	Updates [sel-utils](https://github.com/sel-project/sel-utils), JSON files and libraries used by SEL.
	
	It's reccomended to run this command every time Minecraft or Minecraft: Pocket Edition are updated, in order to avoid SEL servers' deprecation errors.
	
	`sel update <server> [-version=latest]`
	
	Changes the version of a SEL Server. The version format is the same specified in the `init` command.
