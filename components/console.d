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
import std.base64 : Base64;
import std.conv : to, ConvException;
import std.datetime : Clock, UTC;
import std.digest.sha : sha1Of;
import std.process : wait, spawnShell;
import std.socket;
import std.stdio : write, writeln, readln;
import std.string;
import std.typecons : Tuple;

import sul.constants : SulConstants = Constants;
import sul.protocol : SulProtocol = Protocol, SoftwareType;

void main(string[] args) {

	bool write_perm = false;
	foreach(i, string arg; args) {
		if(arg.startsWith("-commands=")) {
			if(arg == "-commands=true") {
				write_perm = true;
			}
			args = args[0..i] ~ args[i+1..$];
		}
	}
	
	string ip = args.length > 1 ? args[1] : "127.0.0.1";
	ushort port = 19134;
	if(ip.lastIndexOf(":") > ip.lastIndexOf("]")) {
		port = to!ushort(ip[ip.lastIndexOf(":")+1..$]);
		ip = ip[0..ip.lastIndexOf(":")];
	}
	Address address;
	try {	
		address = parseAddress(ip, port);
	} catch(SocketException) {
		address = getAddressInfo(ip.replace("[", "").replace("]", ""), to!string(port))[0].address;
	}

	Socket socket = new TcpSocket(address.addressFamily);
	socket.blocking = true;
	socket.connect(address);

	bool send(ubyte[] data) {
		return socket.send(cast(ubyte[])[data.length & 255, (data.length >> 8) & 255] ~ data) != Socket.ERROR;
	}

	ubyte[] cred_buffer = new ubyte[19];
	// wait for auth credentials
	if(socket.receive(cred_buffer) != 19) return;
	auto payload = Protocol.Login.AuthCredentials().decode(cred_buffer[2..$]).payload;

	write("Password required: ");
	char[] password = readln().strip.dup;
	send(Protocol.Login.Auth(sha1Of(to!string(protocol) ~ Base64.encode(cast(ubyte[])password) ~ Base64.encode(payload)), write_perm).encode());
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
			send(Protocol.Status.Ping(count++).encode()); // that shouldn't even work...
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
						send(Protocol.Play.Command(message).encode());
						break;
				}
			}
		}
	}).start();

	ubyte[] socket_buffer = new ubyte[2 ^^ 16];

	while(true) {

		ptrdiff_t recv = socket.receive(socket_buffer);
		if(recv < 2) {
			writeln("Disconnected");
			exit(0);
		}

		ubyte[] buffer = socket_buffer[0..recv];
		size_t length = buffer[0] | buffer[1] << 8;
		if(length > buffer.length + 2) continue;
		buffer = buffer[2..length+2];

		switch(buffer[0]) {
			case Protocol.Login.Welcome.packetId:
				auto welcome = Protocol.Login.Welcome().decode(buffer);
				if(welcome.accepted) {
					nodes = welcome.connectedNodes;
					writeln("Connected to ", address);
					writeln("Software: ", welcome.software, " v", welcome.vers);
					writeln("API: ", welcome.api);
					writeln("Connected nodes: ", nodes);
				} else {
					writeln("Wrong password");
					exit(0);
				}
				break;
			case Protocol.Status.Pong.packetId:
				ping = peek - ping_time;
				break;
			case Protocol.Play.ConsoleMessage.packetId:
				auto cm = Protocol.Play.ConsoleMessage().decode(buffer);
				writeln("[", cm.node, "][", cm.logger, "] ", cm.message);
				break;
			case Protocol.Play.PermissionDenied.packetId:
				writeln("Permission denied");
				break;
			case Protocol.Play.UpdateStats.packetId:
				//writeln(UpdateStats.staticDecode(buffer));
				break;
			case Protocol.Play.UpdateNodes.packetId:
				auto un = Protocol.Play.UpdateNodes().decode(buffer);
				if(un.action == Constants.UpdateNodes.action.add) {
					nodes ~= un.nodeName;
				} else {
					remove(nodes, un.nodeName);
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

static if(__traits(compiles, import("version.txt"))) {

	enum uint protocol = import("version.txt");

} else {

	enum uint protocol = 2;

}

alias Protocol = SulProtocol!("externalconsole", protocol, SoftwareType.client);

alias Constants = SulConstants!("externalconsole", protocol);
