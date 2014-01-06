/// Provides an importer for handling images in various formats.
module dap.TextureImporter;
public import ShardTools.AsyncRange;
public import dap.ContentImporter;
public import ShardTools.Color;
import ShardTools.AsyncAction;
import ShardIO.IOAction;

/// Provides content information for a texture, including a lazy buffered stream to generate pixel data.
class TextureContent {

	/// Gets the width or height of the underlying texture.
	@property uint width() const pure @safe nothrow {
		return _width;
	}

	/// ditto
	@property uint height() const pure @safe nothrow {
		return _height;
	}

	/// Creates an AsyncRange to read Color data from the image (ordered from top-left to bottom-right).
	/// The AsyncRange must be started in order to begin reading pixels.
	AsyncRange!Color createPixelRange(void delegate(Color[], ConsumerCompletionCallback) consumer) {
		return new AsyncRange!Color(_producer, consumer, 1024);
	}

	/// Creates a new TextureContent instance with the given properties.
	this(uint width, uint height, void delegate(RangeBuffer!Color, ProducerCompletionCallback) producer) {
		this._width = width;
		this._height = height;
		this._producer = _producer;
	}

private:
	uint _width, _height;
	void delegate(RangeBuffer!Color, ProducerCompletionCallback) _producer;
}

/// Provides the base class for a ContentImporter to read textures.
abstract class TextureImporter : ContentImporter {

	override bool canProcess(string extension, TypeInfo requestedType) {
		return requestedType == typeid(TextureContent);
	}

	override AsyncAction performProcess(InputSource input, string extension, TypeInfo requestedType) {
		return createContentAction(input, extension);
	}

	/// Override to return an AsyncAction that, upon completion, contains a TextureContent instance as its completion data.
	abstract AsyncAction createContentAction(InputSource input, string extension);
}

