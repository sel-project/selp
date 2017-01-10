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
module convert;

import std.algorithm : canFind;
import std.base64 : Base64URL;
import std.file : write, mkdirRecurse;
import std.path : dirSeparator;
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
		return ["sel", "sel-le", "sel-be", "anvil", "leveldb"].canFind(format);
	}

	// validate formats
	if(!check(format_from)) {
		writeln(format_from, " is not a valid format");
		return;
	}
	if(!check(format_to)) {
		writeln(format_to, " is not a valid format");
		return;
	}

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

	writeln("Setting up a converter");

	// create a server and plugin
	string serverName = randomName;
	executeShell("sel init " ~ serverName ~ " node -version=latest");
	string location = executeShell("sel locate " ~ serverName).output.strip;

	// overwrite the main file
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

	// compile as a versionless node

	immutable hidden = location ~ ".hidden" ~ dirSeparator;
	mkdirRecurse(hidden);
	write(hidden ~ "protocols.1", "");
	write(hidden ~ "protocols.2", "");
	executeShell("sel build " ~ serverName);
	
	writeln("Converting world from ", format_from, " to ", format_to);

	// convert
	wait(spawnShell("sel connect " ~ serverName));

	// delete server
	executeShell("sel delete " ~ serverName);

}

@property string randomName() {
	char[] ret;
	foreach(size_t i ; 0..8) {
		ret ~= uniform!"[]"('a', 'z');
	}
	return ret.idup;
}
