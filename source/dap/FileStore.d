module dap.FileStore;
public import dap.AssetStore;
public import dap.Asset;
import core.sync.mutex;
import vibe.core.stream;
import vibe.stream.zlib;
import vibe.core.file;
import std.algorithm;
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

	/// Indicates the file extension for compiled assets.
	public enum string COMPILED_EXTENSION = "sca";

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

	/// Returns the path to the file that is used as the raw input file for this asset on the disk.
	string getPathForRawAsset(Asset asset) {
		return getAbsolutePath(this.inputDirectory, asset) ~ "." ~ asset.extension;
	}

	/// Returns the path to the output file that results from building this asset.
	string getPathForBuiltAsset(Asset asset) {
		return getAbsolutePath(this.outputDirectory, asset) ~ "." ~ COMPILED_EXTENSION;
	}

	override InputStream createInputStream(Asset asset) {
		auto path = getPathForRawAsset(asset);
		trace("Creating input source for " ~ asset.text ~ " from " ~ getRelativePath(asset));
		return openFile(path, FileMode.read);
	}

	override OutputStream createOutputStream(Asset asset) {
		auto path = getPathForBuiltAsset(asset);
		trace("Creating output source for " ~ asset.text ~ " to " ~ getRelativePath(asset));
		string dir = dirName(path);
		if(!exists(dir)) {
			trace("Output directory did not exist; creating it.");
			mkdirRecurse(dir);
		}
		OutputStream fs = openFile(path, FileMode.createTrunc);
		return new ZlibOutputStream(fs, ZlibOutputStream.HeaderFormat.deflate);
	}
	
	protected override void performSave() {
		trace("Setting location will be '" ~ settingsFile ~ "'.");
		FileStream output = openFile(settingsFile ~ ".tmp", FileMode.createTrunc);
		{
			scope(exit) {
				output.finalize();
				output.close();
			}
			trace("Created output file.");
			serializeNodes(output);
		}
		trace("Done saving temporary output; replacing original settings file.");
		moveFile(settingsFile ~ ".tmp", settingsFile);
		trace("Done performSave.");
	}

	protected override void performLoad() {
		trace("Loading settings from " ~ settingsFile ~ ".");
		if(!exists(settingsFile)) {
			info("Settings file did not exist. Using default data.");
			return;
		}
		FileStream input = openFile(settingsFile, FileMode.read);
		scope(exit)
			input.close();
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

