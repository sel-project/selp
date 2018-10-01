module selp.command.server;

import std.algorithm : canFind;
import std.file : exists, read, write, mkdirRecurse;
import std.net.curl : get, download;
import std.path : dirSeparator;

import selp.util : Manager, writeError, find;

import xserial;

struct Server {
	
	enum Type : ubyte {
		
		bedrock,
		selery,
		seleryHub,
		seleryNode,
		
	}
	
	ubyte type;
	string path;
	string version_;
	
}

void server(Manager manager) {

	if(manager.args.length >= 2 && ["init", "open", "start"].canFind(manager.args[0])) {

		immutable name = manager.args[1];
		string[] args = manager.args[2..$].dup;

		Server[string] servers;

		if(exists(manager.home ~ "servers")) {
			servers = deserialize!(typeof(servers))(cast(ubyte[])read(manager.home ~ "servers"));
		}
		
		void save() {
			mkdirRecurse(manager.home);
			write(manager.home ~ "servers", serialize(servers));
		}
		
		void init() {

			if(args.length) {

				Server server;
				server.path = find("path", args[1..$], manager.home ~ "server" ~ dirSeparator ~ name);
				mkdirRecurse(server.path);
				switch(args[0]) {
					case "bedrock":
						server.type = Server.Type.bedrock;
						installBedrock(server);
						break;
					case "selery":
						server.type = Server.Type.selery;
						installSelery(server);
						break;
					case "selery-hub":
						server.type = Server.Type.seleryHub;
						installSelery(server);
						break;
					case "selery-node":
						server.type = Server.Type.seleryNode;
						installSelery(server);
						break;
					default:
						writeError(manager, "Cannot create a server of type '" ~ args[0] ~ "'");
						return;
				}

				servers[name] = server;
				save();

			} else {

				writeError(manager, "Usage: server init <name> <software> [--version=latest]");

			}

		}
		
		void open() {}
		
		void start() {}

		final switch(manager.args[0]) {
			case "init":
				init();
				break;
			case "open":
				open();
				break;
			case "start":
				start();
				break;
		}

	} else {

		writeError(manager, "Usage: server <delete|init|open|start> <name>");

	}

}

void installBedrock(ref Server server) {

}

void installSelery(ref Server server) {

	// get latest version
	server.version_ = get("https://sel-bot.github.io/status/sel-project/selery/latest.txt").idup;

	// download zip file
	version(Windows) {
		version(X86) immutable file = "windows-x86";
		else immutable file = "windows-x64";
	} else version(OSX) {
		immutable file = "osx-x86_64";
	} else version(linux) {
		version(X86) immutable file = "linux-x86";
		else immutable file = "linux-x86_64";
	} else {
		assert(0, "Cannot find a precompiled binary for your OS");
	}

}
