module dap.TextProcessor;
import dap.ContentProcessor;
import ShardIO.OutputSource;
import std.variant;
import dap.TextImporter;

/// Provides a ContentProcessor that can output a raw text file.
/// This is generally used for only raw text assets. For structured file 
/// types, such as JSON or XML, it is generally recommended to use the
/// SerializedProcessor instead for more efficient storage and loading.
class TextProcessor : ContentProcessor {

	mixin(makeProcessorMixin("Text Processor", ["txt"]));

	this(Asset asset) {
		super(asset);
	}

	/// Indicates if the lines within the text file should be reversed.
	/// At the moment this does nothing and is just a test property.
	@property bool reverseLines() const {
		return _reverseLines;
	}

	/// ditto
	@property void reverseLines(bool val) {
		_reverseLines = val;
	}

	@Ignore(true) @property override TypeInfo inputType() {
		return typeid(string);
	}

	protected override AsyncAction performProcess(Untyped input, OutputSource output) {
		TextContent content = input.get!TextContent;
		auto res = new IOAction(content.input, output);
		res.Start();
		return res;
	}
	
private:
	bool _reverseLines;
}

