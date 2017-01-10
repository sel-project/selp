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
module query;

import std.algorithm : max;
import std.bitmanip;
import std.conv : to, ConvException;
import std.datetime : StopWatch, AutoStart, dur;
import std.json : JSONValue;
import std.socket;
import std.stdio : stdwrite = write;
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

	JSONValue[string] ret;

	foreach(ushort p ; port == 0 ? cast(ushort[])[25565, 19132] : [port]) {
		try {
			query(getAddress(ip, p)[0], ret);
		} catch(Throwable t) {
			ret["error"] = t.msg;
			break;
		}
	}

	stdwrite(JSONValue(ret).toString());

}

// returns a json!
void query(Address address, ref JSONValue[string] ret) {

	ulong ping;

	ubyte[] buffer = new ubyte[2 ^^ 16];
	ptrdiff_t recv;

	UdpSocket socket = new UdpSocket(address.addressFamily);
	socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
	socket.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, dur!"msecs"(256));
	socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"seconds"(2));
	socket.sendTo(cast(ubyte[])[254, 253, 9, 0, 0, 0, 0], address);
	scope(exit) socket.close();
	auto timer = StopWatch(AutoStart.yes);
	if((recv = socket.receiveFrom(buffer, address)) <= 5 || recv >= buffer.length) return;
	ping += timer.peek.usecs;
	timer.stop();
	ubyte[] token = new ubyte[4];
	try {
		write!int(token, to!int(cast(string)buffer[5..recv-1]), 0);
	} catch(ConvException) {
		write!uint(token, to!uint(cast(string)buffer[5..recv-1]), 0);
	}
	socket.sendTo(cast(ubyte[])[254, 253, 0, 0, 0, 0, 0] ~ token ~ new ubyte[4], address); // full stats
	timer.reset();
	timer.start();
	if((recv = socket.receiveFrom(buffer, address)) <= 16 || recv >= buffer.length) return;
	ping += timer.peek.usecs;

	ubyte[] stats = buffer[5..recv];
	auto info = parseKeyValue(stats);
	stats = stats[10..$];
	auto players = parseValue(stats);

	auto game = "game_id" in info;
	if(game && (*game == "MINECRAFT" || *game == "MINECRAFTPE")) {

		JSONValue[string] json;
		json["ping"] = ping / 2000;
		json["address"] = address.toString();
		json["motd"] = info["hostname"];
		json["online"] = to!uint(info["numplayers"]);
		json["max"] = to!uint(info["maxplayers"]);
		json["players"] = players;

		if(info["plugins"].length) {
			auto spl = info["plugins"].split(":");
			json["software"] = spl[0].strip;
			JSONValue[] plugins;
			foreach(string plugin ; spl[1..$].join(":").split(";")) {
				auto s = plugin.split(" ");
				if(s.length > 1) {
					plugins ~= JSONValue(["name": s[0..$-1].join(" ").strip, "version": s[$-1].strip]);
				}
			}
			json["plugins"] = plugins;
		} else {
			json["software"] = "Vanilla";
			json["plugins"] = (JSONValue[]).init;
		}

		ret[*game == "MINECRAFT" ? "minecraft" : "pocket"] = json;

	}

}

string[string] parseKeyValue(ref ubyte[] buffer) {
	// key\0value\0key\0value\0\0
	string[string] ret;
	ubyte[] next;
	string key = null;
	bool last0 = false;
	foreach(size_t i, ref ubyte b; buffer) { // do not count the last null byte
		if(b == 0) {
			if(last0 && key is null) {
				buffer = buffer[i..$];
				return ret;
			} else if(key is null) {
				key = cast(string)next;
				next.length = 0;
			} else {
				ret[key] = cast(string)next;
				key = null;
				next.length = 0;
			}
			last0 = true;
		} else {
			next ~= b;
			last0 = false;
		}
	}
	throw new Exception("Unterminated");
}

string[] parseValue(ref ubyte[] buffer) {
	// value\0value\0value\0\0
	string[] ret;
	ubyte[] next;
	bool last0 = true;
	foreach(size_t i, ref ubyte b; buffer) {
		if(b == 0) {
			if(last0) {
				buffer = buffer[i..$];
				return ret;
			} else {
				if(next.length > 0) {
					ret ~= cast(string)next;
					next.length = 0;
				}
			}
			last0 = true;
		} else {
			next ~= b;
			last0 = false;
		}
	}
	throw new Exception("Unterminated");
}
