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
module social;

import std.conv : to;
import std.datetime : dur;
import std.socket;
import std.stdio : write;
import std.string;

void main(string[] args) {

	bool has_port = args[1].lastIndexOf(":") > args[1].lastIndexOf("]");
	string ip = args[1].replace("[", "").replace("]", "");
	ushort port = 0;
	if(has_port) {
		string[] spl = ip.split(":");
		ip = spl[0..$-1].join(":");
		port = to!ushort(spl[$-1]);
	}
	try {
		auto address = getAddress(ip, port)[0];
	} catch(SocketException e) {
		write("{\"error\":\"", e.msg, "\"}");
		return;
	}

	Address tcp = getAddress(ip, port == 0 ? 25565 : port)[0];
	Address udp = getAddress(ip, port == 0 ? 19132 : port)[0];
	Socket socket;
	char[] buffer = new char[1024];
	ptrdiff_t recv;

	try {
		// try tcp (port | 25565)
		socket = new TcpSocket(tcp);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"seconds"(1));
		socket.send(cast(ubyte[])[253]);
		recv = socket.receive(buffer);
		if(recv > 0) {
			write(buffer[0..recv]);
			return;
		}
		socket.close();
	} catch(SocketException) {}

	try {
		// try udp (port | 19132)
		socket = new UdpSocket();
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"seconds"(1));
		socket.sendTo(cast(ubyte[])[253], udp);
		recv = socket.receiveFrom(buffer, udp);
		if(recv > 0) {
			write(buffer[0..recv]);
			return;
		}
		socket.close();
	} catch(SocketException) {}

	// fail
	write("{}");

}
