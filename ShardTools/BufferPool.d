module ShardTools.BufferPool;
public import ShardTools.Buffer;
private import ShardTools.SortedList;
public import std.outbuffer;
private import std.container;

/// Provides access to a pool of reuseable buffers.
@disable class BufferPool  {

public:

	static this() {
		_Global = new BufferPool(1024 * 1024 * 32); // 32 megabytes max by default seems safe.
	}

	/// Initializes a new instance of the BufferPool object.	
	this(size_t MaxSize) {
		this._MaxSize = MaxSize;
		Buffers = new BufferList();
	}

	/// Gets a global BufferPool to be used.
	@property static BufferPool Global() {
		return _Global;
	}

	/// Gets or sets the maximum size, in bytes, of the buffers that the pool holds. If buffers are resized past this size, they get split upon release.
	/// Changes will not take effect immediately, but the pool will balance itself out eventually.
	@property size_t MaxSize() const {
		return _MaxSize;
	}

	/// Ditto
	@property void MaxSize(size_t Value) {
		_MaxSize = Value;
	}

	/// Acquires a buffer from the pool, or creates a new buffer if necessary.
	/// Params:
	/// 	The minimum number of bytes that the buffer should contain. If no buffers contain this many bytes, the largest one will be resized and returned.
	Buffer Acquire(size_t NumBytes) {
		Buffer Result;	
		if(Buffers.Count == 0) {
			Result = new Buffer(NumBytes);
			return Result;
		}
		for(size_t i = 0; i < Buffers.Count; i++) {
			if(Buffers[i].Capacity < NumBytes) {
				if(i == 0)
					return Buffers[i];
				Result = Buffers[i - 1];
			}
		}
		if(!Result)
			return Buffers[Buffers.Count - 1];
		Result.Reserve(NumBytes);
		assert(0, "Not yet implemented.");
	}
	
private:
	size_t _MaxSize;
	size_t CurrentSize;	
	alias SortedList!Buffer BufferList;	
	private BufferList Buffers;

	static __gshared BufferPool _Global;	
	size_t IndexForBytes(size_t Bytes) {
		assert(0, "Not yet implemented.");
	}
}