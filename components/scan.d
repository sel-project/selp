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
module scan;

import core.atomic : atomicOp;
import core.thread : Thread;

import std.algorithm : canFind;
import std.bitmanip : nativeToBigEndian, bigEndianToNative;
import std.conv : to, ConvException;
import std.datetime : StopWatch, AutoStart, dur;
import std.json;
import std.socket;
import std.stdio : write, writeln;
import std.string;

enum ubyte[16] magic = [0x00, 0xFF, 0xFF, 0x00, 0xFE, 0xFE, 0xFE, 0xFE, 0xFD, 0xFD, 0xFD, 0xFD, 0x12, 0x34, 0x56, 0x78];

void main(string[] args) {

	try {
		getAddress(args[1], 0);
	} catch(Throwable t) {
		write(JSONValue(["error": t.msg]).toString());
		return;
	}

	// check options
	bool pc = args.canFind("-pc") || args.canFind("-minecraft") || args.canFind("-mc");
	bool pe = args.canFind("-pe") || args.canFind("-pocket") || args.canFind("-mcpe");

	ushort scan_from = 1;
	ushort scan_to = 65535;

	size_t retry = 3;

	foreach(arg ; args) {
		if(arg.startsWith("-from=")) scan_from = to!ushort(arg[6..$]);
		if(arg.startsWith("-to=")) scan_to = to!ushort(arg[4..$]);
		if(arg.startsWith("-retry=")) retry = to!size_t(arg[7..$]);
	}
	
	JSONValue[string] json;

	shared size_t sent, recv;

	if(pc) json["minecraft"] = scanMinecraft(args[1], scan_from, scan_to, sent, recv);
	if(pe) json["pocket"] = scanPocket(args[1], scan_from, scan_to, retry, sent, recv);

	if(!pc && !pe) json["error"] = "no game selected";

	json["sent"] = sent;
	json["recv"] = recv;
	
	write(JSONValue(json).toString());
	
}

JSONValue[] scanMinecraft(string ip, ushort scan_from, ushort scan_to, ref shared size_t total_sent, ref shared size_t total_recv) {
	JSONValue[] ret;
	Socket[] sockets;
	foreach(ushort port ; scan_from..scan_to+1) {
		auto address = getAddress(ip, port)[0];
		Socket socket = new TcpSocket(address.addressFamily);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		socket.blocking = false;
		socket.connect(address);
		socket.send(cast(ubyte[])[ip.length + 6, 0, 0, ip.length] ~ cast(ubyte[])ip ~ nativeToBigEndian(port) ~ 1);
		socket.send(cast(ubyte[])[1, 0]);
		atomicOp!"+="(total_sent, ip.length + 9);
		sockets ~= socket;
	}
	ubyte[][ushort] data;
	auto timer = StopWatch(AutoStart.yes);
	while(timer.peek.seconds < 8 && sockets.length) {
		for(size_t i=0; i<sockets.length; i++) {
			auto socket = sockets[i];
			ubyte[] buffer = new ubyte[512];
			auto recv = socket.receive(buffer);
			if(recv > 0) {
				atomicOp!"+="(total_recv, recv);
				data[socket.remoteAddress.toPortString().to!ushort] ~= buffer[0..recv].dup;
			} else if(recv == 0) {
				sockets = sockets[0..i] ~ sockets[i+1..$];
			}
		}
	}
	writeln(data);
	foreach(ushort port, payload; data) {
		if(readVarint(payload) == payload.length && readVarint(payload) == 0 && readVarint(payload) == payload.length) {
			auto json = parseJSON(cast(string)payload);
			if(json.type == JSON_TYPE.OBJECT) {
				auto desc = "description" in json;
				auto players = "players" in json;
				auto vers = "version" in json;
				if(desc && players && vers && players.type == JSON_TYPE.OBJECT && vers.type == JSON_TYPE.OBJECT) {
					string name;
					auto online = "online" in *players;
					auto max = "max" in *players;
					auto protocol = "protocol" in *vers;
					auto pname = "name" in *vers;

					if(online && max && protocol && pname && online.type == JSON_TYPE.INTEGER && max.type == JSON_TYPE.INTEGER && protocol.type == JSON_TYPE.INTEGER && pname.type == JSON_TYPE.STRING) {
						ret ~= JSONValue([
								"port": JSONValue(port),
								"motd": JSONValue(name),
								"protocol": JSONValue(*protocol),
								"version": JSONValue(*pname),
								"online": JSONValue(*online),
								"max": JSONValue(*max)
							]);
					}
				}
			}
		}
	}
	return ret;
}

JSONValue[] scanPocket(string ip, ushort scan_from, ushort scan_to, immutable size_t retry, ref shared size_t total_sent, ref shared size_t total_recv) {
	shared JSONValue[] ret;
	auto ssocket = cast(shared)new UdpSocket(getAddress(ip, 0)[0].addressFamily);
	shared bool finished = false;
	Thread send, recv;
	send = new Thread({
		auto socket = cast()ssocket;
		size_t sent;
		foreach(i ; 0..retry) {
			foreach(ulong port ; scan_from..scan_to+1) {
				if(sent >= 2500) {
					// this limits to ~3.5 mbps
					sent = 0;
					Thread.sleep(dur!"msecs"(1));
				}
				socket.sendTo(1 ~ nativeToBigEndian(port) ~ magic, getAddress(ip, cast(ushort)port)[0]);
				sent += 25;
				atomicOp!"+="(total_sent, 25);
			}
		}
		Thread.sleep(dur!"seconds"(1));
		finished = true;
	});
	recv = new Thread({
		auto socket = cast()ssocket;
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"seconds"(3));
		ushort[] ports;
		while(!finished) {
			ubyte[] buffer = new ubyte[256];
			Address address;
			auto recv = socket.receiveFrom(buffer, address);
			if(recv > 0) {
				immutable port = to!ushort(address.toPortString());
				atomicOp!"+="(total_recv, recv);
				if(buffer[0] == 28 && recv > 35 && !ports.canFind(port)) {
					ubyte[8] pingId = buffer[1..9];
					ubyte[16] m = buffer[17..33];
					ubyte[2] length = buffer[33..35];
					if(bigEndianToNative!ulong(pingId) == port && m == magic && bigEndianToNative!ushort(length) == recv - 35) {
						string[] spl = split(cast(string)buffer[35..recv], ";");
						if(spl.length >= 6 && spl[0] == "MCPE") {
							try {
								ret ~= cast(shared)JSONValue([
										"port": JSONValue(port),
										"motd": JSONValue(spl[1]),
										"protocol": JSONValue(to!uint(spl[2])),
										"version": JSONValue(spl[3]),
										"online": JSONValue(to!uint(spl[4])),
										"max": JSONValue(to!uint(spl[5]))
									]);
								ports ~= port;
							} catch(ConvException) {}
						}
					}
				}
			}
		}
	});
	send.start();
	recv.start();
	send.join();
	recv.join();
	return cast(JSONValue[])ret;
}

uint readVarint(ref ubyte[] buffer) {
	uint value = 0;
	uint shift = 0;
	ubyte next = 0x80;
	while(buffer.length && (next & 0x80)) {
		next = buffer[0];
		buffer = buffer[1..$];
		value |= (next & 0x7F) << shift;
		shift += 7;
	}
	return value;
}
