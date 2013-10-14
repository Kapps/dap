module src.dap.ContentImporter;
import ShardIO.InputSource;
import dap.Asset;
import std.string;
import std.path;
import std.traits;
import ShardTools.ExceptionTools;
import ShardTools.CaoList;

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
	
	/// Processes the raw asset with the given input, returning an instance of T.
	final T process(T)(InputSource input, string extension) {
		return process!(T)(input, extension, type).get!(T);
	}

	/// Processes the raw asset with the given input, returning an instance of requestedType.
	final Variant process(InputSource input, string extension, TypeInfo requestedType) {
		string fixedExt = fixedExtension(extension);
		if(!canProcess(fixedExt, requestedType))
			throw new NotSupportedException("This importer is unable to process the given data.");
		Variant result = performProcess(input, fixedExt, requestedType);
		return result;
	}

	/// Override to indicate whether this import can handle importing
	/// content with the given file extension to return an instance of requestedType.
	/// Extension is always lower-case, but TypeInfo may be qualified.
	abstract bool canProcess(string extension, TypeInfo requestedType);	

	/// Override to process the given raw input, returning an instance of requestedType.
	/// It is guaranteed that canProcess is true for (extension, requestedType).
	/// Extension is always lower-case, but TypeInfo may be qualified.
	abstract Variant performProcess(InputSource input, string extension, TypeInfo requestedType);

	private string fixedExtension(string extension) {
		return extension.toLower.strip();
	}

	private __gshared CaoList!(ContentImporter) _allImporters;
}