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
import std.path : dirSeparator, pathSeparator, buildPath;
import std.process;
import std.regex : ctRegex, replaceAll;
import std.stdio : writeln, readln;
import std.string;
import std.typecons : Tuple, tuple;
import std.utf : toUTF8;

alias ServerTuple = Tuple!(string, "name", string, "location", string, "type", bool, "deleteable");

enum __MANAGER__ = "5.0.0";
enum __COMPONENTS__ = "https://raw.githubusercontent.com/sel-project/sel-manager/master/components/";
enum __LANG__ = "https://raw.githubusercontent.com/sel-project/sel-manager/master/lang/";
enum __UTILS__ = "https://raw.githubusercontent.com/sel-project/sel-utils/master/release.sa";

version(Windows) {
	enum __EXE__ = ".exe";
	enum __EXECUTABLE__ = "main.exe";
} else {
	enum __EXE__ = "";
	enum __EXECUTABLE__ = "main";
}

enum commands = ["about", "build", "clear", "connect", "console", "convert", "delete", "init", "latest", "list", "locate", "open", "ping", "plugin", "query", "rcon", "scan", "shortcut", "social", "start", "update"];

enum noname = [".", "*", "all", "sel", "this", "manager", "lib", "libs", "util", "utils"];

struct Settings {
	
	@disable this();
	
	public static string home;
	public static string config;
	public static string cache;
	public static string utils;
	public static string servers;
	
}

auto spawnCwd(in char[][] command, in char[] cwd) {
	scope (failure)
		writeln("When running ", command, " in ", cwd);
	return spawnProcess(command, null, std.process.Config.none, cwd);
}

