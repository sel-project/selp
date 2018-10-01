module selp.command.ping;

import std.algorithm : canFind;
import std.conv : to;
import std.string : indexOf, capitalize;

import sel.client : Client, BedrockClient, JavaClient;
import sel.terminal : writeln;

import selp.util : Manager, writeError;

void ping(Manager manager) {

	if(manager.args.length && manager.args[0] != "help") {

		string ip = manager.args[0];
		ushort port = 0;
		immutable i = ip.indexOf(":");
		if(i > 0) {
			port = to!ushort(ip[i+1..$]);
			ip = ip[0..i];
		}

		immutable bool bedrock = manager.args.canFind("--bedrock") || !manager.args.canFind("--java");
		immutable bool java = manager.args.canFind("--java") || !manager.args.canFind("--bedrock");

		immutable json = manager.args.canFind("--json");

		void ping(string type, Client client) {
			auto server = client.ping(ip, port == 0 ? client.defaultPort : port);
			if(server.valid) {
				manager.terminal.writeln(capitalize(type), " (", ip, ":", port == 0 ? client.defaultPort : port, ")");
				writeln(manager.terminal, server.rawMotd);
				manager.terminal.writeln("Players: ", server.online, "/", server.max);
				manager.terminal.writeln("Ping: ", server.ping, " ms");
			}
		}

		if(bedrock) ping("bedrock", new BedrockClient!160());

		if(java) ping("java", new JavaClient!340());

	} else {

		writeError(manager, "Usage: ping <server>[:port] [--bedrock] [--java]");

	}

}
