/*
 * Copyright (c) 2016-2017 SEL
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU Lesser General Public License for more details.
 * 
 */
module manager;

import core.thread : Thread;

import etc.c.curl : CurlOption;

import std.algorithm : sort, min, canFind;
import std.ascii : newline;
import std.base64 : Base64;
import std.bitmanip : bigEndianToNative, nativeToBigEndian, peek;
import std.conv : to, ConvException;
import std.datetime : dur, StopWatch, AutoStart, Clock;
import std.exception : enforce;
import std.file;
import std.json;
import std.path : dirSeparator, pathSeparator, buildPath, buildNormalizedPath, absolutePath;
import std.process;
import std.regex : ctRegex, replaceAll;
import std.stdio : writeln, readln;
import std.string;
import std.typecons : Tuple, tuple;
import std.utf : toUTF8;

enum __MANAGER__ = "5.0.1";
enum __COMPONENTS__ = "https://raw.githubusercontent.com/sel-project/sel-manager/master/components/";
enum __LANG__ = "https://raw.githubusercontent.com/sel-project/sel-manager/master/lang/";

version(Windows) {
	enum __EXE__ = ".exe";
} else {
	enum __EXE__ = "";
}

enum commands = ["about", "build", "connect", "console", "delete", "init", "latest", "list", "locate", "open", "ping", "plugin", "query", "rcon", "scan", "shortcut", "social", "start", "update"];

enum noname = [".", "*", "all", "sel", "this", "manager"];

struct Settings {
	
	@disable this();
	
	public static string home;
	public static string config;
	public static string cache;
	public static string utils;
	public static string servers;
	
}

struct Server {

	string name;
	string location;
	string type; //TODO convert to enum
	bool deleteable = true;
	string user, repo, version_;
	bool edu, realm;

}

auto spawnCwd(in char[][] command, in char[] cwd) {
	scope (failure)
		writeln("When running ", command, " in ", cwd);
	return spawnProcess(command, null, std.process.Config.none, cwd);
}

auto spawnExe(in char[] exe, in char[][] args, in char[] cwd) {
	version(Windows) {
		return spawnShell("cd " ~ cwd ~ " && ." ~ dirSeparator ~ exe ~ " " ~ args.join(" "));
	} else {
		// fails on windows
		return spawnCwd(["." ~ dirSeparator ~ exe] ~ args, cwd);
	}
}

auto executeCwd(in char[][] command, in char[] cwd) {
	scope (failure)
		writeln("When running ", command, " in ", cwd);
	return execute(command, null, std.process.Config.none, size_t.max, cwd);
}

version (Posix) void makeExecutable(string path) {
	import core.sys.posix.sys.stat : S_IXUSR;
	path.setAttributes(path.getAttributes | S_IXUSR);
}

