module dap.TextImporter;
import dap.ContentImporter;
import ShardIO.MemoryOutput;
import ShardIO.IOAction;

/// An importer that returns any asset as a TextContent instance or string without any processing.
class TextImporter : ContentImporter {
	static this() {
		ContentImporter.register(new TextImporter());
	}

	override bool canProcess(string extension, TypeInfo requestedType) {
		return requestedType == typeid(string) || requestedType == typeid(TextContent);
	}

	override Variant performProcess(InputSource input, string extension, TypeInfo requestedType) {
		if(requestedType == typeid(TextContent))
			return Variant(TextContent(input));
		else if(requestedType == typeid(string)) {
			MemoryOutput output = new MemoryOutput();
			IOAction action = new IOAction(input, output);
			action.Start();
			action.WaitForCompletion();
			string result = cast(string)output.Data;
			return Variant(result);
		} else
			assert(0);
	}
}

/// Provides the output of a TextImporter, allowing streaming access from a text file.
struct TextContent {
	this(InputSource input) {
		this._input = input;
	}

	/// An InputSource containing the raw input for the text file.
	@property InputSource input() {
		return _input;
	}

	private InputSource _input;
}
