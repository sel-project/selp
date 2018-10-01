/*
 * Copyright (c) 2016-2018 sel-project
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 */
module selp.util;

import std.path : dirSeparator;
import std.process : executeShell;
import std.string : toLower, strip, startsWith;

import terminal : Terminal, Foreground, Color, reset;

class Manager {
	
	public immutable string exe;
	public immutable string command;
	public immutable string[] args;

	public immutable string home;

	public Terminal terminal;

	private void function(Manager)[string] commands;

	public this(string[] args) {
		
		assert(args.length);
		
		if(args.length < 2) args ~= "help";
		
		this.exe = args[0];
		this.command = args[1];
		this.args = args[2..$].idup;

		version(Windows) {
			this.home = locationOf("%appdata%") ~ dirSeparator ~ "selp" ~ dirSeparator;
		} else {
			import std.process : environment;
			this.home = environment["HOME"] ~ dirSeparator ~ ".selp" ~ dirSeparator;
		}

		this.terminal = new Terminal();

	}

	public void register(string command, void function(Manager) func) {
		this.commands[command] = func;
	}
	
	public void execute() {
		auto command = this.command in this.commands;
		if(command) {
			(*command)(this);
		} else {
			writeError(this, "Unkown command. Use 'help' for a list of commands");
		}
	}
	
}

void writeError(Manager manager, string error) {
	manager.terminal.writeln(Foreground(Color.brightRed), error, reset);
}

string locationOf(string location) {
	version(Windows) {
		return executeShell("cd " ~ location ~ " && cd").output.strip;
	} else {
		return executeShell("cd " ~ location ~ " && pwd").output.strip;
	}
}

string find(string search, string[] args, lazy string default_) {
	foreach(arg ; args) {
		if(arg.startsWith("--" ~ search ~ "=")) return arg[search.length+3..$];
	}
	return default_;
}
