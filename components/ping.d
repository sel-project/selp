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
module ping;

import core.thread : Thread, dur;

import std.conv : to;
import std.datetime : Clock, UTC;
import std.json;
import std.socket;
import std.stdio : write;
import std.string;

enum magic = cast(ubyte[])[0x00, 0xFF, 0xFF, 0x00, 0xFE, 0xFE, 0xFE, 0xFE, 0xFD, 0xFD, 0xFD, 0xFD, 0x12, 0x34, 0x56, 0x78];

void main(string[] args) {

	shared string[] ret;

	string[] ipport = (args.length > 1 ? args[1] : "127.0.0.1").split(":");
	string ip = ipport[0];
	ushort port = ipport.length == 2 ? to!ushort(ipport[1]) : 0;

	// Minecraft
	try {
		//TODO only connect if port is open
		ushort p = port==0 ? 25565 : port;
		TcpSocket socket = new TcpSocket();
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, dur!"msecs"(256));
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"seconds"(4));
		socket.connect(getAddress(ip, p)[0]);
		string address = ipport[0]; // servers with proxies or ddos protection may check the ip
		socket.send(cast(ubyte[])[address.length + 6, 0, 0, address.length] ~ cast(ubyte[])address ~ cast(ubyte[])[(p >> 8) & 255, p & 255, 1]);
		socket.send(cast(ubyte[])[1, 0]);
		auto time = peek;
		ubyte[] query;
		ubyte[] buffer = new ubyte[16384];
		ptrdiff_t r;
		ulong ping;
		while((r = socket.receive(buffer)) > 0) {
			ping = peek - time;
			query ~= buffer[0..r];
		}
		if(query.length > 3) {
			removeVarint(query); // packet id
			removeVarint(query); // protocol
			removeVarint(query); // string length
			auto json = parseJSON(cast(string)query).object;
			string name = "";
			if(json["description"].type == JSON_TYPE.OBJECT) {
				if("extra" in json["description"].object) {
					foreach(JSONValue value ; json["description"].object["extra"].array) {
						if("text" in value) {
							name ~= value["text"].str; 
						}
					}
				} else {
					name = json["description"].object["text"].str;
				}
			} else {
				name = json["description"].str;
			}
			string j = "\"minecraft\":{";
			j ~= "\"name\":\"" ~ name.strip ~ "\",";
			j ~= "\"address\":\"" ~ address ~ ":" ~ to!string(p) ~ "\",";
			j ~= "\"protocol\":" ~ json["version"].object["protocol"].integer.to!string ~ ",";
			j ~= "\"online\":" ~ json["players"].object["online"].integer.to!string ~ ",";
			j ~= "\"max\":" ~ json["players"].object["max"].integer.to!string ~ ",";
			j ~= "\"ping\":" ~ to!string(ping / 2) ~ "}";
			ret ~= j;
		}
		socket.close();
	} catch(Throwable) {}

	// Minecraft: Pocket Edition
	try {
		ushort p = port==0 ? 19132 : port;
		Address address = getAddress(ip, p)[0];
		UdpSocket socket = new UdpSocket();
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, dur!"msecs"(256));
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"seconds"(4));
		socket.sendTo(1 ~ new ubyte[8] ~ magic, address); // server may check the raknet's magic number
		auto time = peek;
		ubyte[] buffer = new ubyte[256];
		ptrdiff_t r;
		if((r = socket.receiveFrom(buffer, address)) > 35) {
			// MCPE;server name;protocol;version;online;max
			string[] query = (cast(string)buffer[35..r]).split(";");
			string j = "\"pocket\":{";
			j ~= "\"name\":\"" ~ query[1] ~ "\",";
			j ~= "\"address\":\"" ~ ipport[0] ~ ":" ~ to!string(p) ~ "\",";
			j ~= "\"protocol\":" ~ query[2] ~ ",";
			j ~= "\"online\":" ~ query[4] ~ ",";
			j ~= "\"max\":" ~ query[5] ~ ",";
			j ~= "\"ping\":" ~ to!string((peek - time) / 2) ~ "}";
			ret ~= j;
		}
		socket.close();
	} catch(Throwable) {}

	write("{", ret.join(","), "}");

}

@property ulong peek() {
	auto t = Clock.currTime(UTC());
	return t.toUnixTime!long * 1000 + t.fracSecs.total!"msecs";
}

void removeVarint(ref ubyte[] buffer) {
	while(buffer.length && (buffer[0] & 0b10000000)) {
		buffer = buffer[1..$];
	}
	if(buffer.length > 0) buffer = buffer[1..$];
}
