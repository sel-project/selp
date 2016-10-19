/*
 * Copyright (c) 2016 SEL
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

import core.thread : Thread, dur;

import std.algorithm : min;
import std.base64 : Base64;
import std.conv : to;
import std.file;
import std.json;
import std.net.curl : get, download;
import std.path : dirSeparator, pathSeparator;
import std.process;
import std.stdio : writeln, readln;
import std.string;
import std.typecons : Tuple, tuple;

alias ServerTuple = Tuple!(string, "name", string, "location", string, "type");

enum __MANAGER__ = "3.2.72";
enum __WEBSITE__ = "http://downloads.selproject.org/";
enum __COMPONENTS__ = "https://raw.githubusercontent.com/sel-project/sel-manager/master/components/";
enum __UTILS__ = "https://raw.githubusercontent.com/sel-project/sel-utils/master/release.sa";

version(Windows) {
	enum __NEW_LINE__ = "\r\n";
	enum __EXECUTABLE__ = "main.exe";
} else {
	enum __NEW_LINE__ = "\n";
	enum __EXECUTABLE__ = "main";
}

enum commands = ["about", "build", "connect", "console", "convert", "delete", "init", "latest", "list", "locate", "ping", "query", "rcon", "start", "update"];

enum noname = [".", "*", "all", "sel", "this", "manager", "lib", "libs", "util", "utils"];

struct Settings {
	
	@disable this();
	
	public static string home;
	public static string config;
	public static string cache;
	public static string servers;
	public static string utils;
	
}

void main(string[] args) {

	version(Windows) {
		Settings.home = executeShell("echo %appdata%").output.strip;
	} else {
		Settings.home = executeShell("cd ~ && pwd").output.strip;
	}
	if(!Settings.home.endsWith(dirSeparator)) Settings.home ~= dirSeparator;
	Settings.config = Settings.home ~ ".sel" ~ dirSeparator;
	Settings.cache = Settings.config ~ "versions" ~ dirSeparator;
	Settings.servers = Settings.home ~ "sel" ~ dirSeparator;
	Settings.utils = Settings.config ~ "utils" ~ dirSeparator; 
	
	string launch = args[0];
	args = args[1..$];
	
	if(args.length == 0) args ~= "help";

	if(!in_array(args[0], commands) && args.length > 1 && nameExists(args[0])) {
		string c = args[1];
		args[1] = args[0];
		args[0] = c;
	}
	
	switch(args[0]) {
		case "help":
			printusage();
			writeln("  about   \tprint informations about a server");
			writeln("  build   \tbuild a server");
			writeln("  connect \tstart a node server and connect it to an hub");
			writeln("  console \tconnect to a server throught the external console protocol");
			writeln("  convert \tconvert a world to another format");
			writeln("  delete  \tdelete a server");
			writeln("  init    \tcreate a new server");
			writeln("  latest  \tprint the latest stable version of SEL");
			writeln("  list    \tlist every registered server");
			writeln("  locate  \tprint the location of a server");
			writeln("  ping    \tping a server (not necessarily a sel one)");
			writeln("  query   \tquery a server (not necessarily a sel one)");
			writeln("  rcon    \tconnect to a server through the rcon protocol");
			version(linux) {
				writeln("  shortcut\tcreate a shortcut for a server (requires root permissions)");
			}
			writeln("  start   \tstart an hub server");
			writeln("  update  \tupdate a server");
			break;
		case "about":
			if(args.length > 1) {
				auto server = getServerByName(args[1].toLower);
				if(server.name != "") {
					immutable exe = server.location ~ (server.type == "node" ? __EXECUTABLE__ : "build.jar");
					if(exists(exe)) {
						if(server.type == "node") {
							wait(spawnShell(exe ~ " about"));
						} else {
							wait(spawnShell("java -jar " ~ exe ~ " about"));
						}
					} else {
						writeln("The server hasn't been built yet");
					}
				} else {
					writeln("There's no server named \"", args[1].toLower, "\"");
				}
			} else {
				writeln("Use: '", launch, " about <server-name>'");
			}
			break;
		case "build":
			if(args.length > 1) {
				auto server = getServerByName(args[1].toLower);
				if(server.name != "") {
					immutable exe = server.location ~ (server.type == "node" ? __EXECUTABLE__ : "build.jar");
					bool force = true;
					foreach(size_t i, string arg; args) {
						if(arg.startsWith("-force=")) {
							force = to!bool(arg[7..$]);
							args = args[0..i] ~ args[i+1..$];
							break;
						}
						if(arg == "-version=Pocket" || arg == "-version=Minecraft") {
							// cannot modify this!
							args = args[0..i] ~ args[i+1..$];
						}
					}
					if(!exists(exe) || force) {
						if(exists(exe)) remove(exe);
						if(server.type == "node") {
							wait(spawnShell("cd " ~ server.location ~ " && rdmd -version=NoRead init.d"));
							string versions = cast(string)read(server.location ~ "plugins" ~ dirSeparator ~ ".versions");
							string[] games = ["Pocket", "Minecraft"];
							if(exists(server.location ~ "plugins" ~ dirSeparator ~ ".configuration")) {
								games = [];
								write(server.location ~ "__version.d", "module v;import std.stdio;mixin(import(\".configuration\"));void main(string[] args){if(__MCPE_ACCEPTED_PROTOCOLS__.length>0){writeln(\"Pocket\");}if(__MC_ACCEPTED_PROTOCOLS__.length>0){writeln(\"Minecraft\");}}");
								foreach(string g ; executeShell("cd " ~ server.location ~ " && rdmd -Jplugins __version.d").output.split("\n")) {
									g = g.strip;
									if(g != "") games ~= g;
								}
								remove(server.location ~ "__version.d");
							}
							wait(spawnShell("cd " ~ server.location ~ " && rdmd --build-only -Jplugins " ~ ((){string str="";foreach(string g;games){str~="-version="~g~" ";}return str;}()) ~ " " ~ versions ~ " " ~ args[2..$].join(" ") ~ " main.d"));
						} else {
							if(hasCommand("javac")) {
								if(exists(server.location ~ "bin")) rmdirRecurse(server.location ~ "bin");
								mkdirRecurse(server.location ~ "bin");
								version(Windows) {
									//TODO copy lib into bin\lib
									executeShell("cd " ~ server.location ~ " && dir /s /B *.java > " ~ server.location ~ "sources.txt");
									executeShell("cd " ~ server.location ~ " && dir /s /B lib\\*.jar > " ~ server.location ~ "libs.txt");
									executeShell("cd " ~ server.location ~ "bin && dir /s /B lib\\*jar > " ~ server.location ~ "bin" ~ dirSeparator ~ "libs.txt");
								} else {
									executeShell("cd " ~ server.location ~ " && cp -r lib bin/lib");
									executeShell("cd " ~ server.location ~ " && find sel -name \"*.java\" > " ~ server.location ~ "sources.txt");
									executeShell("cd " ~ server.location ~ " && find lib -name \"*.jar\" > " ~ server.location ~ "libs.txt");
									executeShell("cd " ~ server.location ~ "bin && find lib -name \"*.jar\" > " ~ server.location ~ "bin" ~ dirSeparator ~ "libs.txt");
								}
								string libs = (cast(string)read(server.location ~ "libs.txt")).replace(__NEW_LINE__, pathSeparator) ~ ".";
								wait(spawnShell("cd " ~ server.location ~ " && javac -cp " ~ libs ~ " -d bin @sources.txt"));
								version(Windows) {
									executeShell("cd " ~ server.location ~ " && dir /s /B bin\\*.class > " ~ server.location ~ "sources.txt");
								} else {
									executeShell("cd " ~ server.location ~ "/lib && find sel -name \"*.class\" > " ~ server.location ~ "sources.txt");
								}
								//wait(spawnShell("cd " ~ server.location ~ " && java -cp " ~ libs ~ " @sources.txt"));
								write(server.location ~ "bin" ~ dirSeparator ~ "manifest.txt", "Main-Class: sel.Main" ~ __NEW_LINE__ ~ "Class-Path: " ~ (cast(string)read(server.location ~ "bin" ~ dirSeparator ~ "libs.txt")).replace(__NEW_LINE__, " ") ~ __NEW_LINE__);
								wait(spawnShell("cd " ~ server.location ~ "bin && jar cfm build.jar manifest.txt sel" ~ dirSeparator ~ "*"));
								write(server.location ~ "build.jar", read(server.location ~ "bin" ~ dirSeparator ~ "build.jar"));
								remove(server.location ~ "sources.txt");
								remove(server.location ~ "libs.txt");
								remove(server.location ~ "bin" ~ dirSeparator ~ "manifest.txt");
								remove(server.location ~ "bin" ~ dirSeparator ~ "libs.txt");
								remove(server.location ~ "bin" ~ dirSeparator ~ "build.jar");
							} else {
								writeln("Java Development Kit (JDK) is not installed on this device and the hub cannot be built without it");
							}
						}
					}
				} else {
					writeln("There's no server named \"", args[1].toLower, "\"");
				}
			} else {
				writeln("Use: '", launch, " build <server-name> [<options>]'");
			}
			break;
		case "compress":
			// sel compress <dir> <output-file> <compression=6>
			immutable odir = args[2].indexOf(dirSeparator) >= 0 ? args[2].split(dirSeparator)[0..$-1].join(dirSeparator) : ".";
			version(Windows) {
				immutable input = executeShell("cd " ~ args[1] ~ " && cd").output.strip ~ dirSeparator;
				immutable o = executeShell("cd " ~ odir ~ " && cd").output.strip;
			} else {
				immutable input = executeShell("cd " ~ args[1] ~ " && pwd").output.strip ~ dirSeparator;
				immutable o = executeShell("cd " ~ odir ~ " && pwd").output.strip;
			}
			immutable name = args[2][args[2].indexOf(dirSeparator)+1..$];
			immutable output = o ~ dirSeparator ~ (name.endsWith(".sa") ? name : name ~ ".sa");
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
				if(fpath.isFile && !in_array(path, ignore_files)) {
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
			import std.zlib : Compress;
			Compress compress = new Compress(args.length > 3 ? to!uint(args[3]) : 6);
			ubyte[] data = cast(ubyte[])compress.compress(file);
			data ~= cast(ubyte[])compress.flush();
			writeln("Compressed into ", data.length, " bytes");
			write(output, data);
			writeln("Saved at ", output);
			break;
		case "connect":
			if(args.length > 1) {
				auto server = getServerByName(args[1].toLower);
				if(server.name != "") {
					if(server.type == "node") {
						string name = args.length > 2 ? args[2] : server.name;
						string ip = args.length > 3 ? args[3] : "127.0.0.1";
						string port = args.length > 4 ? args[4] : "28232";
						version(Windows) {
							void connect() {
								wait(spawnShell("cd " ~ server.location ~ " && " ~ __EXECUTABLE__ ~ " " ~ name ~ " " ~ ip ~ " " ~ port));
							}
						} else {
							void connect() {
								wait(spawnShell("cd " ~ server.location ~ " && ./" ~ __EXECUTABLE__ ~ " " ~ name ~ " " ~ ip ~ " " ~ port ~ " \"sel node\""));
							}
						}
						wait(spawnShell(launch ~ " build " ~ server.name ~ " -force=false"));
						immutable pdir = server.location ~ "plugins" ~ dirSeparator ~ ".configuration";
						string protocols = exists(pdir) ? cast(string)read(pdir) : "";
						connect();
						// the node is built again if the the hub requires it
						if(exists(pdir) && cast(string)read(pdir) != protocols) {
							wait(spawnShell(launch ~ " build " ~ server.name ~ " -force=true"));
							connect();
						}
					} else {
						writeln("Server \"", server.name, "\" is not a node");
					}
				} else {
					writeln("There's no server name \"", args[1].toLower, "\"");
				}
			} else {
				writeln("Use: '", launch, " connect <node-name> [<name>=<node-name>] [<hub>=127.0.0.1] [<hub-port>=28232]'");
			}
			break;
		case "console":
			if(args.length > 1) {
				launchComponent!true("console", args[1..$]);
			} else {
				writeln("Use '", launch, " console <ip>[:<port>] <password> [<send-commands>=false]'");
			}
			break;
		case "convert":
			if(args.length > 4) {
				string ffrom = args[1].toLower;
				string fto = args[2].toLower;
				launchComponent!true("convert", [ffrom, fto, args[3], args[4]]);
			} else {
				writeln("Use '", launch, " convert <format-from> <format-to> <location-from> [<location-to>=.]'");
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
						rmdirRecurse(server.location);
					}
				} else {
					writeln("There's no server named \"", args[1].toLower, "\"");
				}
			} else {
				writeln("Use: '", launch, " delete <server-name> [<delete-files>=true]");
			}
			break;
		case "init":
			if(args.length > 2) {
				string name = args[1].toLower;
				string type = args[2].toLower;
				string path = args.length > 3 ? args[3] : Settings.servers ~ name;
				string vers = args.length > 4 ? args[4].toLower : "";
				if(!nameExists(name)) {
					if(!in_array(name, noname)) {
						if(type == "hub" || type == "node") {
							// get real path
							version(Windows) {
								wait(spawnShell("md " ~ path));
								path = executeShell("cd " ~ path ~ " && cd").output.strip;
							} else {
								wait(spawnShell("mkdir -p " ~ path));
								path = executeShell("cd " ~ path ~ " && pwd").output.strip;
							}
							if(!path.endsWith(dirSeparator)) path ~= dirSeparator;
							if(vers != "none") {
								if(vers == "" || vers == "latest") vers = executeShell("sel latest").output.strip;
								if(!vers.endsWith(".sa")) vers ~= ".sa";
								if(!exists(Settings.cache ~ vers)) {
									writeln("Downloading from " ~ __WEBSITE__ ~ vers);
									mkdirRecurse(Settings.cache);
									download(__WEBSITE__ ~ vers, Settings.cache ~ vers);
								}
								import std.zlib : UnCompress;
								UnCompress uncompress = new UnCompress();
								ubyte[] data = cast(ubyte[])uncompress.uncompress(read(Settings.cache ~ vers));
								data ~= cast(ubyte[])uncompress.flush();
								string file = cast(string)data;
								while(file.length > 0) {
									string pname = file[0..file.indexOf("\n")].replace("/", dirSeparator);
									file = file[file.indexOf("\n")+1..$];
									size_t length = to!size_t(file[0..file.indexOf("\n")]);
									file = file[file.indexOf("\n")+1..$];
									string content = file[0..length];
									file = file[length..$];
									if(pname.startsWith(type)) {
										pname = pname[type.length+1..$];
										if(pname.indexOf(dirSeparator) >= 0) {
											mkdirRecurse(path ~ pname.split(dirSeparator)[0..$-1].join(dirSeparator));
										}
										write(path ~ pname, content);
									}
									if(pname == "LICENSE") {
										write(path ~ "license.txt", content);
									}
								}
							}
							saveServerTuples(serverTuples ~ ServerTuple(name, path, type));
						} else {
							writeln("Invalid type \"", type, "\". Choose between \"hub\" and \"node\"");
						}
					} else {
						writeln("Cannot name a server \"", name, "\"");
					}
				} else {
					writeln("A server named \"", name, "\" already exists");
				}
			} else {
				writeln("Use '", launch, " init <server-name> <hub|node> [<path>=", Settings.servers, "<name>] [<version>=latest]'");
			}
			break;
		case "latest":
			//TODO get it from the internet
			writeln("0.8.4");
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
				writeln("Use '", launch, " locate <server-name>'");
			}
			break;
		case "ping":
			if(args.length > 1) {
				string str = launchComponent("ping", args[1..$]);
				if(in_array("-json", args)) {
					writeln(str);
				} else {
					void printping(string type, JSONValue[string] value) {
						writeln(type, " on ", value["address"].str, " (", value["ping"].integer, " ms)");
						writeln("  MOTD: ", value["name"].str.replace("\n", "")[0..min(48, $)].strip); //TODO remove minecraft formatting codes
						writeln("  Players: ", value["online"].integer, "/", value["max"].integer);
						writeln("  Version: unknown (protocol ", value["protocol"].integer, ")"); //TODO print the version after requesting the array with them
					}
					auto json = parseJSON(str);
					if("minecraft" in json) {
						printping("Minecraft", json["minecraft"].object);
					}
					if("pocket" in json) {
						printping("Minecraft: Pocket Edition", json["pocket"].object);
					}
				}
			} else {
				writeln("Use '", launch, " ping <ip>[:<port>]'");
			}
			break;
		case "query":
			if(args.length > 1) {
				string str = launchComponent("query", args[1..$]);
				if(in_array("-json", args)) {
					writeln(str);
				} else {
					void printquery(string type, JSONValue[string] value) {
						writeln(type, " on ", value["address"].str, " (", value["ping"].integer, " ms)");
						writeln("  MOTD: ", value["name"].str);
						writeln("  Players: ", value["online"].integer, "/", value["max"].integer);
						if(value["players"].array.length > 0) {
							//writeln("  List: ", (){ string[] ret;foreach(JSONValue v;value["players"].array){ret~=v.str;}return ret.join(", "); }());
						}
						writeln("  Software: ", value["software"].str);
						if(value["plugins"].array.length > 0) {
							writeln("  Plugins:");
							foreach(JSONValue v ; value["plugins"].array) {
								writeln("    ", v["name"].str, " ", v["version"].str);
							}
						}
					}
					auto json = parseJSON(str);
					if("minecraft" in json) {
						printquery("Minecraft", json["minecraft"].object);
					}
					if("pocket" in json) {
						printquery("Minecraft: Pocket Edition", json["pocket"].object);
					}
				}
			} else {
				writeln("Use '", launch, " query <ip>[:<port>]'");
			}
			break;
		case "rcon":
			writeln("This functionality is not available yet");
			break;
		version(linux) {
			case "shortcut":
			if(args.length > 1) {
				auto server = getServerByName(args[1].toLower);
				if(server.name != "") {
					write(server.location ~ "script.d", "module script;import std.process;import std.string;void main(string[] args){args[0]=\"" ~ server.name ~ "\";wait(spawnShell(\"sel \"~args.join(\" \")));}");
					wait(spawnShell("cd " ~ server.location ~ " && rdmd --build-only -release script.d"));
					remove(server.location ~ "script.d");
					wait(spawnShell("sudo mv " ~ server.location ~ "script /usr/bin/" ~ server.name));
					writeln("You can now use '", server.name, " <command> <options>' as a shortcut for 'sel <command> ", server.name, " <options>'");
				} else {
					writeln("There's no server named \"", args[1].toLower, "\"");
				}
			} else {
				writeln("Use: '", launch, " shortcut <server-name>");
			}
			break;
		}
		case "start":
			if(args.length > 1) {
				auto server = getServerByName(args[1].toLower);
				if(server.name != "") {
					if(server.type == "hub") {
						wait(spawnShell("cd " ~ server.location ~ " && rdmd init.d && java -jar build.jar"));
					} else {
						writeln("Server \"", server.name, "\" is not an hub");
					}
				} else {
					writeln("There's no server named \"", args[1].toLower, "\"");
				}
			} else {
				writeln("Use: '", launch, " start <hub-name> [<port>=28232]'"); //TODO custom port
			}
			break;
		case "uncompress":
			// sel uncompress <archive> <dir>
			immutable output = args[2].endsWith(dirSeparator) ? args[2] : args[2] ~ dirSeparator;
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
			break;
		case "update":
			if(args.length > 1) {
				immutable name = args[1].toLower;
				switch(name) {
					case "*":
					case "all":
						wait(spawnShell("sel update sel"));
						wait(spawnShell("sel update libs"));
						foreach(ServerTuple server ; serverTuples) {
							wait(spawnShell("sel update " ~ server.name));
						}
						break;
					case "sel":
					case "this":
					case "manager":
						// update manager
						// delete components
						foreach(string component ; dirEntries(Settings.config ~ "components", SpanMode.breadth)) {
							if(component.isFile) remove(component);
						}
						break;
					case "lib":
					case "libs":
					case "util":
					case "utils":
						// download and update libraries and utils
						systemDownload(__UTILS__, Settings.config ~ "utils.sa");
						wait(spawnShell("sel uncompress " ~ Settings.config ~ "utils.sa " ~ Settings.config ~ "utils"));
						remove(Settings.config ~ "utils.sa");
						break;
					default:
						// update server
						break;
				}
			} else {
				writeln("Use: '", launch, " update sel|utils|<server-name>|* [<version>=latest]'");
			}
			break;
		case "website":
			writeln(__WEBSITE__);
			break;
		default:
			writeln("'", launch, " ", args.join(" "), "' is not a valid command");
			break;
	}
	
}

void printusage() {
	version(Windows) {
		writeln("SEL Windows Manager v", __MANAGER__);
	} else {
		writeln("SEL Manager v", __MANAGER__);
	}
	writeln("Copyright (c) 2016 SEL");
	writeln();
	writeln("Website: http://selproject.org");
	writeln("Files: " ~ __WEBSITE__);
	writeln("Github: https://github.com/sel-project");
	writeln();
	writeln("Servers path: ", Settings.servers);
	writeln("Managed servers: ", to!string(serverTuples.length));
	writeln("Installed components: ", components.join(", "));
	writeln("Usage:");
	writeln("  sel <command> <server> [<options>]");
	writeln("  sel <server> <command> [<options>]");
	writeln("  sel <command> [<options>]");
	writeln("  sel help <command>");
	writeln();
	writeln("Commands:");
}

bool in_array(T)(T value, T[] array) {
	foreach(T av ; array) {
		if(av == value) return true;
	}
	return false;
}

@property ServerTuple[] serverTuples() {
	ServerTuple[] ret;
	if(exists(Settings.config ~ "sel.conf")) {
		foreach(string s ; (cast(string)read(Settings.config ~ "sel.conf")).split(__NEW_LINE__)) {
			string[] spl = s.split(",");
			if(spl.length == 3) {
				ret ~= ServerTuple(cast(string)Base64.decode(spl[0]), spl[1], spl[2]);
			}
		}
	}
	return ret;
}

@property bool nameExists(string name) {
	foreach(ServerTuple server ; serverTuples) {
		if(server.name == name) return true;
	}
	return false;
}

@property ServerTuple getServerByName(string name) {
	foreach(ServerTuple server ; serverTuples) {
		if(server.name == name) return server;
	}
	return ServerTuple.init;
}

void saveServerTuples(ServerTuple[] servers) {
	mkdirRecurse(Settings.config);
	string file = "# SEL MANAGER CONFIGURATION FILE" ~ __NEW_LINE__;
	foreach(ServerTuple server ; servers) {
		file ~= Base64.encode(cast(ubyte[])server[0]) ~ "," ~ server[1] ~ "," ~ server[2] ~ __NEW_LINE__;
	}
	write(Settings.config ~ "sel.conf", file);
}

bool hasCommand(string cmd) {
	version(Windows) {
		return !executeShell(cmd).output.startsWith("'" ~ cmd ~ "'");
	} else {
		return !executeShell(cmd).output.startsWith(cmd ~ ":");
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

string launchComponent(bool spawn=false)(string component, string[] args) {
	if(!exists(Settings.config ~ "components")) mkdirRecurse(Settings.config ~ "components");
	version(Windows) {
		immutable ext = ".exe";
		immutable runnable = component ~ ".exe";
	} else {
		immutable ext = "";
		immutable runnable = "./" ~ component;
	}
	if(!exists(Settings.config ~ "components" ~ dirSeparator ~ component ~ ext)) {
		systemDownload(__COMPONENTS__ ~ component ~ ".d", Settings.config ~ "components" ~ dirSeparator ~ component ~ ".d");
		wait(spawnShell("cd " ~ Settings.config ~ "components && rdmd --build-only " ~ component ~ ".d"));
		remove(Settings.config ~ "components" ~ dirSeparator ~ component ~ ".d");
	}
	immutable cmd = "cd " ~ Settings.config ~ "components && " ~ runnable ~ " " ~ args.join(" ").replace("\"", "\\\"");
	static if(spawn) {
		wait(spawnShell(cmd));
		return "";
	} else {
		return executeShell(cmd).output.strip;
	}
}

void systemDownload(string file, string dest) {
	version(Windows) {
		wait(spawnShell("bitsadmin /transfer \"SEL Manager Download\" " ~ file ~ " " ~ dest));
	} else {
		wait(spawnShell("wget " ~ file ~ " -O " ~ dest));
	}
}



/*

structure of sel (zipped source code)

	hub/{hub_files}
	node/{node_files}
	README.md
	LICENSE
	install.bat
	install.sh


structure of an hub (java)

	build.jar				runnable jar file (if compiled)
	init.d					initialization for the settings
	sel/../*.java			source code
	sel/res/				default resources
	lib/*.jar				libraries
	resources/sel.txt		settings
	resources/whitelist.txt	whitelisted players
	resources/blacklist.txt	banned players
	resources/index.html	html homepage


structure of a node (d)

	main(.exe)				runnable file (if compiled)
	init.d					initialization for the plugins
	main.d					file with main function
	sel/../*.d				source code
	sel/res					default resources
	resources/plugins.txt	plugins activation
	resources/{plugin}		plugin's resources
	plugins/				plugins' source code
	{xamarin files}

*/