void main(string[] args) {

	version(Windows) {
		Settings.home = locationOf("%appdata%"); //TODO get with windows API
		Settings.servers = locationOf("%appdata%");
		import core.sys.windows.shlobj : SHGetFolderPath, CHAR, NULL, S_OK, CSIDL_PERSONAL, MAX_PATH;
		wchar[] docs = new wchar[MAX_PATH];
		assert(SHGetFolderPath(cast(void*)null, CSIDL_PERSONAL, cast(void*)null, 0, docs.ptr) == S_OK);
		Settings.servers = fromStringz((toUTF8(docs)).ptr);
	} else {
		Settings.home = environment["HOME"];
		Settings.servers = environment["HOME"];
	}
	if(!Settings.home.endsWith(dirSeparator)) Settings.home ~= dirSeparator;
	if(!Settings.servers.endsWith(dirSeparator)) Settings.servers ~= dirSeparator;
	version(Windows) {
		Settings.config = Settings.home ~ "sel" ~ dirSeparator;
	} else {
		Settings.config = Settings.home ~ ".sel" ~ dirSeparator;
	}
	Settings.cache = Settings.config ~ "versions" ~ dirSeparator;
	Settings.servers ~= "sel" ~ dirSeparator;
	
	string launch = args[0];
	args = args[1..$];
	
	if(args.length == 0) args ~= "help";

	if(!commands.canFind(args[0]) && args.length > 1 && nameExists(args[0])) {
		string c = args[1];
		args[1] = args[0];
		args[0] = c;
	}
	
	switch(args[0]) {
		case "help":
			printusage();
			writeln("Commands for SEL servers:");
			writeln();
			writeln("  sel <command> <server> [options]");
			writeln();
			writeln("  about       print informations about a server");
			writeln("  build       build a server");
			writeln("  connect     start a node server and connect it to an hub");
			writeln("  delete      delete a server and its files");
			writeln("  init        create a new server");
			writeln("  list        list every managed server");
			writeln("  locate      print the location of a server");
			writeln("  open        open the file explorer on a server's location");
			version(Posix) {
				writeln("  shortcut    create a shortcut for a server (root permissions required)");
			}
			writeln("  start       start a lite server or an hub server");
			writeln("  update      update a server");
			writeln();
			writeln("Commands for generic Minecraft and Minecraft: Pocket Edition servers:");
			writeln();
			writeln("  sel <command> <ip>[:port] [options]");
			writeln();
			writeln("  console     connect to a server throught the external console protocol");
			writeln("  ping        ping a server");
			writeln("  query       query a server (if the server has it enabled)");
			writeln("  rcon        connect to a server through the rcon protocol");
			writeln("  scan        search for servers on an address in the given port range");
			writeln("  social      perform a social ping to a server");
			writeln();
			writeln("Utility commands:");
			writeln();
			writeln("  convert     convert a world to another format");
			writeln("  latest      print the latest version of SEL");
			break;
		case "about":
			if(args.length > 1) {
				auto server = getServerByName(args[1].toLower);
				if(server.name != "") {
					if(args.canFind("--json")) {
						//TODO
					} else {
						writeln("Name: ", server.name);
						writeln("Location: ", server.location);
						writeln("Type: ", server.type);
						writeln("Version: ", server.version_);
						writeln("Repository: ", server.user ~ "/" ~ server.repo);
					}
				} else {
					writeln("There's no server named \"", args[1].toLower, "\"");
				}
			} else {
				writeln("Use: '", launch, " about <server>'");
			}
			break;
		case "build":
			if(args.length > 1) {
				auto server = getServerByName(args[1].toLower);
				if(server.name != "") {
					args = args[2..$];
					foreach(ref arg ; args) {
						if(arg == "-release") arg = "--build=release";
					}
					StopWatch timer = StopWatch(AutoStart.yes);
					if(!exists(server.location ~ "build" ~ dirSeparator ~ "init" ~ __EXE__)) {
						wait(spawnCwd(["dub", "build", "--single", "init.d"], server.location ~ "build"));
					}
					auto exit = wait(spawnExe("init", [], server.location ~ "build"));
					if(exit == 0) exit = wait(spawnCwd(["dub", "build", "--single", server.type ~ ".d"] ~ args, server.location ~ "build"));
					timer.stop();
					if(exit == 0) {
						if(!exists(server.location ~ "sel.json")) {
							args = ["--init"];
							if(server.edu) args ~= "-edu";
							if(server.realm) args ~= "-realm";
							wait(spawnExe(server.type, args, server.location ~ "build"));
						}
						writeln("Done. Compilation and linking took ", timer.peek.msecs.to!float / 1000, " seconds.");
					} else {
						writeln("Failed with code ", exit, " in ", timer.peek.msecs.to!float / 1000, " seconds.");
					}
				} else {
					writeln("There's no server named \"", args[1].toLower, "\"");
				}
			} else {
				writeln("Use: '", launch, " build <server> [compiler-options]'");
			}
			break;
		case "connect":
			if(args.length > 1) {
				auto server = getServerByName(args[1].toLower);
				if(server.name != "") {
					if(server.type == "node") {
						args = args[2..$];
						bool loop = false;
						bool name = false;
						for(size_t i=0; i<args.length; i++) {
							if(args[i] == "-loop") {
								loop = true;
								args = args[0..i] ~ args[i+1..$];
							} else if(args[i].startsWith("--name=") || args[i].startsWith("-n=")) {
								name = true;
							}
						}
						if(!name) args ~= "--name=" ~ server.name;
						bool connect() {
							return wait(spawnExe("node", args, server.location ~ "build")) != 0;
						}
						if(loop) {
							while(connect()) {}
						} else {
							connect();
						}
					} else {
						writeln("Server \"", server.name, "\" is not a node");
					}
				} else {
					writeln("There's no server name \"", args[1].toLower, "\"");
				}
			} else {
				writeln("Use: '", launch, " connect <server> [--name=<server>] [--password=] [--ip=localhost] [--port=28232] [--main=true] [-loop]'");
			}
			break;
		case "console":
			if(args.length > 1) {
				ptrdiff_t vers = 2; // latest
				if(args.length > 2) {
					foreach(arg ; args) {
						if(arg.startsWith("-protocol=")) {
							try {
								vers = to!uint(arg[10..$]);
							} catch(ConvException) {}
						}
					}
				}
				launchComponent!true("console", [args[1]], vers);
			} else {
				writeln("Use '", launch, " console <ip>[:port] [-protocol=2]'");
			}
			break;
		case "convert":
			if(args.length > 4) {
				string ffrom = args[1].toLower;
				string fto = args[2].toLower;
				launchComponent!true("convert", [ffrom, fto, args[3], args[4]]);
			} else {
				writeln("Use '", launch, " convert <format-from> <format-to> <location-from> [location-to=.]'");
			}
			break;
		case "delete":
			if(args.length > 1) {
				auto server = getServerByName(args[1].toLower);
				if(server.name != "") {
					if(server.deleteable) {
						auto servers = serverTuples;
						foreach(i, s; servers) {
							if(s.name == server.name) {
								servers = servers[0..i] ~ servers[i+1..$];
								break;
							}
						}
						saveServerTuples(servers);
						if(args.length < 3 || to!bool(args[2])) {
							foreach(string file ; dirEntries(server.location, SpanMode.breadth)) {
								if(file.isFile) {
									remove(file);
								}
							}
							rmdirRecurse(server.location);
						}
					} else {
						writeln("The server must be deleted manually");
					}
				} else {
					writeln("There's no server named \"", args[1].toLower, "\"");
				}
			} else {
				writeln("Use: '", launch, " delete <server> [delete-files=true]");
			}
			break;
		case "init":
			if(args.length > 1) {
				string name = args[1].toLower;
				args = args[2..$];
				T find(T)(string key, T def) {
					foreach(arg ; args) {
						if(arg.startsWith("--" ~ key.toLower ~ "=")) {
							try {
								return to!T(arg[3+key.length..$]);
							} catch(ConvException) {}
						}
					}
					return def;
				}
				string type = find("type", "lite").toLower;
				string path = find("path", Settings.servers ~ name);
				string user = find("user", "sel-project");
				string repo = find("repo", find("repository", find("project", "sel-server")));
				string vers = find("version", "latest");
				if(!nameExists(name)) {
					if(!noname.canFind(name)) {
						if(type == "hub" || type == "node" || type == "lite") {
							// get real path
							mkdirRecurse(path);
							if(!path.endsWith(dirSeparator)) path ~= dirSeparator;
							if(vers != "none") {
								vers = install(launch, path, type, user, repo, vers, args.canFind("--local"));
							}
							auto server = Server(name, path, type, !args.canFind("--no-delete"), user, repo, vers, args.canFind("-edu"), args.canFind("-realm"));
							saveServerTuples(serverTuples ~ server);
						} else {
							writeln("Invalid type \"", type, "\". Choose between \"lite\", \"hub\", and \"node\"");
						}
					} else {
						writeln("Cannot name a server \"", name, "\"");
					}
				} else {
					writeln("A server named \"", name, "\" already exists");
				}
			} else {
				writeln("Use '", launch, " init <server> <lite|hub|node> [-user=sel-project] [-repo=sel-server] [-version=latest] [-path=] [-local] [-edu] [-realm] [-no-delete]'");
			}
			break;
		case "latest":
			string user = "sel-project";
			string repo = "sel-server";
			foreach(arg ; args) {
				if(arg.startsWith("--user=")) {
					user = arg[7..$];
				} else if(arg.startsWith("--repo=")) {
					repo = arg[7..$];
				}
			}
			immutable dir = tempDir() ~ dirSeparator ~ "sel" ~ dirSeparator ~ user ~ dirSeparator ~ repo ~ dirSeparator;
			immutable latest = dir ~ "latest";
			immutable time = dir ~ "latest_time";
			if(!exists(latest) || !exists(time) || (){ ubyte[4] ret=cast(ubyte[])read(time);return bigEndianToNative!uint(ret); }() < Clock.currTime().toUnixTime() - 60 * 60) {
				mkdirRecurse(dir);
				auto json = parseJSON(get("https://api.github.com/repos/" ~ user ~ "/" ~ repo ~ "/releases").idup);
				if(json.type == JSON_TYPE.OBJECT) {
					auto name = "name" in json;
					if(name && name.type == JSON_TYPE.STRING) {
						write(latest, name.str);
						write(time, nativeToBigEndian(Clock.currTime().toUnixTime!int()));
					}
				}
			}
			writeln((cast(string)read(latest)).strip);
			break;
		case "list":
			writeln("Servers managed by SEL Manager:");
			foreach(server ; serverTuples) {
				writeln(server.name, " ", server.type, " ", server.location);
			}
			break;
		case "locate":
			if(args.length > 1) {
				if(nameExists(args[1].toLower)) {
					writeln(getServerByName(args[1].toLower).location);
				} else {
					writeln("There's no server named \"", args[1].toLower, "\"");
				}
			} else {
				writeln("Use '", launch, " locate <server>'");
			}
			break;
		case "open":
			if(args.length > 1) {
				if(nameExists(args[1].toLower)) {
					version(Windows) {
						immutable cmd = "start";
					} else {
						immutable cmd = "xdg-open";
					}
					wait(spawnProcess([cmd, getServerByName(args[1].toLower).location]));
				} else {
					writeln("There's no server named \"", args[1].toLower, "\"");
				}
			} else {
				writeln("Use '", launch, " open <server>'");
			}
			break;
		case "ping":
			if(args.length > 1) {
				string str = launchComponent("ping", args[1..$]).strip;
				if(args.canFind("-json")) {
					writeln(str);
				} else {
					auto json = parseJSON(str);
					void printping(string type, JSONValue v) {
						if(v.type == JSON_TYPE.STRING) {
							writeln(v.str);
						} else {
							auto value = v.object;
							writeln(type, " on ", value["ip"].str, ":", value["port"].integer, " (", value["ping"].integer, " ms)");
							writeln("  MOTD: ", value["motd"].str.split("\n")[0].replaceAll(ctRegex!"§[a-fA-F0-9k-or]", "").strip);
							writeln("  Players: ", value["online"].integer, "/", value["max"].integer);
							writeln("  Version: ", value["version"].str, " (protocol ", value["protocol"].integer, ")");
						}
					}
					if("minecraft" in json) {
						printping("Minecraft", json["minecraft"]);
					}
					if("pocket" in json) {
						printping("Minecraft: Pocket Edition", json["pocket"]);
					}
				}
			} else {
				writeln("Use '", launch, " ping <ip>[:port] [options] [-json] [-raw]'");
			}
			break;
		case "query":
			if(args.length > 1) {
				string str = launchComponent("query", args[1..$]).strip;
				if(args.canFind("-json")) {
					writeln(str);
				} else {
					auto json = parseJSON(str);
					auto error = "error" in json;
					if(error) {
						writeln("Error: ", (*error).str);
					} else {
						void printquery(string type, JSONValue[string] value) {
							writeln(type, " on ", value["address"].str, " (", value["ping"].integer, " ms)");
							writeln("  MOTD: ", value["motd"].str.replaceAll(ctRegex!"§[a-fA-F0-9k-or]", "").strip);
							writeln("  Players: ", value["online"].integer, "/", value["max"].integer);
							auto players = value["players"].array;
							if(players.length > 0 && players.length < 32) {
								writeln("  List: ", (){ string[] ret;foreach(JSONValue player;players){ret~=player.str;}return ret.join(", "); }());
							}
							writeln("  Software: ", value["software"].str);
							if(value["plugins"].array.length > 0) {
								writeln("  Plugins:");
								foreach(JSONValue v ; value["plugins"].array) {
									writeln("    ", v["name"].str, " ", v["version"].str);
								}
							}
						}
						if("minecraft" in json) {
							printquery("Minecraft", json["minecraft"].object);
						}
						if("pocket" in json) {
							printquery("Minecraft: Pocket Edition", json["pocket"].object);
						}
					}
				}
			} else {
				writeln("Use '", launch, " query <ip>[:port] [-json]'");
			}
			break;
		case "rcon":
			if(args.length >= 3) {
				launchComponent!true("rcon", args[1..$]);
			} else {
				writeln("Use '", launch, " rcon <ip>[:port] <password>'");
			}
			break;
		case "scan":
			if(args.length >= 2) {
				string ip = args[1];
				string str = launchComponent("scan", args[1..$]).strip;
				if(args.canFind("-json")) {
					writeln(str);
				} else {
					auto json = parseJSON(str);
					auto error = "error" in json;
					if(error) {
						writeln("Error: ", error.str);
					} else {
						void print(string game, const JSONValue[] array) {
							writeln(game, ":");
							if(array.length) {
								foreach(value ; array) {
									writeln("  ", value["port"].integer, ":");
									writeln("    MOTD: ", value["motd"].str.replaceAll(ctRegex!"§[a-fA-F0-9k-or]", "").strip);
									writeln("    Players: ", value["online"], "/", value["max"]);
									writeln("    Version: ", value["version"].str, " (protocol ", value["protocol"], ")");
								}
							} else {
								writeln("No server found");
							}
						}
						auto minecraft = "minecraft" in json;
						auto pocket = "pocket" in json;
						if(minecraft) print("Minecraft", minecraft.array);
						if(pocket) print("Minecraft: Pocket Edition", pocket.array);
					}
				}
			} else {
				writeln("Use '", launch, " scan <ip> [-minecraft] [-pocket] [-from=1] [-to=65535]'");
			}
			break;
		version(Posix) {
			case "shortcut":
			if(args.length > 1) {
				auto server = getServerByName(args[1].toLower);
				if(server.name != "") {
					try {
						write("/usr/bin/" ~ server.name, "#!/bin/sh\nsel '\"" ~ server.name ~ "\"' $@");
						makeExecutable("/usr/bin/" ~ server.name);
						writeln("You can now use '", server.name, " <command> [options]' as a shortcut for '", launch, " <command> ", server.name, " [options]'");
					} catch (FileException) {
						writeln("Failed creating file /usr/bin/" ~ server.name ~ ", are you root?");
					}
				} else {
					writeln("There's no server named \"", args[1].toLower, "\"");
				}
			} else {
				writeln("Use: '", launch, " shortcut <server>");
			}
			break;
		}
		case "social":
			if(args.length > 1) {
				string str = launchComponent("social", args[1..$]);
				writeln(str);
			} else {
				writeln("Use: '", launch, " social <ip>[:port]'");
			}
			break;
		case "start":
			if(args.length > 1) {
				auto server = getServerByName(args[1].toLower);
				if(server.name != "") {
					immutable loop = args.canFind("--loop");
					if(server.type == "hub" || server.type == "lite") {
						if(exists(server.location ~ "build" ~ dirSeparator ~ server.type ~ __EXE__)) {
							args.length = 0;
							if(server.edu) args ~= "-edu";
							if(server.realm) args ~= "-realm";
							do {
								if(wait(spawnExe(server.type, args, server.location ~ "build")) == 0) break; 
							} while(loop);
						} else {
							writeln("Cannot find an executable file for the server. Use '", launch, " build ", server.name, "' to create one");
						}
					} else if(server.type == "node") {
						writeln("Use '" ~ launch ~ " connect " ~ server.name ~ "' to start a node");
					}
				} else {
					writeln("There's no server named \"", args[1].toLower, "\"");
				}
			} else {
				writeln("Use: '", launch, " start <server> [--loop]'");
			}
			break;
		case "update":
			if(args.length > 1) {
				immutable name = args[1].toLower;
				auto servers = serverTuples;
				bool updated = false;
				foreach(ref server ; servers) {
					if(server.name == name) {
						string find(string key, string def) {
							foreach(arg ; args) {
								if(arg.startsWith("--" ~ key.toLower ~ "=")) return arg[3+key.length..$];
							}
							return def;
						}
						server.user = find("user", server.user);
						server.repo = find("repo", find("repository", find("project", server.repo)));
						string vers = find("version", "latest");
						server.version_ = install(launch, server.location, server.type, server.user, server.repo, vers, !exists(server.location ~ ".sel" ~ dirSeparator ~ "libraries"));
						updated = true;
						break;
					}
				}
				if(updated) {
					saveServerTuples(servers);
				} else {
					writeln("There's no server named \"", args[1].toLower, "\"");
				}
			} else {
				writeln("Use: '", launch, " update <server> [--user=current] [--repo=current] [--version=latest]'");
			}
			break;
		default:
			writeln("'", launch, " ", args.join(" "), "' is not a valid command");
			break;
	}
	
}

