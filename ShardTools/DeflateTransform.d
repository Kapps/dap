module ShardTools.DeflateTransform;
private import ShardTools.Compressor;
private import ShardTools.DataTransformer;


/// A DataTransformer used to compress or decompress data with the Deflate algorithm.
class DeflateTransform : DataTransformer {

public:
	/// Initializes a new instance of the DeflateTransform object.
	this(int Priority = 100) {
		super(Priority);
	}

	/// Transforms the given buffer, returning the result of the transformation.
	/// The result may or may not be the same instance of Buffer that was passed in.
	/// The result must not be a slice of the original buffer, unless it is the original buffer.
	/// Params:
	/// 	Buffer = The data to transform.
	/// 	Mode = Whether to transform for a read, or a write.
	override ubyte[] Transform(ubyte[] Buffer, TransformMode Mode) {
		return cast(ubyte[])Compressor.ToDeflate(Buffer, false);
	}
	
private:
}