auto spawnExe(in char[] exe, in char[][] args, in char[] cwd) {
	version(Windows) {
		return spawnShell("cd " ~ cwd ~ " " ~ args.join(" ") ~ " && " ~ exe ~ ".exe");
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
		if(SHGetFolderPath(cast(void*)null, CSIDL_PERSONAL, cast(void*)null, 0, docs.ptr) == S_OK) {
			Settings.servers = fromStringz((toUTF8(docs)).ptr);
		}
	} else {
		Settings.home = environment["HOME"];
		Settings.servers = environment["HOME"];
	}
	if(!Settings.home.endsWith(dirSeparator)) Settings.home ~= dirSeparator;
	if(!Settings.servers.endsWith(dirSeparator)) Settings.servers ~= dirSeparator;
	Settings.config = Settings.home ~ ".sel" ~ dirSeparator;
	Settings.cache = Settings.config ~ "versions" ~ dirSeparator;
	Settings.utils = Settings.config ~ "utils" ~ dirSeparator; 
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
			writeln("  clear       clear a server's cache");
			writeln("  connect     start a node server and connect it to an hub");
			writeln("  delete      delete a server and its files");
			writeln("  init        create a new server");
			writeln("  list        list every managed server");
			writeln("  locate      print the location of a server");
			writeln("  open        open the file explorer on a server's location");
			version(Posix) {
				writeln("  shortcut    create a shortcut for a server (root permissions required)");
			}
			writeln("  start       start an hub server");
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
					JSONValue[string] data;
					if(server.type == "hub" || server.type == "full") {
						try {
							data["hub"] = parseJSON(executeCwd(["." ~ dirSeparator ~ "hub", "about"], server.location).output);
						} catch(JSONException) {}
					}
					if(server.type == "node" || server.type == "full") {
						try {
							data["node"] = parseJSON(executeCwd(["." ~ dirSeparator ~ "node", "about"], server.location).output);
						} catch(JSONException) {}
					}
					if(args.canFind("-json")) {
						writeln(JSONValue(data).toString());
					} else {
						void prt(string what) {
							auto about = what in data;
							if(about) {
								auto software = "software" in *about;
								writeln(capitalize(what), ":");
								if(software) {
									writeln("  Name: ", (*software)["name"].str);
									writeln("  Version: ", (*software)["version"].str, ((*software)["stable"].type == JSON_TYPE.FALSE ? "-dev" : ""));
								}
							}
						}
						prt("hub");
						prt("node");
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
					StopWatch timer = StopWatch(AutoStart.yes);
					wait(spawnCwd(["dub", "init.d"], server.location ~ "build"));
					wait(spawnCwd(["dub", "build", "--single", server.type ~ ".d"], server.location ~ "build")); //TODO custom args
					timer.stop();
					if(exists(server.location ~ "build/sel-" ~ server.type ~ __EXE__)) writeln("Done. Compilation took ", timer.peek.msecs.to!float / 1000, " seconds.");
					else writeln("Failed in ", timer.peek.msecs.to!float / 1000, " seconds.");
				} else {
					writeln("There's no server named \"", args[1].toLower, "\"");
				}
			} else {
				writeln("Use: '", launch, " build <server> [compiler-options]'");
			}
			break;
		case "clear":
			if(args.length == 2) {
				void del(string location) {
					size_t deleted = 0;
					if(exists(location) && location.isDir) {
						foreach(string path ; dirEntries(location, SpanMode.breadth)) {
							if(path.isFile) {
								try {
									remove(path);
									deleted++;
								} catch(FileException) {}
							}
						}
					}
					writeln("Deleted ", deleted, " files from ", location);
				}
				if(args[1] == "all") {
					string tmp = tempDir();
					if(!tmp.endsWith(dirSeparator)) tmp ~= dirSeparator;
					del(tmp ~ "sel");
					del(tmp ~ ".rdmd");
					del(tmp ~ "rdmd-0");
				} else {
					auto server = getServerByName(args[1]);
					if(server.name != "") {
						del(server.location ~ ".hidden");
					} else {
						writeln("There's no server named \"", args[1].toLower, "\"");
					}
				}
			} else {
				writeln("Use: '", launch, " clear <server>'");
			}
			break;
		case "connect":
			if(args.length > 1) {
				auto server = getServerByName(args[1].toLower);
				if(server.name != "") {
					if(server.type == "node") {
						args = args[2..$];
						T find(T)(string key, T def) {
							foreach(arg ; args) {
								if(arg.startsWith("-" ~ key.toLower ~ "=")) {
									try {
										return to!T(arg[2+key.length..$]);
									} catch(ConvException) {}
								}
							}
							return def;
						}
						string name = find("name", server.name);
						string password = find("password", "");
						string ip = find("ip", "localhost");
						ushort port = find("port", cast(ushort)28232);
						bool main = find("main", true);
						bool connect() {
							return wait(spawnExe("sel-node", [name, ip, to!string(port), to!string(main), password], server.location)) == 0;
						}
						if(args.canFind("-loop")) {
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
				writeln("Use: '", launch, " connect <server> [-name=<server>] [-password=] [-ip=localhost] [-port=28232] [-main=true] [-loop]'");
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
						foreach(size_t i, ServerTuple s; servers) {
							if(s.name == server.name) {
								servers = servers[0..i] ~ servers[i+1..$];
								break;
							}
						}
						saveServerTuples(servers);
						if(args.length > 2 ? to!bool(args[2]) : true) {
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
				string type = args.length > 2 ? args[2].toLower : "lite";
				args = args[2..$];
				T find(T)(string key, T def) {
					foreach(arg ; args) {
						if(arg.startsWith("-" ~ key.toLower ~ "=")) {
							try {
								return to!T(arg[2+key.length..$]);
							} catch(ConvException) {}
						}
					}
					return def;
				}
				string path = find("path", Settings.servers ~ name);
				string user = find("user", "sel-project");
				string repo = find("repo", find("repository", find("project", "sel-server")));
				string vers = find("version", "latest").toLower;
				string[] flags;
				if(args.canFind("-edu")) flags ~= "Edu";
				if(args.canFind("-realm")) flags ~= "Realm";
				if(!nameExists(name)) {
					if(!noname.canFind(name)) {
						if(type == "hub" || type == "node" || type == "lite") {
							// get real path
							mkdirRecurse(path);
							if(!path.endsWith(dirSeparator)) path ~= dirSeparator;
							if(vers != "none") {
								install(launch, path, type, user, repo, vers, args.canFind("-local"));
							}
							auto server = ServerTuple(name, path, type, !args.canFind("-no-delete"));
							//TODO save flags
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
				if(arg.startsWith("-user=")) {
					user = arg[6..$];
				} else if(arg.startsWith("-repo=")) {
					repo = arg[6..$];
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
			foreach(ServerTuple server ; serverTuples) {
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
					immutable loop = args.canFind("-loop");
					if(server.type == "hub" || server.type == "lite") {
						do {
							//TODO start with -edu and -realm
							if(wait(spawnExe("sel-" ~ server.type, [], server.location ~ "build")) != 0) break; 
						} while(loop);
					} else if(server.type == "node") {
						writeln("Use '" ~ launch ~ " connect " ~ server.name ~ "' to start a node");
					}
				} else {
					writeln("There's no server named \"", args[1].toLower, "\"");
				}
			} else {
				writeln("Use: '", launch, " start <server> [-loop]'");
			}
			break;
		case "update":
			if(args.length > 1) {
				immutable name = args[1].toLower;
				switch(name) {
					case "*":
					case "all":
						wait(spawnProcess([launch, "update", "sel"]));
						foreach(ServerTuple server ; serverTuples) {
							wait(spawnProcess([launch, "update", server.name]));
						}
						break;
					case "comp":
					case "components":
						foreach(comp ; dirEntries(Settings.config ~ "components", SpanMode.breadth)) {
							if(comp.isFile) remove(comp);
						}
						break;
					default:
						auto server = getServerByName(name);
						if(server.name.length) {
							string find(string key, string def) {
								foreach(arg ; args) {
									if(arg.startsWith("-" ~ key.toLower ~ "=")) return arg[2+key.length..$];
								}
								return def;
							}
							string path = find("path", Settings.servers ~ name);
							string user = find("user", "sel-project");
							string repo = find("repo", find("repository", find("project", "sel-server")));
							string vers = find("version", "latest").toLower;
							install(launch, server.location, server.type, user, repo, vers, false); //TODO get local from server's settings
						} else {
							writeln("There's no server named \"", args[1].toLower, "\"");
						}
						break;
				}
			} else {
				writeln("Use: '", launch, " update <server> [-user=sel-project] [-repo=sel-server] [-version=latest]'");
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
	writeln("Github: https://github.com/sel-project");
	writeln();
	writeln("Servers path: ", Settings.servers);
	writeln("Managed servers: ", to!string(serverTuples.length));
	writeln();
}

@property ServerTuple[] serverTuples() {
	ServerTuple[] ret;
	if(exists(Settings.config ~ "sel.conf")) {
		foreach(string s ; (cast(string)read(Settings.config ~ "sel.conf")).split(newline)) {
			string[] spl = s.split(",");
			if(spl.length >= 3) {
				ret ~= ServerTuple(cast(string)Base64.decode(spl[0]), spl[1], spl[2], spl.length>=4?to!bool(spl[3]):true);
			}
		}
	}
	return ret;
}

@property bool nameExists(string name) {
	foreach(ServerTuple server ; serverTuples) {
		if(server.name == name) return true;
	}
	return name == ".";
}

@property ServerTuple getServerByName(string name) {
	if(name == ".") {
		string loc = locationOf(name);
		if(!loc.endsWith(dirSeparator)) loc ~= dirSeparator;
		return ServerTuple(loc, loc, "lite", true);
	}
	foreach(ServerTuple server ; serverTuples) {
		if(server.name == name) return server;
	}
	return ServerTuple.init;
}

void saveServerTuples(ServerTuple[] servers) {
	mkdirRecurse(Settings.config);
	string file = "### SEL MANAGER CONFIGURATION FILE" ~ newline;
	foreach(ServerTuple server ; servers) {
		file ~= Base64.encode(cast(ubyte[])server.name) ~ "," ~ server.location ~ "," ~ server.type ~ "," ~ server.deleteable.to!string ~ newline;
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

void install(string launch, string path, string type, string user, string repo, string vers, bool local) {
	if(vers.startsWith("~")) {
		//TODO delete .git if exists?
		// download from a branch directly in the server's folder
		wait(spawnCwd(["git", "clone", "-b", vers[1..$], "--single-branch", "https://github.com/" ~ user ~ "/" ~ repo ~ ".git", "."], path));
		foreach(del ; [".editorconfig", ".gitignore", ".travis.yml", "appveyor.yml", "CONTRIBUTING.md", "README.md"]) {
			// unnecessary files
			remove(path ~ del);
		}
	} else {
		if(!vers.length || vers == "latest") {
			vers = execute([launch, "latest"]).output.strip;
		}
		immutable dest = Settings.cache ~ user ~ dirSeparator ~ repo ~ dirSeparator;
		if(!exists(dest ~ vers)) {
			mkdirRecurse(dest);
			// download and unzip
			if(!exists(dest ~ vers ~ ".zip")) {
				//TODO use git clone if git is installed on the system
				if(false) {
					wait(spawnCwd(["git", "clone", "-b", "'v" ~ vers ~ "'", "--single-branch", "https://github.com/" ~ user ~ "/" ~ repo ~ ".git", vers], dest));
				} else {
					immutable dl = "https://github.com/" ~ user ~ "/" ~ repo ~ "/archive/v" ~ vers ~ ".zip";
					mkdirRecurse(dest);
					download(dl, dest ~ vers ~ ".zip");
					//TODO unzip
					
					version(Windows) {
						//TODO add version to .dub/version.json
					}
				}
			}
		}
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
		copy(dec ~ "res", path ~ "res");
		copy(dec ~ "build", path ~ "build");
		if(local) {
			copy(dec ~ "common", path ~ "common");
			copy(dec ~ "hub", path ~ "hub");
			copy(dec ~ "node", path ~ "node");
		} else {
			//TODO edit init.d, hub.d, node.d and lite.d to point to right paths
		}
	}
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