void printusage() {
	writeln("SEL Manager v", __MANAGER__);
	writeln("Copyright (c) 2016-2017 SEL");
	writeln();
	//writeln("Website: http://selproject.org");
	writeln("Github: https://github.com/sel-project/sel-manager");
	writeln();
	writeln("Servers path: ", Settings.servers);
	writeln("Managed servers: ", to!string(serverTuples.length));
	writeln();
}

@property Server[] serverTuples() {
	Server[] ret;
	if(exists(Settings.config ~ "sel.conf")) {
		foreach(string s ; (cast(string)read(Settings.config ~ "sel.conf")).split(newline)) {
			string[] spl = s.split(";");
			if(spl.length >= 9) {
				size_t i = 0;
				T readNext(T)() {
					static if(is(T == string)) {
						return cast(T)Base64.decode(spl[i++]);
					} else {
						return to!T(spl[i++]);
					}
				}
				ret ~= Server(readNext!string(), readNext!string(), readNext!string(), readNext!bool(), readNext!string(), readNext!string(), readNext!string(), readNext!bool(), readNext!bool());
			}
		}
	}
	return ret;
}

@property bool nameExists(string name) {
	foreach(server ; serverTuples) {
		if(server.name == name) return true;
	}
	return name == ".";
}

@property Server getServerByName(string name) {
	foreach(server ; serverTuples) {
		if(server.name == name) return server;
	}
	return Server.init;
}

