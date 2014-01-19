module dap.ContentImporter;
import ShardIO.InputSource;
import dap.Asset;
import std.string;
import std.path;
import std.traits;
import ShardTools.ExceptionTools;
import ShardTools.CaoList;
public import dap.BuildContext;

/// Provides an importer that can be used to read assets in a variety of formats.
/// The results of the importer are then handled by a ContentProcessor.
/// Each importer instance may be used multiple times, potentially concurrently.
/// Importers must be registered through the $(D ContentImporter.register) method.
/// Generally an importer should register an instance of itself in it's static constructor.
abstract class ContentImporter {

	/// Returns an instance of a ContentImporter that reports it can handle
	/// generating requestedType for the given extension.
	/// If no importer reports it can generate this data, null is returned.
	static ContentImporter findImporter(string extension, TypeInfo requestedType) {
		foreach(importer; _allImporters) {
			if(importer.canProcess(extension, requestedType))
				return importer;
		}
		return null;
	}

	/// Registers the given importer, allowing it to be used for processing.
	/// Importers may not be unregistered once registered.
	static void register(ContentImporter importer) {
		_allImporters.push(importer);
	}

	/// Processes the raw asset with the given input. Once the importer has
	/// sufficient data to begin the import, the AsyncAction returned is
	/// completed and the CompletionData contains an instance of requestedType.
	/// If the importer fails to create the data, an error is automatically logged.
	final AsyncAction process(ImportContext context) {
		string fixedExt = fixedExtension(context.extension);
		if(!canProcess(fixedExt, context.requestedType))
			throw new NotSupportedException("This importer is unable to process the given data.");
		AsyncAction result = performProcess(context);
		return result;
	}

	/// Override to indicate whether this import can handle importing
	/// content with the given file extension to return an instance of requestedType.
	/// Extension is always lower-case and does not include the leading dot, but TypeInfo may be qualified.
	abstract bool canProcess(string extension, TypeInfo requestedType);	

	/// Override to process the given raw input, returning an instance of requestedType.
	/// It is guaranteed that canProcess is true for (extension, requestedType).
	/// Extension is always lower-case, but TypeInfo may be qualified.
	/// The result of the action $(B must) be an instance of requestedType if the action is successful.
	/// If the action is aborted, an error is logged and this asset is skipped.
	abstract AsyncAction performProcess(ImportContext context);

	private string fixedExtension(string extension) {
		return extension.toLower.strip();
	}

	private __gshared CaoList!(ContentImporter) _allImporters;
}

/// Provides context information used to import an asset.
struct ImportContext {

	/// The InputSource used to read raw asset data from.
	@property InputSource input() @safe pure nothrow {
		return _input;
	}

	/// The extension, and thus format, of the raw asset data.
	@property string extension() const @safe pure nothrow {
		return _extension;
	}

	/// The type that the returned action should contain as its CompletionData.
	@property TypeInfo requestedType() @safe pure nothrow {
		return _requestedType;
	}

	/// The BuildContext being used that requested this import.
	@property BuildContext buildContext() @safe pure nothrow {
		return _buildContext;
	}

	/// The asset that is being built.
	@property Asset asset() @safe pure nothrow {
		return _asset;
	}

	this(InputSource input, string extension, TypeInfo requestedType, BuildContext buildContext, Asset asset) {
		this._input = input;
		this._extension = extension;
		this._requestedType = requestedType;
		this._buildContext = buildContext;
		this._asset = asset;
	}

private:
	InputSource _input;
	string _extension;
	TypeInfo _requestedType;
	BuildContext _buildContext;
	Asset _asset;
}