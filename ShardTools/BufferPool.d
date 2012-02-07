module ShardTools.BufferPool;
private import core.atomic;
public import ShardTools.Buffer;
private import ShardTools.SortedList;
public import std.outbuffer;
private import std.container;

/// Provides access to a pool of reuseable buffers.
class BufferPool  {

// TODO: Allow support for Paged buffers.

public:

	static this() {		
		// TODO: REMEMBER TO CHANGE THIS TO HIGHER.
		// Once SortedList doesn't suck anyways.
		_Global = new BufferPool(1024 * 1024 * 2); // 32 megabytes max by default seems safe.
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
	/// 	NumBytes = The minimum number of bytes that the buffer should contain. If no buffers contain this many bytes, the largest one will be resized and returned.
	Buffer Acquire(size_t NumBytes) {
		synchronized(this) {
			Buffer Result;	
			if(Buffers.Count == 0) {
				Result = new Buffer(NumBytes);
				return Result;
			}					
			for(size_t i = 0; i < Buffers.Count; i++) {
				if(Buffers[i].Capacity < NumBytes) {
					if(i == 0) {
						Result = Buffers[i];					
						Buffers.RemoveAt(0);
					} else {
						Result = Buffers[i - 1];					
						Buffers.RemoveAt(i - 1);
					}
					break;
				}
			}
			if(!Result) {
				Result = Buffers[Buffers.Count - 1];			
				Buffers.RemoveAt(Buffers.Count - 1);
			}
			CurrentSize -= Result.Capacity;
			Result.Reserve(NumBytes);	
			return Result;
		}
	}

	/// Releases the specified buffer, putting it back into the pool if the pool is not full.
	/// If the buffer is too large to fit, it shall be discarded because it is not possible to slice the buffer without maintaining a reference to the whole data.
	/// Params:
	/// 	Buffer = The buffer to release in to the pool.
	/// 	ClearOldData = Whether to zero out the old data in the buffer.
	void Release(Buffer Buffer, bool ClearOldData = false) {		
		synchronized(this) {
			Buffer.Reuse(ClearOldData);
			if(CurrentSize + Buffer.Capacity > MaxSize)
				return;
			CurrentSize += Buffer.Capacity;
			Buffers.Add(Buffer, Buffer.Capacity);					
		}
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