void saveServerTuples(Server[] servers) {
	mkdirRecurse(Settings.config);
	string file = "### SEL MANAGER CONFIGURATION FILE" ~ newline ~ "### DO NOT EDIT MANUALLY" ~ newline;
	foreach(server ; servers) {
		string[] data;
		void writeNext(T)(T value) {
			static if(is(T == string)) {
				data ~= Base64.encode(cast(ubyte[])value);
			} else {
				data ~= to!string(value);
			}
		}
		writeNext(server.name);
		writeNext(server.location);
		writeNext(server.type);
		writeNext(server.deleteable);
		writeNext(server.user);
		writeNext(server.repo);
		writeNext(server.version_);
		writeNext(server.edu);
		writeNext(server.realm);
		file ~= join(data, ";") ~ newline;
	}
	write(Settings.config ~ "sel.conf", file);
}

string locationOf(string loc) {
	version(Windows) {
		return executeShell("cd " ~ loc ~ " && cd").output.strip;
	} else {
		return executeShell("cd " ~ loc ~ " && pwd").output.strip;
	}
}

string install(string launch, string path, string type, string user, string repo, string vers, bool local) {
	if(vers.startsWith("~")) {
		if(!checkGit()) {
			writeln("Git is not installed on this machine");
		} else if(local || !exists(path ~ ".sel")) {
			//TODO fails if directory is not empty
			// download from a branch directly in the server's folder
			wait(spawnCwd(["git", "clone", "--branch", vers[1..$], "--single-branch", "https://github.com/" ~ user ~ "/" ~ repo ~ ".git", "."], path));
		} else {
			writeln("Cannot update a non-local server using git");
		}
	} else {
		if(!vers.length || vers == "latest") {
			vers = execute([launch, "latest"]).output.strip;
		}
		immutable dest = Settings.cache ~ user ~ dirSeparator ~ repo ~ dirSeparator;
		if(!exists(dest ~ vers)) {
			mkdirRecurse(dest);
			if(checkGit()) {
				wait(spawnCwd(["git", "clone", "-b", "'" ~ vers ~ "'", "--single-branch", "https://github.com/" ~ user ~ "/" ~ repo ~ ".git", vers], dest));
			} else {
				// download and unzip
				if(!exists(dest ~ vers ~ ".zip")) {
					immutable dl = "https://github.com/" ~ user ~ "/" ~ repo ~ "/archive/v" ~ vers ~ ".zip";
					mkdirRecurse(dest);
					download(dl, dest ~ vers ~ ".zip");
				}
				//TODO unzip
				
				version(Windows) {
					// to display the version when building with dub
					string json = JSONValue(["version": vers]).toString();
					foreach(t ; ["common", "hub", "node"]) {
						mkdirRecurse(dest ~ vers ~ t ~ ".dub");
						write(dest ~ vers ~ t ~ ".dub" ~ dirSeparator ~ "version.json", json);
					}
				}
			}
		}
		// delete executables
		void del(string exe) {
			immutable path = dest ~ "build" ~ dirSeparator ~ exe ~ __EXE__;
			if(exists(path)) remove(path);
		}
		del("init");
		del(type);
		// copy files from vers/ to path/
		immutable dec = dest ~ vers ~ dirSeparator;
		void copy(string from, string to) {
			foreach(string p ; dirEntries(from, SpanMode.depth)) {
				immutable dest = to ~ p[from.length..$];
				if(p.isFile) {
					mkdirRecurse(dest[0..dest.lastIndexOf(dirSeparator)]);
					write(dest, read(p));
				}
			}
		}
		copy(dec ~ "build", path ~ "build");
		foreach(t ; ["hub", "node", "lite"]) {
			if(type != t) remove(path ~ "build/" ~ t ~ ".d");
		}
		if(local) {
			copy(dec ~ "res", path ~ "res");
			copy(dec ~ "common", path ~ "common");
			if(type == "hub" || type == "lite") copy(dec ~ "hub", path ~ "hub");
			if(type == "node" || type == "lite") copy(dec ~ "node", path ~ "node");
		} else {
			void relocate(string type)(string file, string to) {
				static if(dirSeparator == "\\") {
					to = to.replace("\\", "\\\\");
				}
				auto data = cast(string)read(file);
				data = data.replaceAll(ctRegex!(`"sel-` ~ type ~ `" path="([a-z\-\.\/]+)"`), `"sel-` ~ type ~ `" path="` ~ to ~ `"`);
				write(file, data);
			}
			immutable build = path ~ "build" ~ dirSeparator;
			immutable libs = buildNormalizedPath(absolutePath(dec)) ~ dirSeparator;
			relocate!"common"(build ~ "init.d", libs ~ "common");
			if(type == "hub") {
				relocate!"common"(build ~ "hub.d", libs ~ "common");
				relocate!"hub"(build ~ "hub.d", libs ~ "hub");
			}
			if(type == "node") {
				relocate!"common"(build ~ "node.d", libs ~ "common");
				relocate!"node"(build ~ "node.d", libs ~ "node");
			}
			if(type == "lite") {
				relocate!"common"(build ~ "lite.d", libs ~ "common");
				relocate!"hub"(build ~ "lite.d", libs ~ "hub");
				relocate!"node"(build ~ "lite.d", libs ~ "node");
			}
			mkdirRecurse(path ~ ".sel");
			write(path ~ ".sel" ~ dirSeparator ~ "libraries", libs);
		}
	}
	return vers;
}

