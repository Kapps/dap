module dap.processors.TextureProcessor;
import dap.ContentProcessor;
public import dap.TextureContent;
import ShardTools.SignaledTask;

/// Provides a ContentProcessor to import various image or texture types.
/// Format:
/// 	[uint] width [uint] height
/// 	[Color(width*height)] pixels
class TextureProcessor : ContentProcessor {

	mixin(makeProcessorMixin("Texture Processor", ["png", "jpg", "jpeg", "gif", "tiff", "raw", "tga"]));

	this(Asset asset) {
		super(asset);
	}

	/// Overrides to set the input type to TextureContent.
	@Ignore(true) @property override TypeInfo inputType() {
		return typeid(TextureContent);
	}
	
	protected override AsyncAction performProcess(Untyped input, OutputSource output) {
		TextureContent content = input.get!TextureContent;
		auto range = content.createPixelRange(Untyped(content), &consumeData);
		std.stdio.writeln("Created range.");
		return range.Start();
	}

	private void consumeData(Untyped state, Color[] data, ConsumerCompletionCallback callback) {
		std.stdio.writeln("Consuming ", data.length, " elements.");
		callback();
	}
}

