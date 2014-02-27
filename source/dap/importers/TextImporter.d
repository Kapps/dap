module dap.importers.TextImporter;
import dap.ContentImporter;
import vibe.core.stream;
import dap.StreamOps;
import ShardTools.ImmediateAction;
import ShardTools.Untyped;
import ShardTools.SignaledTask;
import vibe.stream.memory;

/// An importer that returns any asset as a TextContent instance or string without any processing.
class TextImporter : ContentImporter {
	static this() {
		ContentImporter.register(new TextImporter());
	}

	override bool canProcess(string extension, TypeInfo requestedType) {
		return requestedType == typeid(string) || requestedType == typeid(TextContent);
	}

	override Untyped performProcess(ImportContext context) {
		auto input = context.input;
		if(context.requestedType == typeid(TextContent)) {
			return Untyped(TextContent(input));
		} else if(context.requestedType == typeid(string)) {
			MemoryOutputStream output = new MemoryOutputStream();
			output.write(input, 0);
			output.finalize();
			return Untyped(cast(string)output.data);
		} else
			assert(0);
	}
}

/// Provides the output of a TextImporter, allowing streaming access from a text file.
struct TextContent {
	this(InputStream input) {
		this._input = input;
	}

	/// An InputSource containing the raw input for the text file.
	@property InputStream input() {
		return _input;
	}

	private InputStream _input;
}
