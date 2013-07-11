/// To be removed. Do not use.
module ShardTools.StreamWriter;

/// A helper class used to write to a stream.
@disable class StreamWriter  {

public:
	/// Initializes a new instance of the StreamWriter object.
	/// Params:
	/// 	Capacity = The initial number of bytes the writer is capable of storing prior to a resize.
	this(size_t Capacity) {
		this._Capacity = Capacity;
		this._Length = 0;
		this._Data = (new ubyte[Capacity]).ptr;
	}

	/// Gets the data being written to.
	/// Storing this value is an invalid operation, as it may be modified and/or reallocated after this call.
	@property ubyte[] Data() {
		return _Data[0..Length];
	}

	/// Gets the size of the data contained in this stream.
	@property size_t Length() {
		return _Length;
	}

	/// Gets the number of bytes the stream is capable of storing prior to a resize.
	@property size_t Capacity() {
		return _Capacity;
	}

	/// Writes the given data to the stream.
	/// Params:
	/// 	T = The type of Value. Must be a struct, primitive, or array of these.
	/// 	Value = The vaue to write.
	void Write(T)(T Value) if(!is(T == class) && !is(T == interface)) {
		_Data ~= Value;
	}

	/// Writes the given array to the stream, with an integer (not size_t) prefix indicating the size.
	/// Params:
	/// 	T = The type of Value. Must be a struct, primitive, or array of these.
	/// 	Value = The array to write.
	void WritePrefixed(T)(T[] Value) if(!is(T == class) && !is(T == interface)) {
		Write(Value.length);
		Write(Value);
	}

	/// Writes a null-terminated array of T to the stream. That is, the array followed by T.init.
	/// Params:
	/// 	T = The type of the elements in the array. Must be a struct, primitive, or array of these.
	/// 	Value = The array to write.
	void WriteNullTerminated(T)(T[] Value) if(!is(T == class) && !is(T == interface)) {
		Write(Value);
		Write(T.init);
	}
	
private:
	ubyte* _Data;
	size_t _Length;
	size_t _Capacity;
}