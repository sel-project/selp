/+ dub.sdl:
	name "rcon"
	description "RCON (remote console) command-line application"
	authors "Kripth"
	license "GPL-3.0"
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
module rcon;

import core.thread;

import std.bitmanip : write;
import std.conv : to;
import std.random : uniform;
import std.regex : replaceAll, ctRegex;
import std.socket;
import std.stdio : writeln, readln;
import std.string;
import std.system : Endian;

void main(string[] args) {

	bool has_port = args[1].lastIndexOf(":") > args[1].lastIndexOf("]");
	string ip = args[1].replace("[", "").replace("]", "");
	ushort port = 25575;
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

	string password = args.length > 2 ? args[2] : "";

	ubyte[] buffer = new ubyte[1446];
	ptrdiff_t recv;

	Socket socket = new TcpSocket(address.addressFamily);
	socket.blocking = true;
	socket.connect(address);
	socket.send(createPacket(3, password));
	recv = socket.receive(buffer);
	if(recv >= 14) {
		if(buffer[8] == 2) {
			writeln("Connected to ", address);
			new Thread({
				while(true) {
					string command = readln().strip;
					if(command.length) {
						socket.send(createPacket(2, command));
					}
				}
			}).start();
			while(true) {
				recv = socket.receive(buffer);
				if(recv <= 0) {
					writeln("Disconnected from server");
					import std.c.stdlib : exit;
					exit(0);
				}
				if(recv >= 14 && buffer[8] == 0) {
					writeln("<", address, "> ", replaceAll(cast(string)buffer[12..recv-2], ctRegex!"§[a-fA-F0-9k-or]", ""));
				}
			}
		} else {
			writeln("Wrong password");
		}
	} else {
		writeln("Server replied with an unexpected message of ", recv, " bytes");
	}

}

void[] createPacket(int id, const(void)[] payload) {
	ubyte[] length = new ubyte[4];
	ubyte[] p_id = new ubyte[4];
	write!(uint, Endian.littleEndian)(length, payload.length.to!uint + 10, 0);
	write!(int, Endian.littleEndian)(p_id, id, 0);
	return length ~ randomBytes ~ p_id ~ payload ~ cast(ubyte[])[0, 0];
}

@property ubyte[] randomBytes() {
	return [uniform!ubyte, uniform!ubyte, uniform!ubyte, uniform!ubyte];
}
