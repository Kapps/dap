/// Provides an importer for handling images in various formats.
module dap.TextureContent;
public import ShardTools.AsyncRange;
public import dap.ContentImporter;
public import ShardTools.Color;
import ShardTools.AsyncAction;
import ShardIO.IOAction;
import ShardTools.Untyped;

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
	AsyncRange!Color createPixelRange(Untyped consumerState, void delegate(Untyped, Color[], ConsumerCompletionCallback) consumer) {
		return new AsyncRange!Color(_producer, _producerState, consumer, consumerState);
	}

	/// Creates a new TextureContent instance with the given properties.
	this(uint width, uint height, Untyped producerState, void delegate(Untyped, ProducerCompletionCallback) producer) {
		this._width = width;
		this._height = height;
		this._producer = producer;
		this._producerState = producerState;
	}

private:
	uint _width, _height;
	void delegate(Untyped, ProducerCompletionCallback) _producer;
	Untyped _producerState;
}