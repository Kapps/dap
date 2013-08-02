module dap.Standalone;
import std.getopt;
import std.conv;
version(Standalone) {	
	
	import std.stdio;
	import std.array;
	import dap.FileStore;
	import dap.BuildContext;
	import dap.ConsoleLogger;
	import ShardTools.PathTools;
	import ShardMath.Vector;
	import ShardTools.BufferPool;
	import ShardTools.Buffer;
	import dap.NodeSettings;
	
	/// Provides a stand-alone wrapper that uses a FileStore to keep track of assets, taking in the path to the settings file as the only argument.
	void main(string[] args) {
		//PathTools.SetWorkingDirectory(PathTools.ApplicationDirectory);
		string inputFolder, outputFolder;
		getopt(args,
	        "input", &inputFolder,
	        "output", &outputFolder
	    );
		if(!inputFolder || !outputFolder)
			throw new Exception("The 'input' and 'output' parameters must be specified, indicating the root folder containing unbuilt assets, and where to copy built assets to.");
		writeln("Input Path: ", PathTools.MakeAbsolute(inputFolder));
		writeln("Output Path: ", PathTools.MakeAbsolute(outputFolder));
		
		auto logger = new ConsoleLogger();
		logger.minSeverity = MessageSeverity.Trace;
		auto context = new BuildContext(logger);
		auto assetStore = new FileStore(inputFolder, outputFolder, "standalone", context);
		logger.logMessage(MessageSeverity.Info, "This is a test message!", assetStore);
		Asset testDoc = assetStore.registerAsset(assetStore, "test.txt");
		auto val = new Vector3f(1,  2, 3);
		writeln("Original: ", val);
		testDoc.settings.set!(Vector3f*)("Test", val);
		writeln("Stored as Test.");
		writeln("Stored: ", testDoc.settings.get!(Vector3f)("Test"));
		Buffer buffer = BufferPool.Global.Acquire(4096);
		testDoc.settings.serialize(buffer);
		writeln("Length: ", buffer.Count); 
		NodeSettings settings = new NodeSettings(null);
		settings.deserialize(buffer.FullData);
		writeln("Retrieved: ", settings.get!(Vector3f)("Test"));
		assetStore.save();
		// Prints "Hello World" string in console
		writeln("Hello World!");
	}
}