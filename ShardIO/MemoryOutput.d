module ShardIO.MemoryOutput;
private import std.algorithm;
private import std.parallelism;
private import ShardTools.Buffer;

import ShardIO.OutputSource;


/// An OutputSource used to directly write to a raw array.
class MemoryOutput : OutputSource {

public:
	/// Initializes a new instance of the MemoryOutput object.
	this() {
		
	}

	/// Gets the data that is currently filled in.
	/// Once the operation is completed successfully, this will contain all the data passed in.
	/// Ownership of this data belongs to the input source.
	@property ubyte[] Data() {
		if(buffer is null)
			return null;
		return buffer.Data;
	}

	/// Attempts to handle the given chunk of data.
	/// It is allowed to not handle the entire chunk; the remaining will be buffered and attempted to be written after NotifyReady is called.
	/// For details about the return value, see $(D, DataRequestFlags).
	/// Params:
	///		Chunk = The chunk to attempt to process.
	///		BytesHandled = The actual number of bytes that were able to be handled.
	protected override DataRequestFlags ProcessNextChunk(ubyte[] Chunk, out size_t BytesHandled) {
		// Lazily create the buffer so we can avoid copying the first chunk.	
		if(buffer) {
			buffer.Write(Chunk);
		} else
			buffer = Buffer.FromExistingData(Chunk);
		BytesHandled = Chunk.length;		
		return DataRequestFlags.Continue;
	}
private:
	Buffer buffer;
}