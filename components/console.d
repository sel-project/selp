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
import std.algorithm : remove;
import std.base64 : Base64, Base64URL;
import std.conv : to, ConvException;
import std.datetime : Clock, UTC;
import std.digest.sha : sha1Of;
import std.process : wait, spawnShell;
import std.socket;
import std.stdio : write, writeln, readln;
import std.string;
import std.typecons : Tuple;

void main(string[] args) {

	string[] ipport = (args.length > 1 ? args[1] : "127.0.0.1").split(":");
	string ip = ipport[0];
	ushort port = ipport.length == 2 ? to!ushort(ipport[1]) : 19134;

	bool write_perm = false;
	foreach(string arg ; args) {
		if(arg == "-commands=true") {
			write_perm = true;
			break;
		}
	}

	try {
		ip = getAddress(ip)[0].toAddrString();
	} catch(SocketException) {}

	TcpSocket socket = new TcpSocket();
	socket.blocking = true;
	socket.connect(new InternetAddress(InternetAddress.parse(ip), port));

	bool send(ubyte[] data) {
		return socket.send(cast(ubyte[])[data.length & 255, (data.length >> 8) & 255] ~ data) != Socket.ERROR;
	}

	write("Password required: ");
	char[] password = readln().strip.dup;
	send(Auth(Base64URL.encode(sha1Of(Base64.encode(cast(ubyte[])password))).idup, write_perm).encode());
	password[] = '*';
	version(Windows) {
		//TODO is it even possible?
	} else {
		// replaced the password in the console stdout with asteriks
		wait(spawnShell("tput cuu 1 && tput el"));
		writeln("Password Required: ", password);
	}

	ulong ping, ping_time;
	string[] nodes;

	new Thread({
		size_t count = 0;
		while(true) {
			Thread.sleep(dur!"seconds"(5));
			send(Ping(count++).encode()); // that shouldn't even work...
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
						send(Command(message).encode());
						break;
				}
			}
		}
	}).start();

	ubyte[] socket_buffer = new ubyte[2 ^^ 16];

	while(true) {

		ptrdiff_t recv = socket.receive(socket_buffer);
		if(recv < 2) break;

		ubyte[] buffer = socket_buffer[0..recv];
		size_t length = buffer[0] | buffer[1] << 8;
		if(length > buffer.length + 2) continue;
		buffer = buffer[2..length+2];

		switch(buffer[0]) {
			case Welcome.ID:
				auto welcome = Welcome.staticDecode(buffer);
				if(welcome.accepted) {
					nodes = welcome.nodes;
					writeln("Connected to ", ip, ":", port);
					writeln("Software: ", welcome.sel, " v", welcome.vers);
					writeln("API: ", welcome.api);
					writeln("Connected nodes: ", nodes);
				} else {
					writeln("Wrong password");
					exit(0);
				}
				break;
			case Pong.ID:
				ping = peek - ping_time;
				break;
			case ConsoleMessage.ID:
				auto cm = ConsoleMessage.staticDecode(buffer);
				writeln("[", cm.node, "][", cm.logger, "] ", cm.message);
				break;
			case PermissionDenied.ID:
				writeln("Permission denied");
				break;
			case UpdateStats.ID:
				//writeln(UpdateStats.staticDecode(buffer));
				break;
			case UpdateNodes.ID:
				auto un = UpdateNodes.staticDecode(buffer);
				if(un.add) {
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

struct Packet(ubyte id, E...) {

	public static immutable ubyte ID = id;

	public Tuple!E tuple;

	public this(F...)(F args) {
		this.tuple = Tuple!E(args);
	}

	public ubyte[] encode() {
		ubyte[] buffer;
		write(id, buffer);
		foreach(size_t i, F; E) {
			static if(i % 2 == 0) {
				mixin("write(this." ~ E[i+1] ~ ", buffer);");
			}
		}
		return buffer;
	}

	public void decode(ubyte[] buffer) {
		read!ubyte(buffer);
		foreach(size_t i, F; E) {
			static if(i % 2 == 0) {
				mixin("this." ~ E[i+1] ~ " = read!(E[" ~ to!string(i) ~ "])(buffer);");
			}
		}
	}

	alias tuple this;

	public static typeof(this) staticDecode(ubyte[] buffer) {
		typeof(this) packet;
		packet.decode(buffer);
		return packet;
	}

}

public static void write(T)(T value, ref ubyte[] buffer) {
	static if(is(T == string[])) {
		write!uint(value.length.to!uint, buffer);
		foreach(string s ; value) {
			write!string(s, buffer);
		}
	} else static if(is(T == string)) {
		write!uint(value.length.to!uint, buffer);
		foreach(char c ; value) {
			write!ubyte(c, buffer);
		}
	} else {
		size_t index = buffer.length;
		buffer.length = buffer.length + T.sizeof;
		return std.bitmanip.write!T(buffer, value, &index);
	}
}

public static T read(T)(ref ubyte[] buffer) {
	static if(is(T == string[])) {
		string[] ret = new string[read!uint(buffer)];
		foreach(size_t i ; 0..ret.length) {
			ret[i] = read!string(buffer);
		}
		return ret;
	} else static if(is(T == string)) {
		char[] ret = new char[read!uint(buffer)];
		foreach(size_t i ; 0..ret.length) {
			ret[i] = read!ubyte(buffer);
		}
		return ret.idup;
	} else {
		if(buffer.length < T.sizeof) buffer.length = T.sizeof;
		T ret = std.bitmanip.read!T(buffer);
		return ret;
	}
}

alias Auth = Packet!(1, string, "password", bool, "write_perm");

alias Welcome = Packet!(1, bool, "accepted", string, "sel", string, "vers", uint, "api", string[], "nodes");

alias Ping = Packet!(2, ulong, "ping");

alias Pong = Packet!(2, ulong, "pong");

alias ConsoleMessage = Packet!(3, string, "node", ulong, "time", string, "logger", string, "message");

alias Command = Packet!(4, string, "command");

alias PermissionDenied = Packet!(4);

alias UpdateStats = Packet!(5, string, "name", uint, "online", uint, "max", uint, "uptime", float, "tps", uint, "upload", uint, "download", ulong, "memory", float, "cpu");

alias UpdateNodes = Packet!(6, bool, "add", string, "node");
