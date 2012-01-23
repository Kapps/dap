module ShardIO.DataTransformer;

enum TransformMode {
	Unknown = 0,
	Write = 1,
	Read = 2
}

/// An object used to operate on data by performing a transform operation on it.
/// Multiple transformers may operate on the same set of data, so a (constant) priority property is enforced.
/// The result is that transformers can be combined, for example having an SslTransformer encrypt the results of a DeflateTransformer.
/// Transforms are done in low-to-high priority for writes, and high-to-low for reads.
abstract class DataTransformer  {

public:
	/// Initializes a new instance of the DataTransformer object.	
	this(int Priority) {
		this._Priority = Priority;
	}

	/// Gets the priority of this DataTransformer. This value is constant per object.
	/// A transformer with a lower priority will operate on the data first for reads and last for writes.
	/// A value of 0 is a neutral priority, for a transformer that does not care about ordering.
	@property int Priority() const {
		return _Priority;
	}

	/// Transforms the given buffer, returning the result of the transformation.
	/// The result may or may not be the same instance of Buffer that was passed in.
	/// The result must not be a slice of the original buffer, unless it is the original buffer.
	/// Params:
	/// 	Buffer = The data to transform.
	/// 	Mode = Whether to transform for a read, or a write.
	abstract ubyte[] Transform(ubyte[] Buffer, TransformMode Mode);
	
private:
	int _Priority;
}