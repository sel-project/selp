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
module rcon;

import core.thread;

import std.bitmanip : write;
import std.conv : to;
import std.random : uniform;
import std.socket;
import std.stdio : writeln, readln;
import std.string;
import std.system : Endian;

void main(string[] args) {

	string ip = args.length > 1 ? args[1] : "127.0.0.1";
	ushort port = 25575;
	if(ip.lastIndexOf(":") > ip.lastIndexOf("]")) {
		port = to!ushort(ip[ip.lastIndexOf(":")+1..$]);
		ip = ip[0..ip.lastIndexOf(":")];
	}
	ip = ip.replace("[", "").replace("]", "");

	string password = args.length > 2 ? args[2] : "";

	Address address = parseAddress(ip, port);
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
					writeln("<", address, "> ", cast(string)buffer[12..recv-2]);
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
