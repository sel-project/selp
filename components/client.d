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

import core.stdc.stdlib : exit;
import core.thread : Thread;

import std.algorithm : canFind, min;
import std.base64 : Base64, Base64URL;
static import std.bitmanip;
import std.conv : to;
import std.datetime : dur;
import std.json;
import std.math : ceil;
import std.random : uniform;
import std.regex;
import std.socket;
import std.stdio : writeln, readln;
import std.string;
import std.system : Endian;
import std.typecons : Tuple;
import std.uuid : randomUUID;
import std.zlib;

import sul.types.var;

enum uint __version = to!uint(import("version.txt").strip);

enum ubyte __game = __version & 0b1111;

enum uint __protocol = __version >> 4;

static if(__game == 1) enum __gamestr = "pocket";
else static if(__game == 2) enum __gamestr = "minecraft";
else static assert(0);

mixin("import sul.constants." ~ __gamestr ~ __protocol.to!string ~ " : Constants;");

mixin("import sul.protocol." ~ __gamestr ~ __protocol.to!string ~ " : Types, Packets;");

enum unformatRegex = ctRegex!"§[a-fA-F0-9k-or]";

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

	immutable edu = args.canFind("-edu");

	// list packets
	string[] clientbound, serverbound;
	foreach(immutable packet ; __traits(allMembers, Packets.Play)) {
		mixin("alias T = Packets.Play." ~ packet ~ ";");
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

		static import sul.protocol.raknet8;

		static struct Raknet {

			alias Types = sul.protocol.raknet8.Types;
			
			alias Status = sul.protocol.raknet8.Packets.Status;

			alias Login = sul.protocol.raknet8.Packets.Login;

			alias Connection = sul.protocol.raknet8.Packets.Connection;

		}

		enum ubyte[] magic = [0, 255, 255, 0, 254, 254, 254, 254, 253, 253, 253, 253, 18, 52, 86, 120];

		buffer = new ubyte[1536];
		ushort mtu = 1464;
		immutable clientId = uniform!"[]"(long.min, long.max);

		int sendCount = 0;
		int receiveCount = -1;

		ubyte[][uint] awaitingAcks;

		uint[] lost;

		ushort splitSend = 0;

		ubyte[][][ushort] splitReceived;

		writeln("Connecting to ", address, " as ", username, " with Minecraft: Pocket Edition using protocol ", __protocol);

		Socket socket = new UdpSocket(address.addressFamily);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, dur!"seconds"(5));
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"seconds"(5));
		socket.blocking = true;

		void send(ubyte[] data) {
			socket.sendTo(data, address);
		}

		void encapsulate(ubyte[] payload, bool play=true) {
			if(play) {
				if(payload.length > 128) {
					Compress compress = new Compress(6, HeaderFormat.deflate);
					payload = cast(ubyte[])compress.compress(varuint.encode(payload.length.to!uint) ~ payload.dup);
					payload ~= cast(ubyte[])compress.flush();
					payload = Packets.Play.Batch(payload.dup).encode();
				}
				payload = 254 ~ payload;
			}
			if(payload.length > mtu) {
				uint count = ceil(payload.length.to!float / 1464f).to!uint;
				uint sizes = ceil(payload.length.to!float / count).to!uint;
				foreach(uint order ; 0..count) {
					ubyte[] buffer = payload[order*sizes..min((order+1)*sizes, $)];
					auto split = Raknet.Types.Split(count, splitSend, order);
					auto encapsulation = Raknet.Types.Encapsulation(16 + 64, cast(ushort)(buffer.length * 8), sendCount, 0, ubyte.init, split, buffer);
					ubyte[] packet = Raknet.Connection.Encapsulated(sendCount, encapsulation).encode();
					packet[0] = 140;
					awaitingAcks[sendCount] = packet;
					send(packet);
					sendCount++;
				}
				splitSend++;
			} else {
				ubyte[] packet = Raknet.Connection.Encapsulated(sendCount, Raknet.Types.Encapsulation(64, to!ushort(payload.length << 3), sendCount, 0, ubyte.init, Raknet.Types.Split.init, payload)).encode();
				awaitingAcks[sendCount] = packet;
				send(packet);
				sendCount++;
			}
		}

		ubyte[] receive() {
			Address a;
			recv = socket.receiveFrom(buffer, a);
			if(recv <= 0) {
				writeln("Network error: ", lastSocketError);
				socket.close();
				exit(0);
			}
			//writeln(buffer);
			return buffer[0..recv];
		}

		Raknet.Types.Address toAddress(Address from) {
			Raknet.Types.Address ret;
			if(from.addressFamily == AddressFamily.INET) {
				auto v4 = new InternetAddress(from.toAddrString(), to!ushort(from.toPortString()));
				ret.type = 4;
				ret.ipv4 = cast(ubyte[])[(v4.addr >> 24) ^ 255, (v4.addr >> 16) ^ 255, (v4.addr >> 8) ^ 255, v4.addr ^ 255];
				ret.port = v4.port;
			} else if(from.addressFamily == AddressFamily.INET6) {
				auto v6 = new Internet6Address(from.toAddrString(), to!ushort(from.toPortString()));
				ret.type = 6;
				ret.ipv6 = v6.addr;
				ret.port = v6.port;
			}
			return ret;
		}

		// open connection request 1
		send(Raknet.Login.OpenConnectionRequest1(magic, 8, new ubyte[1464]).encode());

		// open connection response 1
		auto ocr1 = Raknet.Login.OpenConnectionReply1().decode(receive());
		mtu = ocr1.mtuLength;

		// open connection request 2
		send(Raknet.Login.OpenConnectionRequest2(magic, toAddress(address), mtu, clientId).encode());

		// open connection response 2
		auto ocr2 = Raknet.Login.OpenConnectionReply2().decode(receive());

		// send client connect
		encapsulate(Raknet.Login.ClientConnect(clientId, 0).encode(), false);

		void delegate(ubyte[]) handle;

		void handlePlayImpl(ubyte[] payload) {
			if(payload.length) {
				switch(payload[0]) {
					case Packets.Play.Batch.packetId:
						UnCompress uncompress = new UnCompress();
						ubyte[] batch = cast(ubyte[])uncompress.uncompress(Packets.Play.Batch().decode(payload).data);
						batch ~= cast(ubyte[])uncompress.flush();
						while(batch.length) {
							size_t length = varuint.fromBuffer(batch);
							handlePlayImpl(batch[0..length]);
							batch = batch[length..$];
						}
						break;
					case Packets.Play.StartGame.packetId:
						writeln(payload);
						writeln(Packets.Play.StartGame().decode(payload));
						break;
					case Packets.Play.PlayStatus.packetId:
						auto ps = Packets.Play.PlayStatus().decode(payload);
						if(ps.status == Constants.PlayStatus.status.spawned) {

						}
						break;
					case Packets.Play.MovePlayer.packetId:
						auto move = Packets.Play.MovePlayer().decode(payload);
						//TODO compare with player's entity id and update last known position
						break;
					case Packets.Play.Text.packetId:
						auto text = Packets.Play.Text().decode(payload);
						if(text.type == Packets.Play.Text.Raw.type) {
							auto raw = Packets.Play.Text.Raw().decode(payload);
							writeln(raw.message.replaceAll(unformatRegex, ""));
						}
						break;
					case Packets.Play.AddPlayer.packetId:
						//TODO create a list of known players
						//writeln(Packets.Play.AddPlayer().decode(payload));
						break;
					case Packets.Play.Disconnect.packetId:
						auto disconnect = Packets.Play.Disconnect().decode(payload);
						writeln("Disconnected: ", disconnect.message.replaceAll(unformatRegex, "").strip);
						exit(0);
						break;
					default:
						break;
				}
			}
		}
		
		void handlePlay(ubyte[] payload) {
			if(payload[0] == 254 && payload.length > 1) {
				handlePlayImpl(payload[1..$]);
			}
		}

		void handleLogin(ubyte[] payload) {
			if(payload.length > 2 && payload[0] == 254) {
				if(payload[1] == Packets.Play.PlayStatus.packetId) {
					auto playstaus = Packets.Play.PlayStatus().decode(payload[1..$]);
					switch(playstaus.status) {
						case Constants.PlayStatus.status.ok:
							writeln("Connected to the server");
							handle = &handlePlay;
							return;
						case Constants.PlayStatus.status.outdatedClient:
							writeln("Could not connect: Outdated Client!");
							break;
						case Constants.PlayStatus.status.outdatedServer:
							writeln("Could not connect: Outdated Server!");
							break;
						default:
							writeln("Unknown status: ", playstaus.status);
							break;
					}
					exit(0);
				} else if(payload[1] == Packets.Play.Disconnect.packetId) {
					return handlePlay(payload);
				}
			}
			writeln("Wrong packet received while waiting for PlayStatus");
			exit(0);
		}

		void handleServerHandshake(ubyte[] payload) {

			auto sh = Raknet.Login.ServerHandshake().decode(payload);
			encapsulate(Raknet.Login.ClientHandshake(toAddress(address), sh.systemAddresses, sh.ping, sh.pong).encode(), false);

			string chain_data = Base64URL.encode(cast(ubyte[])(`{"extraData":{"displayName":"` ~ username ~ `","identity":"` ~ randomUUID().toString() ~ `"}}`)).replace("=", "");
			string chain = `{"chain":[".` ~ chain_data ~ `."]}`;
			string client_data = "." ~ Base64URL.encode(cast(ubyte[])(`{"SkinId":"Standard_Custom","SkinData":"` ~ Base64.encode(randomSkin()) ~ `"}`)).idup.replace("=", "") ~ ".";
			ubyte[] data = new ubyte[4];
			std.bitmanip.write!(uint, Endian.littleEndian)(data, chain.length.to!uint, 0);
			data ~= cast(ubyte[])chain;
			data ~= new ubyte[4];
			std.bitmanip.write!(uint, Endian.littleEndian)(data, client_data.length.to!uint, chain.length + 4);
			data ~= cast(ubyte[])client_data;
			Compress compress = new Compress(7, HeaderFormat.deflate);
			data = cast(ubyte[])compress.compress(data.dup);
			data ~= cast(ubyte[])compress.flush();
			encapsulate(Packets.Play.Login(__protocol, edu, data).encode(), true);
			handle = &handleLogin;

		}
		
		handle = &handleServerHandshake;

		// ping (keep alive thread)
		new Thread({
			long count = 0;
			while(true) {
				Thread.sleep(dur!"seconds"(4));
				encapsulate(Raknet.Connection.Ping(count++).encode(), false);
			}
		}).start();

		// nack
		new Thread({
			while(true) {
				foreach(i ; 0..5) {
					Thread.sleep(dur!"seconds"(1));
					if(lost.length) {
						auto l = lost.dup;
						Raknet.Connection.Nack packet;
						do {
							auto current = Raknet.Types.Acknowledge(true, l[0], l[0]);
							l = l[1..$];
							while(l.length && l[0] == current.last + 1) {
								current.unique = false;
								current.last = l[0];
								l = l[1..$];
							}
							packet.packets ~= current;
						} while(l.length);
						send(packet.encode());
					}
				}
				lost.length = 0; // don't ask too much for lost packets
			}
		}).start();

		// start connection
		while(true) {
			ubyte[] data = receive();
			switch(data[0]) {
				case Raknet.Connection.Ack.packetId:
					foreach(ack ; Raknet.Connection.Ack().decode(data).packets) {
						foreach(uint i ; ack.first..(ack.unique ? ack.first : ack.last)+1) {
							awaitingAcks.remove(i);
						}
					}
					break;
				case Raknet.Connection.Nack.packetId:
					// mcpe doesn't repeat itself
					break;
				case 128:..case 143:
					auto encapsulated = Raknet.Connection.Encapsulated().decode(data);
					if(encapsulated.count < receiveCount) {
						// discard if not in lost array
						bool found = false;
						foreach(i, l; lost) {
							if(l == encapsulated.count) {
								found = true;
								lost = lost[0..i] ~ lost[i+1..$];
								break;
							}
						}
						if(!found) break; // duplicated
					} else {
						if(receiveCount + 1 != encapsulated.count) {
							// lost some packets
							foreach(uint i ; receiveCount+1..encapsulated.count) {
								lost ~= i;
							}
						}
						receiveCount = encapsulated.count;
					}
					data = encapsulated.encapsulation.payload;
					send(Raknet.Connection.Ack([Raknet.Types.Acknowledge(true, encapsulated.count)]).encode());
					if(encapsulated.encapsulation.info & 16) {
						auto split = encapsulated.encapsulation.split;
						if(split.id !in splitReceived) {
							splitReceived[split.id] = new ubyte[][split.count];
						}
						splitReceived[split.id][split.order] = data;
						bool full = true;
						data.length = 0;
						foreach(ubyte[] s ; splitReceived[split.id]) {
							if(s.length == 0) {
								full = false;
								break;
							} else {
								data ~= s;
							}
						}
						if(full) {
							splitReceived.remove(split.id);
						} else {
							break;
						}
					}
					if(data.length) {
						switch(data[0]) {
							case Raknet.Connection.Pong.packetId:
								//TODO use to calculate latency
								break;
							default:
								handle(data);
								break;
						}
					}
					break;
				default:
					break;
			}
		}

	} else {

		writeln("Connecting to ", address, " as ", username, " with Minecraft using protocol ", __protocol);

		buffer = new ubyte[4096];
		size_t thresold = 0;
		bool compression = false;

		Socket socket = new TcpSocket(address);
		socket.blocking = true;

		void send(ubyte[] data) {
			socket.send(varuint.encode(data.length.to!uint) ~ data);
		}

		void encapsulate(ubyte[] data) {
			uint length = 0;
			if(data.length > thresold) {
				length = data.length.to!uint;
				Compress compress = new Compress(6, HeaderFormat.deflate);
				data = cast(ubyte[])compress.compress(data.dup);
				data ~= cast(ubyte[])compress.flush();
			}
			send(varuint.encode(length) ~ data);
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
		send(Packets.Status.Handshake(__protocol, ip, port, Constants.Handshake.next.login).encode());

		// send login start packet
		send(Packets.Login.LoginStart(username).encode());
		
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
			return ret.replaceAll(unformatRegex, "");
		}

		bool login = true;

		// receive set compression, login success or disconnect (login)
		while(login) {

			ubyte[] b = next();
			uint id = varuint.fromBuffer(b);
			switch(id) {
				case Packets.Login.Disconnect.packetId:
					writeln("Disconnected: ", unformat(Packets.Login.Disconnect().decode!false(b).reason));
					goto close;
				case Packets.Login.EncryptionRequest.packetId:
					writeln("Error: you need to authenticate to connect to this server");
					goto close;
				case Packets.Login.SetCompression.packetId:
					thresold = Packets.Login.SetCompression().decode!false(b).thresold;
					compression = true;
					break;
				case Packets.Login.LoginSuccess.packetId:
					auto success = Packets.Login.LoginSuccess().decode!false(b);
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
				case Packets.Play.KeepAliveClientbound.packetId:
					encapsulate(Packets.Play.KeepAliveServerbound(Packets.Play.KeepAliveClientbound().decode!false(b).id).encode());
					break;
				case Packets.Play.JoinGame.packetId:
					//TODO call event if exist (spawned)
					break;
				case Packets.Play.ChatMessageClientbound.packetId:
					auto chat = Packets.Play.ChatMessageClientbound().decode!false(b);
					if(logs.chat && chat.position != Constants.ChatMessageClientbound.position.aboveHotbar) {
						writeln(unformat(chat.message));
					}
					break;
				case Packets.Play.Disconnect.packetId:
					writeln("Disconnected: ", unformat(Packets.Play.Disconnect().decode!false(b).reason));
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

string randomUsername() {
	static if(__game == 1) size_t length = uniform!"[]"(1, 15);
	else size_t length = uniform!"[]"(3, 16);
	char[] username = new char[length];
	foreach(ref char c ; username) {
		c = uniform!"[]"('a', 'z');
		if(!uniform!"[]"(0, 4)) c -= 32;
	}
	return username.idup;
}

ubyte[] randomSkin() {
	ubyte[] skin = new ubyte[8192];
	foreach(ref b ; skin) {
		b = uniform(0, 256) & 255;
	}
	return skin;
}
