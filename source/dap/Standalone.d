module dap.Standalone;
version(Standalone) {	
	import std.getopt;
	import std.conv;
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
	import std.path;
	import ShardTools.Udas;
	import ShardTools.CommandLine;
	import std.typecons;
	import ShardTools.Reflection;
import std.ascii;
import std.file;

	/// Provides a stand-alone wrapper that uses a FileStore to keep track of assets.
	void main(string[] args) { 
		//PathTools.SetWorkingDirectory(PathTools.ApplicationDirectory);
		// TODO: Add support for things like --help add.
		Standalone instance;
		try {
			instance = getCommandLineOptions!Standalone(args);
		} catch(CommandLineException) {
			// Do nothing since we allow CommandLine to handle outputting errors it throws.
		}
		/+
		 + Format:
		 + dap --add Textures/MyTexture.png
		 + Added asset Textures:MyTexture.png
		 + 	Context Processor:	TextureProcessor
		 + 	Resize to pow2:		true
		 + 	Generate Mipmaps:	true
		 + File not found: Textures/MyTexture.png
		 + Added asset Textures:MyTexture.png
		 + 	Content Processor:	Unknown
		 + Asset Textures:MyTexture already exists.
		 + (Above gets shown with dap --view as well.)
		 + (Perhaps specify --quiet to not output the above with add?)
		 +/
		/+foreach(val; params.metadata.children.values)
			writeln(val.name, " = ", val.getValue(params).text);
		auto logger = new ConsoleLogger();
		logger.minSeverity = MessageSeverity.Trace;
		auto context = new BuildContext(logger);
		auto assetStore = new FileStore(inputFolder, outputFolder, "standalone", context);
		logger.trace("Input Path: ", inputFolder);
		logger.trace("Output Path: ", outputFolder);
		assetStore.load();
		assert(context.getStore("standalone") == assetStore);
		auto testDoc = context.getNode("standalone:test.txt");
		writeln(testDoc.settings.get!(Vector3f)("Test"));+/
		/+logger.logMessage(MessageSeverity.Info, "This is a test message!", assetStore);
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
		assetStore.save();+/
	}

	class Standalone {
		@Description("The folder that assets should be read from and settings stored in.")
		@DisplayName("input-folder")
		@ShortName('i')
		string inputFolder = buildPath("Content", "Input");

		@Description("The folder that generated assets should be saved to.")
		@DisplayName("output-folder")
		@ShortName('o')
		string outputFolder = buildPath("Content", "Output");

		@Description("The minimum severity for a message to be logged.")
		@ShortName('l')
		@DisplayName("log-level")
		MessageSeverity severity = MessageSeverity.trace;

		@Description("Displays the help string.")
		@ShortName('h')
		@Command(CommandFlags.setDefault)
		string help() {
			string helpText = "D Asset Pipeline" ~ newline;
			helpText ~= "Converts assets into an intermediate post-processed format more efficiently loaded at runtime.";
			helpText ~= newline ~ getHelpString!Standalone;
			return helpText;
		}

		@Description("Adds the given raw asset to the asset store using the default processor and default settings.")
		@Command(CommandFlags.allowMulti | CommandFlags.argRequired)
		string add(string arg) {
			string assetPath = PathTools.MakeAbsolute(buildPath(_assetStore.inputDirectory, arg));
			if(!exists(assetPath))
				return "The asset at " ~ assetPath ~ " did not exist.";
			if(!PathTools.IsInWorkingDirectory(assetPath))
				return "The given asset was not in the current working directory.";
			string relPath = PathTools.GetRelativePath(assetPath, _assetStore.inputDirectory);
			string assetName = HierarchyNode.nameFromPath(relPath);
			Asset asset = _assetStore.registerAsset(assetName);
			_assetStore.save();
			return "Registered asset " ~ asset.qualifiedName ~ ".";
		}

		@CommandInitializer(true)
		void initialize() {
			auto logger = new ConsoleLogger();
			logger.minSeverity = MessageSeverity.info;
			auto context = new BuildContext(logger);
			this._assetStore = new FileStore(inputFolder, outputFolder, "Content", context);
			logger.trace("Input Path: " ~ inputFolder);
			logger.trace("Output Path: " ~ outputFolder);
			_assetStore.load();
		}
	
		private BuildContext context;
		private FileStore _assetStore;
	}
}