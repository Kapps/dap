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

// TODO: Either here or in an ArchivedFileStore allow packing assets into a single archive.
// For example, a sound archive, texture archive, etc.
// Alternatively, just make an ArchivedStore(T), which would likely make more sense.
// After all, perhaps you want to send the archive over the network or something (maybe useful for updaters?).

/// Provides a basic implementation of AssetStore used to read or write assets directly to/from a file-system.
class FileStore : AssetStore {
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

	protected override InputSource createInputSource(Asset asset) {
		auto path = getAbsolutePath(this.inputDirectory, asset);
		trace("Creating output source for " ~ asset.text ~ " from " ~ getRelativePath(asset));
		return new FileInput(path);
	}

	protected override OutputSource createOutputSource(Asset asset) {
		auto path = getAbsolutePath(this.outputDirectory, asset);
		trace("Creating output source for " ~ asset.text ~ " to " ~ getRelativePath(asset));
		return new FileOutput(path);
	}
	
	protected override void performSave() {
		string filePath = buildPath(inputDirectory, identifier ~ "-settings.saf");
		trace("Setting location will be '" ~ filePath ~ "'.");
		FileOutput output = new FileOutput(filePath);
		trace("Created output file.");
		serializeNodes(output);
	}

	protected string getAbsolutePath(string basePath, Asset asset) {
		string relative = getRelativePath(asset);
		string abs = buildPath(basePath, relative);
		return abs;
	}

	/// Returns the relative path for the given asset.
	protected string getRelativePath(Asset asset) {
		return buildPath(asset.qualifiedName);
	}
	
	Asset[string] loadedAssets;
	Mutex assetLock;
	string _inputDirectory;
	string _outputDirectory;
}

