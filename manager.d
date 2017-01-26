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

import std.algorithm : min, canFind;
import std.ascii : newline;
import std.base64 : Base64;
import std.bitmanip : nativeToBigEndian;
import std.conv : to, ConvException;
import std.datetime : dur, StopWatch, AutoStart;
import std.file;
import std.json;
import std.net.curl : HTTP, get, download;
import std.path : dirSeparator, pathSeparator;
import std.process;
import std.regex : ctRegex, replaceAll;
import std.stdio : writeln, readln;
import std.string;
import std.typecons : Tuple, tuple;
import std.utf : toUTF8;
import std.zlib : Compress, UnCompress, HeaderFormat;

alias Config = Tuple!(string, "sel", string, "common", string[], "versions", string[], "code", string[], "files");

alias ServerTuple = Tuple!(string, "name", string, "location", string, "type", Config, "config");

enum __MANAGER__ = "4.5.1";
enum __DOWNLOAD__ = "https://github.com/sel-project/sel-server/releases/";
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

enum commands = ["about", "build", "clear", "client", "connect", "console", "convert", "delete", "init", "latest", "list", "locate", "open", "ping", "query", "rcon", "scan", "social", "start", "update"];

enum noname = [".", "*", "all", "sel", "this", "manager", "lib", "libs", "util", "utils"];

version(linux) enum __shortcut = true;
else version(OSX) enum __shortcut = true;
else version(FreeBSD) enum __shortcut = true;
else enum __shortcut = false;

struct Settings {
	
	@disable this();
	
	public static string home;
	public static string config;
	public static string cache;
	public static string utils;
	public static string servers;
	
}

