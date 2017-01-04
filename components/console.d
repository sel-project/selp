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
import std.process : wait, spawnShell;
import std.socket;
import std.stdio : write, writeln, readln;
import std.string;
import std.typecons : Tuple;

static if(__traits(compiles, import("version.txt"))) {
	
	enum __protocol = to!int(strip(import("version.txt")));
	
} else {
	
	enum __protocol = 1;
	
}

mixin("import sul.constants.externalconsole" ~ __protocol.to!string ~ " : Constants;");

mixin("import sul.protocol.externalconsole" ~ __protocol.to!string ~ " : Packets;");

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
	} else if(buffer[0] != Packets.Login.AuthCredentials.packetId) {
		error("Wrong packet received. Maybe the wrong protocol is used?");
	}
	auto credentials = Packets.Login.AuthCredentials().decode(buffer);
	if(credentials.protocol != __protocol) {
		error("Incompaticle protocols: " ~ to!string(credentials.protocol) ~ " is required");
	} else if(!["", "sha1", "sha224", "sha256", "sha384", "sha512", "md5"].canFind(credentials.hashAlgorithm)) {
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
		send(Packets.Login.Auth(hash).encode());
		password[] = '*';
		version(Windows) {
			//TODO is it even possible?
		} else {
			// replaced the password in the console stdout with asteriks
			wait(spawnShell("tput cuu 1 && tput el"));
			writeln("Password Required: ", password);
		}
	}).start();

	string[] nodes;
	
	recv = socket.receive(buffer);
	if(recv <= 0) {
		error("Connection error");
	}
	if(buffer[0] != Packets.Login.Welcome.packetId) {
		error("Wrong packet received");
	}
	auto welcome = Packets.Login.Welcome().decode(buffer);
	if(welcome.status == Packets.Login.Welcome.Accepted.status) {
		auto info = Packets.Login.Welcome.Accepted().decode(buffer);
		with(info) {
			nodes = info.connectedNodes;
			writeln("Connected to ", address);
			writeln("Software: ", software, " v", versions[0], ".", versions[1], ".", versions[2]);
			writeln("Remote commands: ", remoteCommands);
			if(pocketProtocols) writeln("Pocket protocols: ", pocketProtocols);
			if(minecraftProtocols) writeln("Minecraft Protocols: ", minecraftProtocols);
			writeln("Connected nodes: ", nodes);
		}
	} else if(welcome.status == Packets.Login.Welcome.WrongHash.status) {
		error("Wrong password");
	} else if(welcome.status == Packets.Login.Welcome.TimedOut.status) {
		error("\nTimed out");
		//TODO a thread isn't killed because is waiting a console input
	} else {
		error("Unknown error");
	}

	ulong ping, ping_time;

	new Thread({
		uint count = 0;
		while(true) {
			Thread.sleep(dur!"seconds"(5));
			send(Packets.Status.KeepAlive(count++).encode());
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
						send(Packets.Play.Command(message).encode());
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
			case Packets.Status.KeepAlive.packetId:
				ping = peek - ping_time;
				break;
			case Packets.Play.ConsoleMessage.packetId:
				auto cm = Packets.Play.ConsoleMessage().decode(buffer);
				writeln("[", cm.node, "][", cm.logger, "] ", cm.message);
				break;
			case Packets.Play.PermissionDenied.packetId:
				writeln("Permission denied");
				break;
			case Packets.Status.UpdateStats.packetId:
				//writeln(UpdateStats.staticDecode(buffer));
				break;
			case Packets.Status.UpdateNodes.packetId:
				auto un = Packets.Status.UpdateNodes().decode(buffer);
				if(un.action == Constants.UpdateNodes.action.add) {
					nodes ~= un.node;
				} else {
					remove(nodes, un.node);
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
