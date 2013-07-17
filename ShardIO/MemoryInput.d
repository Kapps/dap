module ShardIO.MemoryInput;
private import std.stdio;
private import std.parallelism;
private import std.algorithm;

import ShardIO.InputSource;

/// Provides an InputSource to read from an in-memory array.
class MemoryInput : InputSource {

public:
	/// Initializes a new instance of the MemoryInput object.
	/// Params:
	/// 	Raw = The raw array used for input. Unless ForceCopy is true, this array will be referenced directly and may be modified.
	/// 	ForceCopy = Whether or not to force a copy of Raw.
	this(ubyte[] Raw, bool ForceCopy = false) {		
		this.Raw = Raw;
		this.ForceCopy = ForceCopy;
	}	 

	/// Called by the IOAction after this InputSource notifies it is ready to have input received.
	/// The InputSource should have roughly RequestedSize bytes ready and then invoke Callback with the available data.
	/// If the InputSource is unable to get an acceptable number of bytes without blocking, then Waiting should be returned.
	/// The RequestedSize parameter is only a hint; as much or little data may be passed in as desired. The unused data will then be buffered.
	/// See $(D, DataRequestFlags) and $(D, DataFlags) for more information as to what the allowed flags are.
	/// Params:
	///		RequestedSize = A rough number of bytes requested to be passed into Callback. This is simply to prevent buffering too much, so if the data is already in memory, just pass it in.
	///		Callback = The callback to invoke with the data.
	protected override DataRequestFlags GetNextChunk(size_t RequestedSize, scope void delegate(ubyte[], DataFlags) Callback) {
		// We already have it all in memory, may as well let the IOAction buffer it all.
		DataFlags Flags = ForceCopy ? DataFlags.None : DataFlags.AllowStorage;		
		Callback(this.Raw, Flags);
		// Make sure this doesn't try to keep it in memory once IOAction is done with it.		
		this.Raw = null;				
		return DataRequestFlags.Complete;		
	}
	
	
private:
	ubyte[] Raw;
	bool ForceCopy;
}