void main(string[] args) {

	version(Windows) {
		Settings.home = locationOf("%appdata%");
		Settings.servers = locationOf("%appdata%");
		import core.sys.windows.shlobj : SHGetFolderPath, CHAR, NULL, S_OK, CSIDL_PERSONAL, MAX_PATH;
		wchar[] docs = new wchar[MAX_PATH];
		if(SHGetFolderPath(cast(void*)null, CSIDL_PERSONAL, cast(void*)null, 0, docs.ptr) == S_OK) {
			Settings.servers = fromStringz((toUTF8(docs)).ptr);
		}
	} else {
		Settings.home = locationOf("$HOME");
		Settings.servers = locationOf("$HOME");
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
			static if(__shortcut) {
				writeln("  shortcut    create a shortcut for a server (root permissions required)");
			}
			writeln("  start       start an hub server");
			writeln("  update      update a server");
			writeln();
			writeln("Commands for generic Minecraft and Minecraft: Pocket Edition servers:");
			writeln();
			writeln("  sel <command> <ip>[:port] [options]");
			writeln();
			writeln("  client      simulate a game client");
			writeln("  console     connect to a server throught the external console protocol");
			writeln("  ping        ping a server");
			writeln("  query       query a server (if the server has it enabled)");
			writeln("  rcon        connect to a server through the rcon protocol");
			writeln("  scan        search for servers on an address in the given port range");
			writeln("  social      perform a social ping to a server");
			writeln();
			writeln("Utility commands:");
			writeln();
			writeln("  compress    compress a folder into a sel archive");
			writeln("  convert     convert a world to another format");
			writeln("  latest      print the latest stable version of SEL");
			writeln("  uncompress  uncompress a file archive");
			break;
		case "about":
			if(args.length > 1) {
				auto server = getServerByName(args[1].toLower);
				if(server.name != "") {
					immutable location = server.location ~ (server.type == "full" ? "hub" ~ dirSeparator : "") ~ dirSeparator;
					if(exists(location ~ __EXECUTABLE__)) {
						wait(spawnShell("cd " ~ location ~ " && ." ~ dirSeparator ~ "main about"));
					} else {
						writeln("The server hasn't been built yet");
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
					if(server.type == "full" || server.config.sel != server.config.common) args ~= "-I" ~ server.location ~ server.config.common;
					foreach(v ; server.config.versions) args ~= "-version=" ~ v;
					foreach(c ; server.config.code) args ~= "-I" ~ c.replace("/", dirSeparator);
					foreach(f ; server.config.files) args ~= "-J" ~ f.replace("/", dirSeparator);
					/*if(!exists(exe) || force)*/ {
						StopWatch timer = StopWatch(AutoStart.yes);
						immutable full = server.type == "full";
						if(server.type == "node" || server.type == "full") {
							immutable src = server.location ~ server.config.sel.replace("/", dirSeparator) ~ dirSeparator ~ (server.type == "full" ? "node" ~ dirSeparator : "");
							string[] nargs = args.dup;
							wait(spawnShell("cd " ~ src ~ " && rdmd --build-only " ~ nargs.join(" ") ~ " init.d"));
							if(server.config.sel.length || server.type == "full") {
								write(server.location ~ "init" ~ __EXE__, read(src ~ "init" ~ __EXE__));
								version(Posix) executeShell("cd " ~ server.location ~ " && chmod u+x init");
							}
							wait(spawnShell("cd " ~ server.location ~ " && ." ~ dirSeparator ~ "init"));
							remove(server.location ~ "init" ~ __EXE__);
							if(server.config.sel.length) remove(src ~ "init" ~ __EXE__);
							if(exists(server.location ~ dirSeparator ~ ".hidden" ~ dirSeparator ~ "temp")) nargs ~= "-I" ~ tempDir() ~ dirSeparator ~ "sel" ~ dirSeparator ~ cast(string)read(server.location ~ dirSeparator ~ ".hidden" ~ dirSeparator ~ "temp"); // for compressed plugins (managed by init.d)
							wait(spawnShell("cd " ~ src ~ " && rdmd --build-only " ~ nargs.join(" ") ~ " main.d"));
							if(server.config.sel.length || server.type == "full" || server.name != "main") {
								write(server.location ~ "node" ~ __EXE__, read(src ~ "main" ~ __EXE__));
								remove(src ~ "main" ~ __EXE__);
								version(Posix) executeShell("cd " ~ server.location ~ " && chmod u+x node");
							}
						}
						if(server.type == "hub" || server.type == "full") {
							immutable src = server.location ~ server.config.sel.replace("/", dirSeparator) ~ dirSeparator ~ (server.type == "full" ? "hub" ~ dirSeparator : "");
							wait(spawnShell("cd " ~ src ~ " && rdmd --build-only " ~ args.join(" ") ~ " main.d"));
							if(server.config.sel.length || server.type == "full" || server.name != "main") {
								write(server.location ~ "hub" ~ __EXE__, read(src ~ "main" ~ __EXE__));
								remove(src ~ "main" ~ __EXE__);
								version(Posix) executeShell("cd " ~ server.location ~ " && chmod u+x hub");
							}
						}
						timer.stop();
						writeln("Done. Compilation took ", timer.peek.msecs.to!float / 1000, " seconds.");
						//TODO write deprecations and errors
					}
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
		case "client":
			if(args.length > 2) {
				string g = args[1].toLower;
				uint game = ["pocket", "pe", "mcpe"].canFind(g) ? 1 : (["minecraft", "pc", "mc"].canFind(g) ? 2 : 0);
				if(game != 0) {
					string ip = args[2];
					args = args[3..$];
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
					immutable gamestr = game == 1 ? "pocket" : "minecraft";
					string username = find("username", "");
					string password = find("password", "");
					string options = find("options", "");
					uint protocol = find("protocol", 0);
					if(protocol == 0) {
						foreach(string path ; dirEntries(Settings.utils ~ "json" ~ dirSeparator ~ "protocol", SpanMode.breadth)) {
							if(path.isFile && path.indexOf(gamestr) > 0 && path.endsWith(".json")) {
								uint p = to!uint(path[path.indexOf(gamestr)+gamestr.length..$-5]);
								if(p > protocol) protocol = p;
							}
						}
					}
					immutable vers = protocol << 4 | game;
					args = [ip];
					if(username.length) args ~= ["-username=" ~ username];
					if(password.length) args ~= ["-password=" ~ password];
					if(options.length) args ~= ["-options=" ~ locationOf(options)];
					launchComponent!true("client", args, vers);
				} else {
					writeln("Invalid game");
				}
			} else {
				// client.exe ip:port username password
				writeln("Use '", launch, " client <game> <ip>[:port] [-protocol=latest] [-username=random]'");
			}
			break;
		case "compress":
			if(args.length > 2) {
				bool plugin;
				int level = 6;
				HeaderFormat format = HeaderFormat.gzip;
				foreach(arg ; args[3..$]) {
					if(arg == "-alg=deflate") format = HeaderFormat.deflate;
					else if(arg == "-alg=gzip") format = HeaderFormat.gzip;
					else if(arg.startsWith("-level=")) level = to!int(arg[7..$]);
					else if(arg == "-plugin") plugin = true;
				}
				immutable odir = args[2].indexOf(dirSeparator) >= 0 ? args[2].split(dirSeparator)[0..$-1].join(dirSeparator) : ".";
				version(Windows) {
					immutable input = executeShell("cd " ~ args[1] ~ " && cd").output.strip ~ dirSeparator;
					immutable o = executeShell("cd " ~ odir ~ " && cd").output.strip;
				} else {
					immutable input = executeShell("cd " ~ args[1] ~ " && pwd").output.strip ~ dirSeparator;
					immutable o = executeShell("cd " ~ odir ~ " && pwd").output.strip;
				}
				immutable name = args[2][args[2].indexOf(dirSeparator)+1..$];
				immutable ext = plugin ? ".ssa" : ".sa";
				immutable output = o ~ dirSeparator ~ (name.endsWith(ext) ? name : name ~ ext);
				if(plugin && !exists(input ~ "package.json")) {
					writeln("Cannot find plugin info at '", input, "package.json'");
					break;
				}
				writeln("Compressing ", input, " into ", output);
				string[] ignore_files = [".selignore"];
				string[] ignore_dirs = [];
				if(exists(input ~ dirSeparator ~ ".selignore")) {
					foreach(string line ; (cast(string)read(input ~ dirSeparator ~ ".selignore")).split("\n")) {
						version(Windows) {
							line = line.strip.replace(r"/", r"\");
						} else {
							line = line.strip.replace(r"\", r"/");
						}
						if(line != "") {
							if(line.endsWith(dirSeparator)) ignore_dirs ~= line;
							else ignore_files ~= line;
						}
					}
				}
				string file;
				size_t count = 0;
				foreach(string path ; dirEntries(input, SpanMode.breadth)) {
					immutable fpath = path;
					if(path.startsWith(input)) path = path[input.length..$];
					if(fpath.isFile && !ignore_files.canFind(path)) {
						bool valid = true;
						foreach(string dir ; ignore_dirs) {
							if(path.startsWith(dir)) {
								valid = false;
								break;
							}
						}
						if(!valid) continue;
						writeln("Adding ", path);
						count++;
						string content = cast(string)read(fpath);
						file ~= path.replace(dirSeparator, "/") ~ "\n" ~ to!string(content.length) ~ "\n" ~ content;
					}
				}
				writeln("Added ", count, " files (", file.length, " bytes)");
				Compress compress = new Compress(level, format);
				ubyte[] data = cast(ubyte[])compress.compress(file);
				data ~= cast(ubyte[])compress.flush();
				writeln("Compressed into ", data.length, " bytes (", to!float(to!size_t((1 - data.length.to!float / file.length) * 10000)) / 100, "% smaller)");
				if(plugin) {
					try {
						auto json = parseJSON(cast(string)read(input ~ "package.json"));
						compress = new Compress(level, format);
						ubyte[] pack = cast(ubyte[])compress.compress(json.toString());
						pack ~= cast(ubyte[])compress.flush();
						data = cast(ubyte[])"plugn" ~ nativeToBigEndian(pack.length.to!uint) ~ pack ~ data;
					} catch(JSONException e) {
						writeln("Error whilst reading package.json: ", e.msg);
						break;
					}
				}
				write(output, data);
				writeln("Saved at ", output);
			} else {
				writeln("Use '", launch, " compress <source> <destination> [-level=6] [-alg=gzip] [-plugin]'");
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
						void connect() {
							wait(spawnShell("cd " ~ server.location ~ " && ." ~ dirSeparator ~ "node " ~ name ~ " " ~ ip ~ " " ~ to!string(port) ~ " " ~ to!string(main) ~ " " ~ password));
						}
						connect();
						// reconnect the node when it stops until sel manager is closed
						if(args.canFind("-loop")) {
							while(true) connect();
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
				ptrdiff_t vers = 1; // latest
				if(args.length > 2) {
					try {
						vers = to!uint(args[2]);
					} catch(ConvException) {}
				}
				launchComponent!true("console", [args[1]], vers);
			} else {
				writeln("Use '", launch, " console <ip>[:port]'");
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
							if(file.isFile) remove(file);
						}
						rmdirRecurse(server.location);
					}
				} else {
					writeln("There's no server named \"", args[1].toLower, "\"");
				}
			} else {
				writeln("Use: '", launch, " delete <server> [delete-files=true]");
			}
			break;
		case "init":
			if(args.length > 2) {
				string name = args[1].toLower;
				string type = args[2].toLower;
				args = args[3..$];
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
				string vers = find("version", "latest").toLower;
				string[] flags;
				if(args.canFind("-edu")) flags ~= "Edu";
				if(args.canFind("-realm")) flags ~= "Realm";
				if(!nameExists(name)) {
					if(!noname.canFind(name)) {
						if(type == "hub" || type == "node" || type == "full") {
							// get real path
							version(Windows) {
								executeShell("mkdir \\a " ~ path);
								path = executeShell("cd " ~ path ~ " && cd").output.strip;
							} else {
								// not tested yet
								executeShell("mkdir -p " ~ path);
								path = executeShell("cd " ~ path ~ " && pwd").output.strip;
							}
							if(!path.endsWith(dirSeparator)) path ~= dirSeparator;
							if(vers != "none") {
								install(launch, path, type, vers);
							}
							auto server = ServerTuple(name, path, type, Config.init);
							setDefaultConfig(server);
							server.config.versions ~= flags;
							saveServerTuples(serverTuples ~ server);
						} else {
							writeln("Invalid type \"", type, "\". Choose between \"full\", \"hub\", and \"node\"");
						}
					} else {
						writeln("Cannot name a server \"", name, "\"");
					}
				} else {
					writeln("A server named \"", name, "\" already exists");
				}
			} else {
				writeln("Use '", launch, " init <server> <hub|node|full> [-version=latest] [-path=] [-edu] [-realm]'");
			}
			break;
		case "latest":
			//TODO get it from the internet
			writeln("1.0.0");
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
						immutable cmd = "nautilus";
					}
					wait(spawnShell(cmd ~ " " ~ getServerByName(args[1].toLower).location));
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
		static if(__shortcut) {
			case "shortcut":
			if(args.length > 1) {
				auto server = getServerByName(args[1].toLower);
				if(server.name != "") {
					write(server.location ~ "script.d", "module script;import std.process;import std.string;void main(string[] args){args[0]=\"" ~ server.name ~ "\";wait(spawnShell(\"sel \"~args.join(\" \")));}");
					wait(spawnShell("cd " ~ server.location ~ " && rdmd --build-only -release script.d"));
					remove(server.location ~ "script.d");
					wait(spawnShell("sudo mv " ~ server.location ~ "script /usr/bin/" ~ server.name));
					writeln("You can now use '", server.name, " <command> [options]' as a shortcut for '", launch, " <command> ", server.name, " [options]'");
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
					if(server.type == "hub") {
						do {
							wait(spawnShell("cd " ~ server.location ~ " && ." ~ dirSeparator ~ "hub"));
						} while(loop);
					} else if(server.type == "full") {
						bool rebuild;
						do {
							rebuild = false;
							if(exists(server.location ~ "resources" ~ dirSeparator ~ ".handshake")) remove(server.location ~ "resources" ~ dirSeparator ~ ".handshake");
							new Thread({ wait(spawnShell("cd " ~ server.location ~ " && ." ~ dirSeparator ~ "hub")); }).start();
							executeShell("cd " ~ server.location ~ " && ." ~ dirSeparator ~ "node");
							if(exists(server.location ~ ".hidden" ~ dirSeparator ~ "rebuild")) {
								rebuild = true;
								remove(server.location ~ ".hidden" ~ dirSeparator ~ "rebuild");
								wait(spawnShell(launch ~ " build " ~ server.name));
							}
						} while(loop || rebuild);
					} else {
						writeln("Server \"", server.name, "\" is not an hub");
					}
				} else {
					writeln("There's no server named \"", args[1].toLower, "\"");
				}
			} else {
				writeln("Use: '", launch, " start <server> [-loop]'");
			}
			break;
		case "uncompress":
			if(args.length > 2) {
				immutable output = args[2].endsWith(dirSeparator) ? args[2] : args[2] ~ dirSeparator;
				if(!exists(output)) {
					mkdirRecurse(output);
				}
				import std.zlib : UnCompress;
				UnCompress uncompress = new UnCompress();
				ubyte[] data = cast(ubyte[])uncompress.uncompress(read(args[1]));
				data ~= cast(ubyte[])uncompress.flush();
				string file = cast(string)data;
				while(file.length > 0) {
					string pname = file[0..file.indexOf("\n")].replace("/", dirSeparator);
					file = file[file.indexOf("\n")+1..$];
					size_t length = to!size_t(file[0..file.indexOf("\n")]);
					file = file[file.indexOf("\n")+1..$];
					string content = file[0..length];
					file = file[length..$];
					if(pname.indexOf(dirSeparator) >= 0) {
						mkdirRecurse(output ~ pname.split(dirSeparator)[0..$-1].join(dirSeparator));
					}
					write(output ~ pname, content);
				}
			} else {
				writeln("Use '", launch, " uncompress <archive> <destination>'");
			}
			break;
		case "update":
			if(args.length > 1) {
				immutable name = args[1].toLower;
				switch(name) {
					case "*":
					case "all":
						wait(spawnShell(launch ~ " update sel"));
						wait(spawnShell(launch ~ " update libs"));
						foreach(ServerTuple server ; serverTuples) {
							wait(spawnShell(launch ~ " update " ~ server.name));
						}
						break;
					case "lib":
					case "libs":
					case "util":
					case "utils":
						// download or update sel-utils
						systemDownload(__UTILS__, Settings.config ~ "utils.sa");
						wait(spawnShell("cd " ~ Settings.config ~ " && " ~  launch ~ " uncompress utils.sa utils"));
						remove(Settings.config ~ "utils.sa");
						break;
					default:
						auto server = getServerByName(name);
						if(server.name.length) {
							string vers = "";
							foreach(a ; args) {
								if(a.startsWith("-version=")) {
									vers = a[9..$];
									break;
								}
							}
							install(launch, server.location, server.type, vers);
						} else {
							writeln("There's no server named \"", args[1].toLower, "\"");
						}
						break;
				}
			} else {
				writeln("Use: '", launch, " update utils|<server> [-version=latest]'");
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
	writeln("Website: http://selproject.org");
	writeln("Downloads: " ~ __DOWNLOAD__);
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
				auto server = ServerTuple(cast(string)Base64.decode(spl[0]), spl[1], spl[2], Config.init);
				if(exists(server.location ~ ".config")) {
					foreach(string line ; (cast(string)read(server.location ~ ".config")).split("\n")) {
						string[] ls = line.split("=");
						if(ls.length >= 2) {
							immutable res = ls[1..$].join("=").strip;
							if(res.length) {
								final switch(ls[0].strip) {
									case "sel":
										server.config.sel = res;
										break;
									case "common":
										server.config.common = res;
										break;
									case "versions":
										server.config.versions = res.split(",");
										break;
									case "code":
										server.config.code = res.split(",");
										break;
									case "files":
										server.config.files = res.split(",");
										break;
								}
							}
						}
					}
				} else {
					setDefaultConfig(server);
				}
				ret ~= server;
			}
		}
	}
	return ret;
}

void setDefaultConfig(ref ServerTuple server) {
	server.config.sel = "src" ~ dirSeparator;
	server.config.common = "src" ~ dirSeparator;
	server.config.code = [Settings.utils ~ "src" ~ dirSeparator ~ "d"];
	if(server.type == "full" || server.type == "node") server.config.files ~= ".." ~ dirSeparator ~ ".." ~ dirSeparator ~ ".hidden";
	else if(server.type == "node") server.config.files ~= ".." ~ dirSeparator ~ ".hidden";
	if(server.type == "full") server.config.code ~= ".." ~ dirSeparator ~ ".." ~ dirSeparator ~ "plugins";
	else if(server.type == "node") server.config.code ~= ".." ~ dirSeparator ~ "plugins";
	if(server.type == "full") server.config.files ~= ".." ~ dirSeparator ~ ".." ~ dirSeparator ~ "resources";
	else if(server.type == "hub") server.config.files ~= ".." ~ dirSeparator ~ "resources";
	if(server.type == "full") server.config.versions ~= "OneNode";
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
		return ServerTuple(loc, loc, "node", Config.init);
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
		file ~= Base64.encode(cast(ubyte[])server[0]) ~ "," ~ server[1] ~ "," ~ server[2] ~ newline;
		write(server.location ~ ".config", "sel=" ~ server.config.sel ~ newline ~ "common=" ~ server.config.common ~ newline ~ "versions=" ~ server.config.versions.join(",") ~ newline ~ "code=" ~ server.config.code.join(",") ~ newline ~ "files=" ~ server.config.files.join(","));
		version(Windows) {
			import core.sys.windows.winnt : FILE_ATTRIBUTE_HIDDEN;
			setAttributes(server.location ~ ".config", FILE_ATTRIBUTE_HIDDEN);
		}
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

void install(string launch, string path, string type, string vers) {
	if(!vers.length || vers == "latest") vers = executeShell(launch ~ " latest").output.strip;
	if(!exists(Settings.cache ~ vers)) {
		if(!exists(Settings.cache ~ vers ~ ".sa")) {
			immutable dl = __DOWNLOAD__ ~ "download/v" ~ vers ~ "/" ~ vers ~ ".sa";
			writeln("Downloading from " ~ dl);
			mkdirRecurse(Settings.cache);
			systemDownload(dl, Settings.cache ~ vers ~ ".sa");
		}
		executeShell("cd " ~ Settings.cache ~ " && " ~ launch ~ " uncompress " ~ vers ~ ".sa " ~ vers);
	}
	// copy files from x.x.x/ to path/
	immutable dec = Settings.cache ~ vers ~ dirSeparator;
	void copy(string from, string to) {
		foreach(string p ; dirEntries(from, SpanMode.depth)) {
			immutable dest = to ~ p[from.length..$];
			if(p.isFile) {
				mkdirRecurse(dest[0..dest.lastIndexOf(dirSeparator)]);
				write(dest, read(p));
			}
		}
	}
	if(type == "hub") {
		copy(dec ~ "hub", path ~ "src");
	} else if(type == "node") {
		copy(dec ~ "node", path ~ "src");
	} else if(type == "full") {
		copy(dec ~ "hub", path ~ "src" ~ dirSeparator ~ "hub");
		copy(dec ~ "node", path ~ "src" ~ dirSeparator ~ "node");
	}
	copy(dec ~ "common", path ~ "src" ~ dirSeparator ~ "common");
	copy(dec ~ "res", path ~ "src" ~ dirSeparator ~ "res");
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
	if(!exists(Settings.config ~ "components" ~ dirSeparator ~ component ~ ext)) {
		systemDownload(__COMPONENTS__ ~ name ~ ".d", Settings.config ~ "components" ~ dirSeparator ~ component ~ ".d");
		write(Settings.config ~ "components" ~ dirSeparator ~ "version.txt", to!string(vers));
		wait(spawnShell("cd " ~ Settings.config ~ "components && rdmd --build-only -J. -I" ~ Settings.config ~ "utils" ~ dirSeparator ~ "src" ~ dirSeparator ~ "d " ~ component ~ ".d"));
		remove(Settings.config ~ "components" ~ dirSeparator ~ component ~ ".d");
		remove(Settings.config ~ "components" ~ dirSeparator ~ "version.txt");
	}
	immutable cmd = "cd " ~ Settings.config ~ "components && " ~ runnable ~ " " ~ args.join(" ");
	static if(spawn) {
		wait(spawnShell(cmd));
		return "";
	} else {
		return executeShell(cmd).output.strip;
	}
}

void systemDownload(string file, string dest) {
	HTTP http = HTTP();
	http.handle.set(CurlOption.ssl_verifypeer, false);
	http.handle.set(CurlOption.timeout, 10);
	download(file, dest, http);
}
