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
module client;

import std.conv : to;
import std.json;
import std.random : uniform;
import std.regex;
import std.socket;
import std.stdio : writeln, readln;
import std.string;
import std.typecons : Tuple;
import std.zlib;

static import sul.constants;
static import sul.protocol;

import sul.types.var;

enum uint __version = to!uint(import("version.txt").strip);

enum ubyte __game = __version & 0b1111;

enum uint __protocol = __version >> 4;

static if(__game == 1) enum __gamestr = "pocket";
else static if(__game == 2) enum __gamestr = "minecraft";
else static assert(0);

alias Protocol = sul.protocol.Protocol!(__gamestr, __protocol, sul.protocol.SoftwareType.client);

alias Types = Protocol.Types;

alias Constants = sul.constants.Constants!(__gamestr, __protocol);

void main(string[] args) {

	bool has_port = args[1].lastIndexOf(":") > args[1].lastIndexOf("]");
	string ip = args[1].replace("[", "").replace("]", "");
	ushort port = __game == 1 ? 19132 : 25565;
	if(has_port) {
		string[] spl = ip.split(":");
		ip = spl[0..$-1].join(":");
		port = to!ushort(spl[$-1]);
	}
	Address address = getAddress(ip, port)[0];

	args = args[2..$];

	T find(T)(string key, T def) {
		foreach(arg ; args) {
			if(arg.toLower.startsWith("-" ~ key ~ "=")) {
				try {
					return to!T(arg[2+key.length..$]);
				} catch(Exception) {}
			}
		}
		return def;
	}

	string options = find("options", "");

	string username = find("username", randomUsername());
	string password = find("password", "");

	// list packets
	string[] clientbound, serverbound;
	foreach(immutable packet ; __traits(allMembers, Protocol.Play)) {
		mixin("alias T = Protocol.Play." ~ packet ~ ";");
		static if(is(typeof(T.encode))) {
			clientbound ~= packet;
		}
		static if(is(typeof(T.decode))) {
			serverbound ~= packet;
		}
	}

	// parse options
	Logs logs = Logs(true);

	ubyte[] buffer;
	ptrdiff_t recv;

	static if(__gamestr == "pocket") {

		writeln("Connecting to ", address, " as ", username, " with Minecraft: Pocket Edition using protocol ", __protocol);

	} else {

		writeln("Connecting to ", address, " as ", username, " with Minecraft using protocol ", __protocol);

		buffer = new ubyte[4096];
		size_t thresold = 0;
		bool compression = false;

		Socket socket = new TcpSocket(address);
		socket.blocking = true;

		void send(ubyte[] data) {
			socket.send(varuint(data.length.to!uint).encode() ~ data);
		}

		void encapsulate(ubyte[] data) {
			uint length = 0;
			if(data.length > thresold) {
				length = data.length.to!uint;
				Compress compress = new Compress(6, HeaderFormat.deflate);
				data = cast(ubyte[])compress.compress(data.dup);
				data ~= cast(ubyte[])compress.flush();
			}
			send(varuint(length).encode() ~ data);
		}

		size_t next_length;
		ubyte[] next_buffer;
		
		void receive() {
			recv = socket.receive(buffer);
			if(recv > 0) {
				next_buffer ~= buffer[0..recv];
			}
		}

		ubyte[] next() {
			bool canReadLength() {
				if(next_buffer.length >= 5) return true;
				foreach(ubyte b ; next_buffer) {
					if(b <= 127) return true;
				}
				return false;
			}
			while(next_length == 0 && !canReadLength()) {
				receive();
			}
			next_length = varuint.fromBuffer(next_buffer);
			while(next_buffer.length < next_length) {
				receive();
			}
			ubyte[] ret = next_buffer[0..next_length];
			next_buffer = next_buffer[next_length..$];
			next_length = 0;
			if(compression) {
				uint length = varuint.fromBuffer(ret);
				if(length != 0) {
					UnCompress uncompress = new UnCompress(length);
					ret = cast(ubyte[])uncompress.uncompress(ret.dup);
					ret ~= cast(ubyte[])uncompress.flush();
				}
			}
			return ret;
		}

		// send handshake packet
		send(Protocol.Status.Handshake(varuint(__protocol), ip, port, varuint(Constants.Handshake.next.login)).encode());

		// send login start packet
		send(Protocol.Login.LoginStart(username).encode());
		
		string unformat(string str) {
			string ret = "";
			auto json = parseJSON(str);
			auto extra = "extra" in json;
			auto text = "text" in json;
			auto translate = "translate" in json;
			if(extra && (*extra).type == JSON_TYPE.ARRAY) {
				foreach(JSONValue value ; (*extra).array) {
					if(value.type == JSON_TYPE.OBJECT) {
						foreach(string key, JSONValue v; value.object) {
							if(v.type == JSON_TYPE.STRING) {
								if(key == "text") {
									// only one supported by now
									ret ~= v.str;
								}
							}
						}  
					}
				}
			}
			if(text && (*text).type == JSON_TYPE.STRING) {
				ret ~= (*text).str;
			}
			if(translate && (*translate).type == JSON_TYPE.STRING) {
				ret ~= (*translate).str;
			}
			return ret.replaceAll(ctRegex!"§[a-zA-Z0-9]", "");
		}

		bool login = true;

		// receive set compression, login success or disconnect (login)
		while(login) {

			ubyte[] b = next();
			uint id = varuint.fromBuffer(b);
			switch(id) {
				case Protocol.Login.Disconnect.packetId:
					writeln("Disconnected: ", unformat(Protocol.Login.Disconnect().decode!false(b).reason));
					goto close;
				case Protocol.Login.SetCompression.packetId:
					thresold = Protocol.Login.SetCompression().decode!false(b).thresold;
					compression = true;
					break;
				case Protocol.Login.LoginSuccess.packetId:
					auto success = Protocol.Login.LoginSuccess().decode!false(b);
					writeln("Logged in as ", success.username, " with UUID ", success.uuid);
					login = false;
					break;
				default:
					writeln("Unexpected packet with id ", id, " during login");
					break;
			}

		}

		//TODO call events if exist (connected)

		while(true) {

			ubyte[] b = next();
			uint id = varuint.fromBuffer(b);

			//writeln("received ", id, " with ", b.length, " bytes");

			// packet also handled by client
			switch(id) {
				case Protocol.Play.KeepAliveClientbound.packetId:
					encapsulate(Protocol.Play.KeepAliveServerbound(Protocol.Play.KeepAliveClientbound().decode!false(b).id).encode());
					break;
				case Protocol.Play.JoinGame.packetId:
					//TODO call event if exist (spawned)
					break;
				case Protocol.Play.ChatMessageClientbound.packetId:
					auto chat = Protocol.Play.ChatMessageClientbound().decode!false(b);
					if(logs.chat && chat.position != Constants.ChatMessageClientbound.position.aboveHotbar) {
						writeln(unformat(chat.message));
					}
					break;
				case Protocol.Play.Disconnect.packetId:
					writeln("Disconnected: ", unformat(Protocol.Play.Disconnect().decode!false(b).reason));
					goto close;
				default:
					break;
			}

		}

	close: // 😨

		socket.close();

	}

}

alias Logs = Tuple!(bool, "chat");

struct Event {}

string randomUsername() {
	static if(__game == 1) {
		size_t length = uniform!"[]"(1, 15);
	} else {
		size_t length = uniform!"[]"(3, 16);
	}
	char[] username = new char[length];
	foreach(ref char c ; username) {
		c = uniform!"[]"('a', 'z');
		if(!uniform!"[]"(0, 4)) c -= 32;
	}
	return username.idup;
}
