﻿module dap.processors.TextureProcessor;
import dap.ContentProcessor;
public import dap.TextureContent;
import ShardTools.SignaledTask;
import ShardIO.StreamInput;
import ShardTools.ImmediateAction;
import ShardTools.ExceptionTools;

/// A bitwise enum of texture format data.
enum TextureFormat : ubyte {
	color = 0
}

/// Provides a ContentProcessor to import various image or texture types.
/// Format:
/// 	[TextureFormat] format
/// 	[uint] width [uint] height
/// 	(format = color) ->
/// 		[Color(width*height)] pixels
class TextureProcessor : ContentProcessor {

	mixin(makeProcessorMixin("Texture Processor", ["png", "jpg", "jpeg", "gif", "tiff", "raw", "tga", "bmp"]));

	/// Gets or sets the format of the texture.
	/// Color is the most efficient to load at runtime, but takes up the most space.
	@property TextureFormat format() const @safe pure nothrow {
		return _format;
	}

	/// ditto
	@property void format(TextureFormat val) @safe nothrow {
		_format = val;
	}

	this(Asset asset) {
		super(asset);
	}

	/// Overrides to set the input type to TextureContent.
	@Ignore(true) @property override TypeInfo inputType() {
		return typeid(TextureContent);
	}

	protected override AsyncAction performProcess(Untyped untypedInput, OutputSource output) {
		TextureContent content = untypedInput.get!TextureContent;
		this.input = new StreamInput(FlushMode.Manual);
		if(content.width > ushort.max || content.height > ushort.max)
			throw new NotSupportedException("Textures with a width or height over 65535 pixels are not supported.");
		auto action = new IOAction(input, output).Start();
		TextureFormat format = TextureFormat.color;
		input.Write(cast(ubyte)format);
		input.Write(cast(ushort)content.width);
		input.Write(cast(ushort)content.height);
		auto range = content.createPixelRange(Untyped(content), &consumeData);
		range.Start();
		return action;
	}

	// Save as BMP to test with. May have bugs...
	/*protected override AsyncAction performProcess(Untyped input, OutputSource output) {
		TextureContent content = input.get!TextureContent;
		this.input = new StreamInput(FlushMode.Manual());
		ubyte[14] fileHeader = cast(ubyte[])[
			cast(ubyte)'B', cast(ubyte)'M', 
			0, 0, 0, 0, 
			0, 0, 
			0, 0, 
			54, 0, 0, 0
		];
		ubyte[40] infoHeader = cast(ubyte[])[
			40, 0, 0, 0,
			0, 0, 0, 0,
			0, 0, 0, 0,
			1, 0,
			24, 0,
			0, 0, 0, 0,
			0, 0, 0, 0,
			0x13, 0x0B, 0, 0,
			0x13, 0x0B, 0, 0,
			0, 0, 0, 0,
			0, 0, 0, 0
		];
		//ubyte[3] padding = cast(ubyte[])[0, 0, 0];
		uint padSize = (4 - content.width % 4) % 4;
		uint sizeData = content.width * content.height * 3 + (content.height * padSize);
		uint size = 54 + sizeData;
		uint width = cast(uint)content.width;
		uint height = cast(uint)content.height;
		fileHeader[2] = cast(ubyte)(size);
		fileHeader[3] = cast(ubyte)(size >> 8);
		fileHeader[4] = cast(ubyte)(size >> 16);
		fileHeader[5] = cast(ubyte)(size >> 24);
		infoHeader[4] = cast(ubyte)(width);
		infoHeader[5] = cast(ubyte)(width >> 8);
		infoHeader[6] = cast(ubyte)(width >> 16);
		infoHeader[7] = cast(ubyte)(width >> 24);
		infoHeader[8] = cast(ubyte)(height);
		infoHeader[9] = cast(ubyte)(height >> 8);
		infoHeader[10] = cast(ubyte)(height >> 16);
		infoHeader[11] = cast(ubyte)(height >> 24);
		infoHeader[24] = cast(ubyte)(sizeData);
		infoHeader[25] = cast(ubyte)(sizeData >> 8);
		infoHeader[26] = cast(ubyte)(sizeData >> 16);
		infoHeader[27] = cast(ubyte)(sizeData >> 24);
		this.input.Write(fileHeader[]);
		this.input.Write(infoHeader[]);
		this.input.Flush();
		auto range = content.createPixelRange(Untyped(content), &consumeData);
		std.stdio.writeln("Created range.");
		range.Start();
		return new IOAction(this.input, output).Start();
	}*/

	/*private void consumeData(Untyped state, Color[] data, ProducerStatus status, ConsumerCompletionCallback callback) {
		// TODO: Try writing a BMP to test with.
		std.stdio.writeln("Consuming ", data.length, " elements with status of ", status, ".");
		foreach(pixel; data) {
			ubyte[] pixels = [pixel.B, pixel.G, pixel.R];
			input.Write(pixels);
		}
		if(status == ProducerStatus.complete) {
			ubyte[] padding = cast(ubyte[])[0, 0, 0];
			input.Write(padding);
			input.Complete();
		}
		input.Flush();
		callback();
	}*/

	private void consumeData(Untyped state, Color[] data, ProducerStatus status, ConsumerCompletionCallback callback) {
		assert(format == TextureFormat.color);
		TextureContent content = state.get!TextureContent;
		input.Write(data);
		input.Flush();
		if(status == ProducerStatus.complete)
			input.Complete();
		callback();
	}

	@Ignore(true) StreamInput input;
	TextureFormat _format;
}
