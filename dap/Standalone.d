module dap.Standalone;
version(Standalone) {	

	import std.stdio;
	import std.array;
	
	/// Provides a stand-alone wrapper that uses a FileStore to keep track of assets, taking in the path to the settings file as the only argument.
	void main(string[] args) {
		// TODO: Use that command-line thing from phobos.
		string settingPath = join(args, " ");
	    // Prints "Hello World" string in console
	    writeln("Hello World!");
	    
	    // Lets the user press <Return> before program returns
	    stdin.readln();
	}

}