bool checkGit() {
	return executeCwd(["git", "--version"], ".").status == 0;
}

string[] components() {
	if(!exists(Settings.config ~ "components")) return [];
	string[] ret;
	foreach(string path ; dirEntries(Settings.config ~ "components", SpanMode.breadth)) {
		if(path.isFile) {
			string file = path.split(dirSeparator)[$-1];
			version(Windows) {
				if(file.endsWith(".exe")) ret ~= file[0..$-4];
			} else {
				if(file.indexOf(".") == -1) ret ~= file;
			}
		}
	}
	return ret;
}

string launchComponent(bool spawn=false)(string component, string[] args, ptrdiff_t vers=-1) {
	immutable name = component;
	if(vers >= 0) component ~= to!string(vers);
	if(!exists(Settings.config ~ "components")) mkdirRecurse(Settings.config ~ "components");
	version(Windows) {
		immutable ext = ".exe";
		immutable runnable = component ~ ".exe";
	} else {
		immutable ext = "";
		immutable runnable = "./" ~ component;
	}
	immutable cwd = Settings.config ~ "components";
	if(!exists(Settings.config ~ "components" ~ dirSeparator ~ component ~ ext)) {
		download(__COMPONENTS__ ~ name ~ ".d", Settings.config ~ "components" ~ dirSeparator ~ component ~ ".d");
		write(Settings.config ~ "components" ~ dirSeparator ~ "version.txt", to!string(vers));
		wait(spawnCwd(["dub", "build", "--single", component ~ ".d"], cwd));
		remove(Settings.config ~ "components" ~ dirSeparator ~ component ~ ".d");
		remove(Settings.config ~ "components" ~ dirSeparator ~ "version.txt");
	}
	const cmd = [runnable] ~ args;
	static if(spawn) {
		wait(spawnCwd(cmd, cwd));
		return "";
	} else {
		return executeCwd(cmd, cwd).output.strip;
	}
}

string get(string file) {
	static import std.net.curl;
	auto http = std.net.curl.HTTP();
	http.handle.set(CurlOption.ssl_verifypeer, false);
	http.handle.set(CurlOption.timeout, 10);
	return std.net.curl.get(file, http).idup;
}

void download(string file, string dest) {
	writeln("Downloading ", file, " into ", dest);
	static import std.net.curl;
	auto http = std.net.curl.HTTP();
	http.handle.set(CurlOption.timeout, 10);
	std.net.curl.download(file, dest, http);
	if(http.statusLine.code != 200)
		throw new Exception("Failed to download file " ~ file ~ " (HTTP error code " ~ http.statusLine.code.to!string ~ ")");
}
