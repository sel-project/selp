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
module console;

import core.stdc.stdlib : exit;
import core.thread;

static import std.bitmanip;
import std.algorithm : remove, canFind;
import std.base64 : Base64;
import std.conv : to, ConvException;
import std.datetime : Clock, UTC;
import std.digest.md;
import std.digest.sha;
import std.process : wait, spawnShell, executeShell;
import std.socket;
import std.stdio : write, writeln, readln;
import std.string;
import std.typecons : Tuple;

static if(__traits(compiles, import("version.txt"))) {
	
	enum __protocol = to!int(strip(import("version.txt")));
	
} else {
	
	enum __protocol = 1;
	
}

mixin("import Types = sul.protocol.externalconsole" ~ __protocol.to!string ~ ".types;");
mixin("import Login = sul.protocol.externalconsole" ~ __protocol.to!string ~ ".login;");
mixin("import Status = sul.protocol.externalconsole" ~ __protocol.to!string ~ ".status;");
mixin("import Connected = sul.protocol.externalconsole" ~ __protocol.to!string ~ ".connected;");

void main(string[] args) {
	
	bool has_port = args[1].lastIndexOf(":") > args[1].lastIndexOf("]");
	string ip = args[1].replace("[", "").replace("]", "");
	ushort port = 19134;
	if(has_port) {
		string[] spl = ip.split(":");
		ip = spl[0..$-1].join(":");
		port = to!ushort(spl[$-1]);
	}
	Address address;
	try {
		address = getAddress(ip, port)[0];
	} catch(SocketException e) {
		writeln("Address cannot be resolved: ", e.msg);
		return;
	}

	ubyte[] buffer = new ubyte[2048];
	ptrdiff_t recv;

	Socket socket = new TcpSocket(address.addressFamily);
	socket.blocking = true;
	try {
		socket.connect(address);
	} catch(SocketException e) {
		writeln(e.msg);
		return;
	}
	socket.send("classic");

	bool send(ubyte[] data) {
		return socket.send(data) != Socket.ERROR;
	}
	
	void error(string message) {
		writeln(message);
		socket.close();
		exit(0);
	}

	// wait for auth credentials
	recv = socket.receive(buffer);
	if(recv == Socket.ERROR) {
		error("Cannot connect: " ~ lastSocketError);
	} else if(recv == 0) {
		error("Connection closed by server");
	} else if(buffer[0] != Login.AuthCredentials.ID) {
		error("Wrong packet received. Maybe the wrong protocol is used?");
	}
	auto credentials = Login.AuthCredentials.fromBuffer(buffer);
	if(credentials.protocol != __protocol) {
		error("Incompaticle protocols: " ~ to!string(credentials.protocol) ~ " is required");
	} else if(!credentials.hash && !["sha1", "sha224", "sha256", "sha384", "sha512", "md5"].canFind(credentials.hashAlgorithm)) {
		error("The server requires an unknown hash algorithm: " ~ credentials.hashAlgorithm);
	}

	new Thread({
		write("Password required: ");
		char[] password = readln().strip.dup;
		ubyte[] payload = cast(ubyte[])password.idup ~ credentials.payload;
		ubyte[] hash = (){
			switch(credentials.hashAlgorithm) {
				case "sha1":
					return sha1Of(payload).dup;
				case "sha224":
					return sha224Of(payload).dup;
				case "sha256":
					return sha256Of(payload).dup;
				case "sha384":
					return sha384Of(payload).dup;
				case "sha512":
					return sha512Of(payload).dup;
				case "md5":
					return md5Of(payload).dup;
				default:
					return cast(ubyte[])password.idup;
			}
		}();
		send(new Login.Auth(hash).encode());
		password[] = '*';
		version(Posix) {
			// replaces the password in the console stdout with asteriks
			wait(spawnShell("tput cuu 1 && tput el"));
			writeln("Password Required: ", password);
		}
	}).start();

	string[] nodes;
	
	recv = socket.receive(buffer);
	if(recv <= 0) {
		error("Connection error");
	}
	if(buffer[0] != Login.Welcome.ID) {
		error("Wrong packet received");
	}
	bool cmd;
	auto welcome = Login.Welcome.fromBuffer(buffer);
	if(welcome.status == Login.Welcome.Accepted.STATUS) {
		auto info = welcome.new Accepted();
		info.decode();
		with(info) {
			nodes = info.connectedNodes;
			writeln("Connected to ", address);
			writeln("Software: ", software, " v", versions[0], ".", versions[1], ".", versions[2]);
			writeln("Name: ", displayName);
			writeln("Remote commands: ", (cmd = remoteCommands));
			foreach(game ; games) {
				string name = (){
					switch(game.type) {
						case Types.Game.POCKET: return "Pocket";
						case Types.Game.MINECRAFT: return "Minecraft";
						default: return "Unknown";
					}
				}();
				writeln(name, " protocols: ", game.protocols);
			}
			writeln("Connected nodes: ", nodes.join(", "));
			version(Windows) {
				executeShell("title " ~ displayName.replace("|", "^|") ~ " ^| External Console");
			}
		}
	} else if(welcome.status == Login.Welcome.WrongHash.STATUS) {
		error("Wrong password");
	} else if(welcome.status == Login.Welcome.TimedOut.STATUS) {
		error("\nTimed out");
		//TODO a thread isn't killed because is waiting a console input
	} else {
		error("Unknown error");
	}

	immutable remoteCommands = cmd;

	ulong ping, ping_time;

	new Thread({
		uint count = 0;
		while(true) {
			Thread.sleep(dur!"seconds"(5));
			send(new Status.KeepAlive(count++).encode());
			ping_time = peek;
		}
	}).start();

	new Thread({
		while(true) {
			string message = readln().strip;
			if(message != "") {
				switch(message.toLower) {
					case "ping":
						writeln("Ping: ", ping, " ms");
						break;
					case "clear":
						version(Windows) {
							immutable cmd = "cls";
						} else {
							immutable cmd = "clear";
						}
						wait(spawnShell(cmd));
						break;
					case "nodes":
						writeln("Connected nodes: ", nodes.join(", "));
						break;
					default:
						if(remoteCommands) {
							send(new Connected.Command(message).encode());
						} else {
							writeln("The server doesn't allow remote commands");
						}
						break;
				}
			}
		}
	}).start();

	while(true) {

		recv = socket.receive(buffer);
		if(recv == Socket.ERROR) {
			error("Connection error: " ~ lastSocketError);
		} else if(recv == 0) {
			error("Disconnected from server");
		}

		switch(buffer[0]) {
			case Status.KeepAlive.ID:
				ping = peek - ping_time;
				break;
			case Connected.ConsoleMessage.ID:
				auto cm = Connected.ConsoleMessage.fromBuffer(buffer);
				writeln("[", cm.node, "][", cm.logger, "] ", cm.message);
				break;
			case Connected.PermissionDenied.ID:
				writeln("Permission denied");
				break;
			case Status.UpdateStats.ID:
				//writeln(UpdateStats.staticDecode(buffer));
				break;
			case Status.UpdateNodes.ID:
				auto un = Status.UpdateNodes.fromBuffer(buffer);
				final switch(un.action) {
					case Status.UpdateNodes.ADD:
						nodes ~= un.node;
						break;
					case Status.UpdateNodes.REMOVE:
						remove(nodes, un.node);
						break;
				}
				break;
			default:
				break;
		}

	}

}

@property ulong peek() {
	auto t = Clock.currTime(UTC());
	return t.toUnixTime!long * 1000 + t.fracSecs.total!"msecs";
}
