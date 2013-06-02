module ShardIO.StreamInput;
private import std.stdio;
private import std.traits;
private import std.exception;
private import ShardTools.BufferPool;
public import ShardIO.InputSource;
private import ShardTools.Buffer;

/// Determines how to flush a stream.
enum StreamFlushType {
	Manual = 0,
	PerWrite = 1,
	AfterSize = 2
}

/// Indicates the way a Stream will be flushed, and when.
struct FlushMode {
	const StreamFlushType Type;
	const size_t Parameter;

	this(StreamFlushType Type, size_t Parameter) {
		this.Type = Type;
		this.Parameter = Parameter;
	}

	/// Gets a FlushMode that forces a manual call to Flush for data to be written.
	@property static FlushMode Manual() {
		return FlushMode(StreamFlushType.Manual, 0);
	}

	/// Gets a FlushMode that forces a flush on every write.
	@property static FlushMode PerWrite() {
		return FlushMode(StreamFlushType.PerWrite, 0);
	}

	/// Gets a FlushMode that flushes after a minimum of NumBytes have been written.
	/// The remaining bytes in the Write that caused NumBytes to be written are in the same flush as well.
	static FlushMode AfterSize(size_t NumBytes) {
		enforce(NumBytes > 0);
		return FlushMode(StreamFlushType.AfterSize, NumBytes);
	}
}

/// Provides an InputSource that gets manually written to, and flushed to send to the output.
/// The InputSource does not end until Complete is called.
/// Note that there is no StreamOutput, but a MemoryOutput performs a similar task.
class StreamInput : InputSource {

public:
	/// Initializes a new instance of the StreamInput object.
	this(FlushMode FlushType) {		
		SizeEstimate = 1024;
		this._FlushType = FlushType;
		AcquireBuffer();
	}

	/// Gets the way that the StreamInput will be flushed.
	@property FlushMode FlushType() const {
		return _FlushType;
	}

	/// Flushes the Buffer, causing currently appended data to be written upon the next data request.
	void Flush() {
		synchronized(this) {
			if(CurrentBuffer.Data.length == 0)
				return;
			SizeEstimate = CurrentBuffer.Data.length;
			FlushedBuffers ~= CurrentBuffer;
			AcquireBuffer();
			NotifyDataReady();
		}
	}

	/// Reserves space for the given number of bytes in the StreamInput's buffer.
	/// Params:
	/// 	Bytes = The number of bytes to reserve.
	void Reserve(size_t Bytes) {
		synchronized(this) {
			CurrentBuffer.Reserve(Bytes);
		}
	}

	/// Writes an element in to the Stream.
	/// Params:
	/// 	T = The type of the element to write.
	/// 	Data = The element to write.
	void Write(T)(T Data) if(!is(T == class) && !is(T == interface) && !isArray!(T)) {
		synchronized(this) {
			enforce(!_ShouldComplete, "Unable to write more data to a stream after waiting for completion.");
			CurrentBuffer.Write(Data);
			CheckFlush();
		}
	}

	/// Writes an array to the Stream.
	/// Params:
	/// 	T = The type of the elements in the array.
	/// 	Data = The array to write.
	void Write(T)(T[] Data) if(!is(T == class) && !is(T == interface) && !isArray!(T)) {
		synchronized(this) {
			enforce(!_ShouldComplete, "Unable to write more data to a stream after waiting for completion.");
			CurrentBuffer.Write(Data);
			CheckFlush();
		}
	}
		
	/// Writes an array to the Stream, prefixed by an unsigned integer length.
	/// Params:
	/// 	T = The type of the elements in the array.
	///		Data = The array to write.
	void WritePrefixed(T)(T[] Data) if(!is(T == class) && !is(T == interface) && !isArray!T) {
		synchronized(this) {
			enforce(!_ShouldComplete, "Unable to write more data to a stream after waiting for completion.");
			CurrentBuffer.WritePrefixed(Data);
			CheckFlush();
		}
	}

	/// Indicates that no more input will arrive to the Stream, and completes it after going through the buffered data.
	void Complete() {
		synchronized(this) {
			if(_ShouldComplete)
				return;
			Flush();
			_ShouldComplete = true;
		}
	}

protected:
	/// Called by the IOAction after this InputSource notifies it is ready to have input received.
	/// The InputSource should have roughly RequestedSize bytes ready and then invoke Callback with the available data.
	/// If the InputSource is unable to get an acceptable number of bytes without blocking, then Waiting should be returned.
	/// The RequestedSize parameter is only a hint; as much or little data may be passed in as desired. The unused data will then be buffered.
	/// See $(D, DataRequestFlags) and $(D, DataFlags) for more information as to what the allowed flags are.
	/// Params:
	///		RequestedSize = A rough number of bytes requested to be passed into Callback. This is simply to prevent buffering too much, so if the data is already in memory, just pass it in.
	///		Callback = The callback to invoke with the data.
	/// Ownership:
	///		Any Data passed in will have ownership transferred away from the caller if DataFlags includes the AllowStorage bit.
	override DataRequestFlags GetNextChunk(size_t RequestedSize, scope void delegate(ubyte[], DataFlags) Callback) {
		synchronized(this) {
			if(FlushedBuffers.length == 0) {
				Callback(null, DataFlags.None);
				return DataRequestFlags.Waiting;
			}
			Buffer buff = FlushedBuffers[0];
			FlushedBuffers = FlushedBuffers[1..$].dup;
			ubyte[] Data = buff.Data;
			Callback(Data, DataFlags.None);
			BufferPool.Global.Release(buff);
			if(_ShouldComplete && FlushedBuffers.length == 0)
				return DataRequestFlags.Complete;
			if(FlushedBuffers.length == 0)
				return DataRequestFlags.Waiting | DataRequestFlags.Continue;
			return DataRequestFlags.Continue;
		}
	}

private:
	Buffer CurrentBuffer;
	Buffer[] FlushedBuffers;
	FlushMode _FlushType;
	size_t SizeEstimate;
	bool _ShouldComplete;

	void CheckFlush() {
		final switch(_FlushType.Type) {
			case StreamFlushType.Manual:
				return;
			case StreamFlushType.PerWrite:
				Flush();
				return;
			case StreamFlushType.AfterSize:
				if(CurrentBuffer.Data.length >= _FlushType.Parameter)
					Flush();
				return;
		}
	}

	void AcquireBuffer() {
		size_t BufferSize;
		switch(FlushType.Type) {
			case StreamFlushType.AfterSize:
				BufferSize = cast(size_t)(FlushType.Parameter * 1.25f);
				break;
			default:
				BufferSize = SizeEstimate;
				break;
		}
		CurrentBuffer = BufferPool.Global.Acquire(BufferSize);
	}
}