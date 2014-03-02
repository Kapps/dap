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
	import ShardTools.BufferPool;
	import ShardTools.Buffer;
	import dap.NodeSettings;
	import std.path;
	import ShardTools.Udas;
	import ShardTools.CommandLine;
	import std.typecons;
	import ShardTools.Reflection;
	import std.algorithm;
	import std.range;
	import std.ascii;
	import std.file;
	import dap.ContentProcessor;
	import dap.ContentImporter;
	import dap.AssetBuilder;
	import core.time;
	import std.datetime;
	import std.exception;
	import std.variant;
	import vibe.vibe;
	import std.parallelism;

	/// Provides a stand-alone wrapper that uses a FileStore to keep track of assets.
	void main(string[] args) { 
		// TODO: Add support for things like --help add.
		runTask({
			Standalone instance;
			try {
				instance = getCommandLineOptions!Standalone(args);
			} catch(CommandLineException) {
				// Do nothing since we allow CommandLine to handle outputting errors it throws.
			} catch (Exception e) {
				writeln(e);
			}
			//exitEventLoop(true);
		});
		runEventLoop();
		taskPool.finish();
	}

	class Standalone {
		@Description("The folder that assets should be read from and settings stored in.")
		@DisplayName("input-folder")
		string inputFolder = buildPath("Content", "Input");

		@Description("The folder that generated assets should be saved to.")
		@DisplayName("output-folder")
		string outputFolder = buildPath("Content", "Output");

		@Description("The minimum severity for a message to be logged.")
		@DisplayName("log-level")
		MessageSeverity severity = MessageSeverity.info;

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
		@ShortName('a')
		string add(string arg) {
			string[] matches = dirEntries(_assetStore.inputDirectory, SpanMode.breadth, false)
				.filter!(c=>c.isFile).map!(c=>cast()PathTools.GetRelativePath(c.name, _assetStore.inputDirectory))
				.filter!(c=>globMatch(c, arg)).array;
			if(matches.empty)
				return "No raw assets matched the specified glob.";
			string resultMessage;
			foreach(assetPath; matches) {
				if(!PathTools.IsInWorkingDirectory(assetPath))
					return "A matched asset was not in the current working directory.";
				string ext = extension(assetPath);
				string relPath = PathTools.GetRelativePath(assetPath, _assetStore.inputDirectory);
				string assetName = HierarchyNode.nameFromPath(relPath);
				if(context.getNode(_storeName ~ ":" ~ assetName) !is null) {
					resultMessage ~= "Skipped already existing matched asset " ~ assetName ~ ".\r\n";
					continue;
				}
				Asset asset = _assetStore.registerAsset(assetName, ext);
				resultMessage ~= "Registered asset " ~ asset.qualifiedName ~ ".\r\n" ~ getInspectString(asset) ~ "\n\n";
			}
			_assetStore.save();
			return resultMessage.stripRight();
		}

		@Description("Removes the asset with the specified qualified name from the asset store.")
		@Command(CommandFlags.allowMulti | CommandFlags.argRequired)
		@ShortName('r')
		string remove(string arg) {
			if(!arg.startsWith("Content:") && !arg.startsWith("*"))
				arg = "Content:" ~ arg;
			Asset[] matches = _assetStore.allAssets.filter!(c=>cast(Asset)c)
				.filter!(c=>globMatch(c.qualifiedName, arg)).array;
			if(matches.empty)
				return "No assets matched the specified glob.";
			string result;
			foreach(node; matches) {
				node.parent.children.remove(node);
				result ~= node.text ~ " was removed from the asset store.\n";
			}
			_assetStore.save();
			return result.stripRight();
		}

		@Description("Lists all assets currently stored.")
		@Command(true)
		@ShortName('l')
		string list() {
			auto result = appender!string;
			appendContainer(_assetStore, 1, result);
			return std.string.strip(result.data);
		}

		@Description("Builds all dirty assets using current settings.")
		@Command(true)
		@ShortName('b')
		string build() {
			StopWatch sw = StopWatch(AutoStart.yes);
			auto builder = new AssetBuilder();
			builder.build(context);
			return "Build complete. Elapsed time was " ~ (cast(Duration)sw.peek).text ~ ".";
		}

		@Description("Shows all properties of the given asset.")
		@Command(true)
		@ShortName('i')
		string inspect(string arg) {
			auto node = getAsset(arg);
			return getInspectString(node);
		}

		@Description("Modifies a property of a processor on an asset, or the processor used to build the asset.")
		@Command(true)
		@ShortName('m')
		string modify(string arg, string[] params) {
			enum string PROCESSOR_KEY = "processor";
			// args_ to prevent ParameterDefaultValueTuple from failing to compile and thus reflection not being generated.
			if(params.length == 0) {
				return "Expected parameters to modify the asset with.\r\nValid parameters are \"" ~ PROCESSOR_KEY ~ "\""
					~ "to change the processor used or any parameter shown with inspect to change a processor property.";
			}
			auto node = getAsset(arg);
			auto processor = node.createProcessor();
			import std.string;
			foreach(param; params) {
				size_t indexEq = param.countUntil("=");
				if(indexEq == -1)
					continue;
				if(indexEq == param.length - 1)
					return "Expected a value after = token.";
				string key = param[0..indexEq].strip;
				string val = param[indexEq + 1 .. $];
				// Handle special built-in parameters.
				if(key == PROCESSOR_KEY) {
					if(ContentProcessor.create(val, node) is null)
						return "No processor was found named " ~ val ~ ".";
					node.processorName = val;
				} else {
					if(processor is null)
						return "A processor must be set prior to setting any values except " ~ PROCESSOR_KEY ~ ".";
					auto split = key.split(".");
					enforce(split);
					ValueMetadata curr;
					Variant obj = processor;
					foreach(index, part; split) {
						curr = obj.metadata.findValue(part);
						if(curr == ValueMetadata.init)
							return "No value named " ~ part ~ " was found on " ~ split[0..index].join(".").text ~ ".";
						if(index != split.length - 1)
							obj = curr.getValue(obj);
					}
					if(!curr.canSet)
						return "The value of " ~ curr.name ~ " is read-only.";
					Variant parsedVal;
					try
						parsedVal = curr.type.metadata.coerceFrom(val);
					catch
						return "Unable to convert " ~ val ~ " to " ~ curr.type.metadata.name ~ ".";
					curr.setValue(obj, parsedVal);
					processor.saveSettings();
				}
			}
			_assetStore.save();
			return getInspectString(node);
		}

		private string getInspectString(Asset node) {
			auto processor = node.createProcessor();
			auto importer = processor is null ? null : processor.createImporter();
			Appender!string result;
			result ~= "Importer: " ~ (importer is null ? "Unknown" : typeid(importer).text) ~ "\n";
			result ~= "Processor: " ~ node.processorName ~ "\n";
			if(processor !is null) {
				foreach(prop; processor.metadata.children.values.filter!(c=>c.kind == DataKind.property))
					appendProperty(prop, prop.getValue(processor), 1, result);
			} else {
				result ~= "\tInvalid Processor";
			}
			return std.string.stripRight(result.data);
		}

		private Asset getAsset(string arg) {
			string name = std.string.strip(arg);
			if(!std.string.toLower(name).startsWith(std.string.toLower(_storeName ~ nodeSeparator)))
				name = _storeName ~ nodeSeparator ~ name;
			auto node = cast(Asset)context.getNode(name);
			if(node is null)
				throw new ValidationException("No asset with the fully qualified name of '" ~ name ~ "' was found.");
			return node;
		}

		private void appendProperty(ValueMetadata metadata, Variant val, int indentLevel, ref Appender!string result) {
			if(metadata.propertyData.getter.findAttribute!Ignore(false))
				return;
			string indentString = repeat('\t', indentLevel).array;
			TypeMetadata type = val.metadata;
			// Didn't bother with recursive yet, have to implement making sure we're not running into
			// an infinite loop or stack overflow, and need a way to indicate something is a reference
			// to another instance that was already printed out, etc.

			//if(type.kind == TypeKind.primitive_)
				result ~= indentString ~ metadata.name ~ " = " ~ val.text ~ "\n";
			/+else {
				result ~= indentString ~ metadata.name ~ ":\n";
				// Can't find a better way to check if it contains null....
				bool isNull = cast(ClassInfo)val.type && val.coerce!Object is null;
				if(isNull)
					result ~= indentString ~ "\tnull";
				else {
					writeln("Currently value is ", val, ". ");
					foreach(child; type.children.values)
						appendProperty(child, child.getValue(val), indentLevel + 1, result);
				}
			}+/
		}

		private void appendContainer(HierarchyNode node, int indentLevel, ref Appender!string result) {
			string indentString = repeat('\t', indentLevel).array;
			result ~= (indentString[0..$-1] ~ node.name ~ ":\n");
			foreach(asset; node.children.allNodes.filter!(c=>cast(Asset)c)) {
				result ~= (indentString ~ asset.name ~ "\n");
			}
			foreach(child; node.children.allNodes.filter!(c=>cast(Asset)c is null)) {
				appendContainer(child, indentLevel + 1, result);
			}
		}

		@CommandInitializer(true)
		void initialize() {
			auto logger = new ConsoleLogger();
			logger.minSeverity = severity;
			context = new BuildContext(logger);
			this._assetStore = new FileStore(inputFolder, outputFolder, _storeName, context);
			logger.trace("Input Path: " ~ inputFolder);
			logger.trace("Output Path: " ~ outputFolder);
			_assetStore.load();
		}
	
		private BuildContext context;
		private FileStore _assetStore;
		private string _storeName = "Content";
	}
}