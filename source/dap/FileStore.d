module dap.FileStore;
public import dap.AssetStore;
public import dap.Asset;
import core.sync.mutex;
import ShardIO.FileOutput;
import ShardIO.StreamInput;
import std.algorithm;
import ShardIO.FileInput;
import std.path;
import std.conv;
import ShardTools.PathTools;
import std.file;

// TODO: Either here or in an ArchivedFileStore allow packing assets into a single archive.
// For example, a sound archive, texture archive, etc.
// Alternatively, just make an ArchivedStore(T), which would likely make more sense.
// After all, perhaps you want to send the archive over the network or something (maybe useful for updaters?).

/// Provides a basic implementation of AssetStore used to read or write assets directly to/from a file-system.
class FileStore : AssetStore {

	private enum string COMPILED_EXTENSION = "sca";

	/// Creates a new FileStore with the given settings.
	/// Params:
	///		identifier = The name of this AssetStore.
	///		context    = Provides information abut the build and means of accessing other assets.
	///	 	settings   = Provides access to settings of individual assets.
	this(string inputDirectory, string outputDirectory, string identifier, BuildContext context) {
		assert(inputDirectory && outputDirectory);
		super(identifier, context);
		this._inputDirectory = PathTools.MakeAbsolute(inputDirectory);
		this._outputDirectory = PathTools.MakeAbsolute(outputDirectory);
	}
	
	/// Indicates the directory to read assets from.
	@property string inputDirectory() const {
		return _inputDirectory;
	}
	
	/// Indicates the directory to write compiled assets to.
	@property string outputDirectory() const {
		return _outputDirectory;
	}

	@property string settingsFile() {
		return buildPath(inputDirectory, name ~ "-settings.sas");
	}

	override InputSource createInputSource(Asset asset) {
		auto path = getAbsolutePath(this.inputDirectory, asset) ~ "." ~ asset.extension;
		trace("Creating input source for " ~ asset.text ~ " from " ~ getRelativePath(asset));
		return new FileInput(path);
	}

	override OutputSource createOutputSource(Asset asset) {
		auto path = getAbsolutePath(this.outputDirectory, asset) ~ "." ~ COMPILED_EXTENSION;
		trace("Creating output source for " ~ asset.text ~ " to " ~ getRelativePath(asset));
		string dir = dirName(path);
		if(!exists(dir)) {
			trace("Output directory did not exist; creating it.");
			mkdirRecurse(dir);
		}
		return new FileOutput(path, FileOpenMode.CreateOrReplace);
	}
	
	protected override void performSave() {
		trace("Setting location will be '" ~ settingsFile ~ "'.");
		FileOutput output = new FileOutput(settingsFile, FileOpenMode.CreateOrReplace);
		trace("Created output file.");
		serializeNodes(output);
		trace("Done performSave.");
	}

	protected override void performLoad() {
		trace("Loading settings from " ~ settingsFile ~ ".");
		if(!exists(settingsFile)) {
			info("Settings file did not exist. Using default data.");
			return;
		}
		FileInput input = new FileInput(settingsFile);
		trace("Prepared input file.");
		deserializeNodes(input);
		trace("Done performLoad.");
	}

	protected string getAbsolutePath(string basePath, Asset asset) {
		string relative = getRelativePath(asset);
		string abs = buildPath(basePath, relative);
		return abs;
	}

	/// Returns the relative path for the given asset.
	protected string getRelativePath(Asset asset) {
		// Note that this does not include the store name.
		return buildPath(HierarchyNode.splitQualifiedName(asset.qualifiedName)[1..$]);
	}
	
	Asset[string] loadedAssets;
	Mutex assetLock;
	string _inputDirectory;
	string _outputDirectory;
}

