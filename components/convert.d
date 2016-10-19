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
module convert;

import std.base64 : Base64URL;
import std.file : write;
import std.process : executeShell, wait, spawnShell;
import std.random : uniform;
import std.stdio : writeln;
import std.string;

void main(string[] args) {

	string format_from = args[1].toLower;
	string format_to = args[2].toLower;
	string location_from = args[3];
	string location_to = args[4];

	bool check(string format) {
		return format == "sel" || format == "sel-le" || format == "sel-be" || format == "anvil" || format == "leveldb";
	}

	// validate formats
	if(!check(format_from)) return;
	if(!check(format_to)) return;

	string toName(string format) {
		final switch(format) {
			case "sel": return "DefaultSel";
			case "sel-le": return "LittleEndianSel";
			case "sel-be": return "BigEndianSel";
			case "anvil": return "Anvil";
			case "leveldb": return "LevelDB";
		}
	}

	format_from = toName(format_from);
	format_to = toName(format_to);

	writeln("converting world from ", format_from, " to ", format_to);

	// create a server and plugin
	string serverName = randomName;
	executeShell("sel init " ~ serverName ~ " node");
	string location = executeShell("sel locate " ~ serverName).output.strip;
	write(location ~ "main.d", q{
			module main;

			import sel.world.io;
			import sel.world.world : World;

			void main(string[] args) {
				World world = new World();
				{from}.readWorld(world, "{froml}");
				{to}.writeWorld(world, "{tol}");
			}
		}.replace("{from}", format_from).replace("{to}", format_to).replace("{froml}", location_from).replace("{tol}", location_to));

	// convert
	wait(spawnShell("cd " ~ location ~ " && rdmd -version=NoRead main.d"));

	// delete server and plugin
	executeShell("sel delete " ~ serverName);

}

@property string randomName() {
	ubyte[] ret;
	foreach(size_t i ; 0..48) {
		ret ~= cast(ubyte)uniform!"[]"(0, 255);
	}
	return Base64URL.encode(ret);
}
