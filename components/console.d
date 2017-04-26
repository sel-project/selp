/+ dub.sdl:
	name "console"
	description "External Console command-line application"
	authors "Kripth"
	license "GPL-3.0"
	dependency "sel-utils" version="~>1.1.82"
	stringImportPaths "."
+/
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
import std.bitmanip : read, nativeToLittleEndian;
import std.conv : to, ConvException;
import std.datetime : StopWatch;
import std.digest.md;
import std.digest.sha;
import std.process : wait, spawnShell, executeShell;
import std.regex : replaceAll, ctRegex;
import std.socket;
import std.stdio : write, writeln, readln;
import std.string;
import std.system : Endian;
import std.typecons : Tuple;

static if(__traits(compiles, import("version.txt"))) {
	
	enum __protocol = to!int(strip(import("version.txt")));
	
} else {
	
	enum __protocol = 2;
	
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
	
	void error(string message) {
		writeln(message);
		//socket.close();
		exit(0);
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
		static if(__protocol >= 2) data = nativeToLittleEndian(cast(ushort)data.length) ~ data;
		return socket.send(data) != Socket.ERROR;
	}
	
	ubyte[] receiveImpl() {
		auto recv = socket.receive(buffer);
		if(recv <= 0) error("Connection closed: " ~ lastSocketError);
		return buffer[0..recv];
	}
	
	ubyte[] receive() {
		static if(__protocol >= 2) {
			ubyte[] data = receiveImpl();
			if(data.length <= 2) error("Received too small packet");
			immutable length = read!(ushort, Endian.littleEndian)(data);
			while(data.length < length) {
				data ~= receiveImpl();
			}
			return data[0..length];
		} else {
			return receiveImpl();
		}
	}

	// wait for auth credentials
	auto data = receive();
	if(data[0] != Login.AuthCredentials.ID) {
		error("Wrong packet received. Maybe the wrong protocol is used?");
	}
	auto credentials = Login.AuthCredentials.fromBuffer(data);
	if(credentials.protocol != __protocol) {
		error("Incompaticle protocols: " ~ to!string(credentials.protocol) ~ " is required");
	} else if(!credentials.hash && !["sha1", "sha224", "sha256", "sha384", "sha512", "md5"].canFind(credentials.hashAlgorithm)) {
		error("The server requires an unknown hash algorithm: " ~ credentials.hashAlgorithm);
	}

	new Thread({
		write("Password required: ");
		char[] password = readln().strip.dup;
		ubyte[] payload = cast(ubyte[])password.idup ~ credentials.payload;
		password[] = '*';
		version(Posix) {
			// replaces the password in the console stdout with asteriks
			wait(spawnShell("tput cuu 1 && tput el"));
			writeln("Password Required: ", password);
		}
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
	}).start();

	string[] nodes;
	
	data = receive();
	if(data[0] != Login.Welcome.ID) {
		error("Wrong packet received, expecting " ~ to!string(Login.Welcome.ID) ~ " but got " ~ to!string(data[0]) ~ " instead");
	}
	bool cmd;
	string name;
	auto welcome = Login.Welcome.fromBuffer(data);
	if(welcome.status == Login.Welcome.Accepted.STATUS) {
		auto info = welcome.new Accepted();
		info.decode();
		with(info) {
			nodes = info.connectedNodes;
			writeln("Connected to ", address);
			writeln("Software: ", software, " v", versions[0], ".", versions[1], ".", versions[2]);
			writeln("Name: ", (name = displayName));
			writeln("Remote commands: ", (cmd = remoteCommands));
			foreach(game ; games) {
				string n = (){
					switch(game.type) {
						case Types.Game.POCKET: return "Pocket";
						case Types.Game.MINECRAFT: return "Minecraft";
						default: return "Unknown";
					}
				}();
				writeln(n, " protocols: ", game.protocols);
			}
			writeln("Connected nodes: ", nodes.join(", "));
		}
	} else if(welcome.status == Login.Welcome.WrongHash.STATUS) {
		error("Wrong password");
	} else if(welcome.status == Login.Welcome.TimedOut.STATUS) {
		error("\nTimed out");
		//TODO a thread isn't killed because is waiting a console input
	} else {
		error("Unknown error");
	}

	ulong ping;

	void updateTitle() {
		version(Windows) {
			executeShell("title " ~ name ~ " ^| External Console ^| " ~ to!string(ping) ~ " ms");
		}
	}

	updateTitle();
	
	StopWatch timer;
	uint expected_count;

	new Thread({
		uint count = 0;
		while(true) {
			Thread.sleep(dur!"seconds"(5));
			send(new Status.KeepAlive(++count).encode());
			expected_count = count;
			timer.stop();
			timer.reset();
			timer.start();
		}
	}).start();

	if(cmd) {
		new Thread({
			while(true) {
				string command = readln().strip;
				if(command.length) {
					send(new Connected.Command(command).encode());
				}
			}
		}).start();
	}

	while(true) {

		data = receive();

		switch(data[0]) {
			case Status.KeepAlive.ID:
				auto ka = Status.KeepAlive.fromBuffer(data);
				if(ka.count == expected_count) {
					ping = timer.peek.msecs;
					updateTitle();
				}
				break;
			case Connected.ConsoleMessage.ID:
				auto cm = Connected.ConsoleMessage.fromBuffer(data);
				writeln(replaceAll("[" ~ cm.node ~ "][" ~ cm.logger ~ "] " ~ cm.message, ctRegex!"§[a-fA-F0-9k-or]", ""));
				break;
			case Connected.PermissionDenied.ID:
				writeln("Permission denied");
				break;
			case Status.UpdateStats.ID:
				//writeln(UpdateStats.staticDecode(data));
				break;
			case Status.UpdateNodes.ID:
				auto un = Status.UpdateNodes.fromBuffer(data);
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
