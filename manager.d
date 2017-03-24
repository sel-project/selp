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
import std.file;
import std.json;
import std.path : dirSeparator, pathSeparator;
import std.process;
import std.regex : ctRegex, replaceAll;
import std.stdio : writeln, readln;
import std.string;
import std.typecons : Tuple, tuple;
import std.utf : toUTF8;
import std.zlib : Compress, UnCompress, HeaderFormat;

alias Config = Tuple!(string, "sel", string, "common", string[], "versions", string[], "code", string[], "files");

alias ServerTuple = Tuple!(string, "name", string, "location", string, "type", bool, "deleteable", Config, "config");

enum __MANAGER__ = "4.6.0";
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

enum commands = ["about", "build", "clear", "connect", "console", "convert", "delete", "init", "latest", "list", "locate", "open", "ping", "plugin", "query", "rcon", "scan", "social", "start", "update"];

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
			writeln("  plugin      manage a server's plugins");
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
					JSONValue[string] data;
					if(server.type == "hub" || server.type == "full") {
						try {
							data["hub"] = parseJSON(executeShell("cd " ~ server.location ~ " && ." ~ dirSeparator ~ "hub about").output);
						} catch(JSONException) {}
					}
					if(server.type == "node" || server.type == "full") {
						try {
							data["node"] = parseJSON(executeShell("cd " ~ server.location ~ "&& ." ~ dirSeparator ~ "node about").output);
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
					args = args[2..$];
					if(server.type == "full" || server.config.sel != server.config.common) args ~= "-I" ~ server.location ~ server.config.common;
					foreach(v ; server.config.versions) args ~= "-version=" ~ v;
					foreach(c ; server.config.code) args ~= "-I" ~ c.replace("/", dirSeparator);
					foreach(f ; server.config.files) args ~= "-J" ~ f.replace("/", dirSeparator);
					bool node = server.type == "node" || server.type == "full";
					bool hub = server.type == "hub" || server.type == "full";
					// do not build the hub when the type is full and the version is not changed
					if(server.type == "full") {
						try {
							auto data = parseJSON(executeShell(launch ~ " about " ~ server.name ~ " -json").output);
							if(data.type == JSON_TYPE.OBJECT) {
								auto hub_data = "hub" in data;
								if(hub_data && hub_data.type == JSON_TYPE.OBJECT) {
									//TODO compare with source
								}
							}
						} catch(JSONException) {}
					}
					{
						//version(Windows) compileLibraries(); //TODO only if outdated
						bool failed = false;
						StopWatch timer = StopWatch(AutoStart.yes);
						immutable full = server.type == "full";
						if((server.type == "hub" || server.type == "full") && !failed) {
							immutable src = server.location ~ server.config.sel.replace("/", dirSeparator) ~ dirSeparator ~ (server.type == "full" ? "hub" ~ dirSeparator : "");
							/+version(Windows) {
								// build using sul.lib
								foreach(ref arg ; args) {
									if(arg.indexOf("utils") > 0) arg = "";
								}
								args = ("-L" ~ Settings.config ~ "libs" ~ dirSeparator ~ "sul.lib") ~ args;
							}+/
							wait(spawnShell("cd " ~ src ~ " && rdmd --build-only " ~ args.join(" ") ~ " main.d"));
							failed = !exists(src ~ "main" ~ __EXE__);
							if(!failed && (server.config.sel.length || server.type == "full" || server.name != "main")) {
								write(server.location ~ "hub" ~ __EXE__, read(src ~ "main" ~ __EXE__));
								remove(src ~ "main" ~ __EXE__);
								version(Posix) executeShell("cd " ~ server.location ~ " && chmod u+x hub");
								executeShell("cd " ~ server.location ~ " && ." ~ dirSeparator ~ "hub init");
							}
						}
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
							failed = !exists(src ~ "main" ~ __EXE__);
							if(!failed && (server.config.sel.length || server.type == "full" || server.name != "main")) {
								write(server.location ~ "node" ~ __EXE__, read(src ~ "main" ~ __EXE__));
								remove(src ~ "main" ~ __EXE__);
								version(Posix) executeShell("cd " ~ server.location ~ " && chmod u+x node");
							}
						}
						timer.stop();
						if(failed) writeln("Failed in ", timer.peek.msecs.to!float / 1000, " seconds.");
						else writeln("Done. Compilation took ", timer.peek.msecs.to!float / 1000, " seconds.");
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
				Tuple!(string, string)[] paths;
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
						if(valid) paths ~= tuple(path, fpath);
					}
				}
				sort!"a[0] < b[0]"(paths);
				ubyte[] file;
				foreach(path ; paths) {
					auto content = read(path[1]);
					writeln("Adding ", path[0], " (", content.length, " bytes)");
					file ~= cast(ubyte[])replace(path[0], dirSeparator, "/");
					file ~= ubyte.init;
					file ~= nativeToBigEndian!uint(content.length.to!uint);
					file ~= cast(ubyte[])content;
				}
				writeln("Added ", paths.length, " files (", file.length, " bytes)");
				Compress compress = new Compress(level, format);
				ubyte[] data = cast(ubyte[])"sel-archive-2";
				data ~= cast(ubyte[])compress.compress(file);
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
				string type = args.length > 2 ? args[2].toLower : "full";
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
								install(launch, path, type, user, repo, vers);
							}
							auto server = ServerTuple(name, path, type, !args.canFind("-no-delete"), Config.init);
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
				writeln("Use '", launch, " init <server> <hub|node|full> [-user=sel-project] [-repo=sel-server] [-version=latest] [-path=] [-edu] [-realm] [-no-delete]'");
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
				download("https://raw.githubusercontent.com/" ~ user ~ "/" ~ repo ~ "/master/.latest", latest);
				write(time, nativeToBigEndian(Clock.currTime().toUnixTime!int()));
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
		case "plugin":
			if(args.length > 3 && ["add", "update", "remove"].canFind(args[2])) {
				auto server = getServerByName(args[1].toLower);
				if(server.name.length) {
					immutable plugin = args[3].toLower;
					immutable location = server.location ~ "plugins" ~ dirSeparator;
					if(!exists(location)) mkdirRecurse(location);
					final switch(args[2]) {
						case "add":
							if(!exists(location ~ plugin ~ ".ssa") && !exists(location ~ plugin)) {
								//TODO from generic url
								auto file = "https://github.com/sel-project/sel-plugins/blob/master/releases/" ~ args[3].toLower ~ ".ssa?raw=true";
								try {
									download(file, location ~ plugin ~ ".ssa");
									writeln("The plugin has been installed");
								} catch(Exception e) {
									writeln("Cannot download the plugin: ", e.msg);
								}
							} else {
								writeln("A plugin with the same name is already installed");
							}
							break;
						case "update":
							// check for sa file
							// read "release" field in JSON
							// download
							break;
						case "remove":
							if(exists(location ~ plugin ~ ".ssa") && isFile(location ~ plugin ~ ".ssa")) {
								remove(location ~ plugin ~ ".ssa");
								writeln("The plugin has been successfully removed");
							} else if(exists(location ~ plugin)) {
								writeln("The plugin cannot be removed because it isn't a SEL archive");
							} else {
								writeln("The plugin is not installed");
							}
							break;
					}
				} else {
					writeln("There's no server named \"", args[1].toLower, "\"");
				}
			} else {
				writeln("Use '", launch, " <server> plugin [add|update|remove] <plugin>'");
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
				string file = cast(string)read(args[1]);
				uint v = 1;
				if(file.startsWith("sel-archive-2")) {
					v = 2;
					file = file["sel-archive-2".length..$];
				}
				import std.zlib : UnCompress;
				UnCompress uncompress = new UnCompress();
				ubyte[] data = cast(ubyte[])uncompress.uncompress(file);
				data ~= cast(ubyte[])uncompress.flush();
				if(v == 1) {
					file = cast(string)data;
					while(file.length) {
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
				} else if(v == 2) {
					size_t index = 0;
					while(index < data.length) {
						ubyte[] n;
						while(index < data.length - 4 && data[index++] != 0) n ~= data[index-1];
						string pname = (cast(string)n).replace("/", dirSeparator);
						size_t length = peek!uint(data, &index);
						if(pname.indexOf(dirSeparator) >= 0) {
							mkdirRecurse(output ~ pname.split(dirSeparator)[0..$-1].join(dirSeparator));
						}
						write(output ~ pname, data[index..index+length]);
						index += length;
					}
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
					case "comp":
					case "components":
						foreach(comp ; dirEntries(Settings.config ~ "components", SpanMode.breadth)) {
							if(comp.isFile) remove(comp);
						}
						break;
					case "lib":
					case "libs":
					case "util":
					case "utils":
						// download or update sel-utils
						mkdirRecurse(Settings.config);
						download(__UTILS__, Settings.config ~ "utils.sa");
						wait(spawnShell("cd " ~ Settings.config ~ " && " ~  launch ~ " uncompress utils.sa utils"));
						remove(Settings.config ~ "utils.sa");
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
							install(launch, server.location, server.type, user, repo, vers);
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
	writeln("Website: http://selproject.org");
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
				auto server = ServerTuple(cast(string)Base64.decode(spl[0]), spl[1], spl[2], spl.length>=4?to!bool(spl[3]):true, Config.init);
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
		return ServerTuple(loc, loc, "node", true, Config.init);
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
		if(exists(server.location ~ ".config")) remove(server.location ~ ".config");
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

void install(string launch, string path, string type, string user, string repo, string vers) {
	if(!vers.length || vers == "latest") vers = executeShell(launch ~ " latest").output.strip;
	immutable dest = Settings.cache ~ user ~ dirSeparator ~ repo ~ dirSeparator;
	if(!exists(dest ~ vers)) {
		// download and uncompress
		if(!exists(dest ~ vers ~ ".sa")) {
			immutable dl = "https://github.com/" ~ user ~ "/" ~ repo ~ "/releases/download/v" ~ vers ~ "/" ~ vers ~ ".sa";
			writeln("Downloading from " ~ dl);
			mkdirRecurse(dest);
			download(dl, dest ~ vers ~ ".sa");
		}
		executeShell("cd " ~ dest ~ " && " ~ launch ~ " uncompress " ~ vers ~ ".sa " ~ vers);
	}
	// update res if the downloaded version is newer
	long versionOf(string v) {
		auto spl = v.split(".");
		if(spl.length >= 2 && spl.length <= 4) {
			try {
				ulong ret = 0;
				foreach(i, shift; [48, 32, 16, 0]) {
					if(spl.length > i) ret += to!ulong(spl[i]) << shift;
				}
				return ret;
			} catch(ConvException) {}
		}
		return -1;
	}
	if(!exists(dest ~ "res" ~ dirSeparator ~ ".version") || versionOf(vers) > versionOf(cast(string)read(dest ~ "res" ~ dirSeparator ~ ".version"))) {
		immutable dl = "https://github.com/" ~ user ~ "/" ~ repo ~ "/blob/master/res/res.sa?raw=true";
		writeln("Updating res from " ~ dl);
		download(dl, dest ~ "res.sa");
		executeShell("cd " ~ dest ~ " && " ~ launch ~ " uncompress res.sa res");
		write(dest ~ "res" ~ dirSeparator ~ ".version", vers);
		remove(dest ~ "res.sa");
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
	if(type == "hub") {
		copy(dec ~ "hub", path ~ "src");
	} else if(type == "node") {
		copy(dec ~ "node", path ~ "src");
	} else if(type == "full") {
		copy(dec ~ "hub", path ~ "src" ~ dirSeparator ~ "hub");
		copy(dec ~ "node", path ~ "src" ~ dirSeparator ~ "node");
	}
	copy(dec ~ "common", path ~ "src" ~ dirSeparator ~ "common");
	copy(dest ~ "res", path ~ "src" ~ dirSeparator ~ "res");
}

void compileLibraries() {
	mkdirRecurse(Settings.config ~ "libs");
	void compileLibrary(string loc, string dest) {
		if(exists(dest)) remove(dest);
		if(!loc.endsWith(dirSeparator)) loc ~= dirSeparator;
		string[] files;
		foreach(file ; dirEntries(loc, SpanMode.breadth)) {
			if(file.isFile) files ~= file[loc.length..$];
		}
		wait(spawnShell("cd " ~ loc ~ " && dmd -lib " ~ files.join(" ")));
		immutable lib = loc ~ files[0].split(dirSeparator)[$-1][0..$-1] ~ "lib";
		write(dest, read(lib));
		remove(lib);
	}
	compileLibrary(Settings.utils ~ "src" ~ dirSeparator ~ "d", Settings.config ~ "libs" ~ dirSeparator ~ "sul.lib");
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
		download(__COMPONENTS__ ~ name ~ ".d", Settings.config ~ "components" ~ dirSeparator ~ component ~ ".d");
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

string get(string file) {
	static import std.net.curl;
	auto http = std.net.curl.HTTP();
	http.handle.set(CurlOption.ssl_verifypeer, false);
	http.handle.set(CurlOption.timeout, 10);
	return std.net.curl.get(file, http).idup;
}

void download(string file, string dest) {
	static import std.net.curl;
	auto http = std.net.curl.HTTP();
	http.handle.set(CurlOption.ssl_verifypeer, false);
	http.handle.set(CurlOption.timeout, 10);
	std.net.curl.download(file, dest, http);
}
