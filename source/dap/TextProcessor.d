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

	@Ignore(true) @property override TypeInfo inputType() {
		return typeid(TextContent);
	}

	protected override AsyncAction performProcess(Variant input, OutputSource output) {
		TextContent content = input.get!TextContent;
		return new IOAction(content.input, output);
	}
}

