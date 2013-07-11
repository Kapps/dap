module ShardIO.DeflateTransform;
private import ShardTools.Compressor;
private import ShardIO.DataTransformer;
private import std.zlib;

/// A DataTransformer used to compress or decompress data with the Deflate algorithm.
/// Currently disabled because it operates individually on each request, as opposed to acting as a larger stream as a DataTransformer should.
@disable class DeflateTransform : DataTransformer {

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
		if(Mode == TransformMode.Write)
			return cast(ubyte[])Compressor.ToDeflate(Buffer, false);
		else
			return cast(ubyte[])uncompress(Buffer);
	}
	
private:
}