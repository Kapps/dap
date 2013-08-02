module ShardIO.ChainedInput;
public import ShardIO.InputSource;
// Todo...
version(None) {
/// Provides an InputSource that takes input from one or more other input sources.
/// A ChainedInput is similar to a StreamInput, in the sense that it operates by writing to it,
/// but instead of bytes being written, InputSources get written.
/// A ChainedInput must be manually closed, in order to indicate no new input will be written.
class ChainedInput : InputSource {

public:
	/// Initializes a new instance of the ChainedInput object.
	this() {
		
	}
	
protected:
	/// Called by the IOAction after this InputSource notifies it is ready to have input received.
	/// The InputSource should have roughly RequestedSize bytes ready and then invoke Callback with the available data.
	/// If the InputSource is unable to get an acceptable number of bytes without blocking, then Waiting should be returned.
	/// The RequestedSize parameter is only a hint; as much or little data may be passed in as desired. The unused data will then be buffered.
	/// See $(D, DataRequestFlags) and $(D, DataFlags) for more information as to what the allowed flags are.
	/// Params:
	/// 	RequestedSize = A rough number of bytes requested to be passed into Callback. This is simply to prevent buffering too much, so if the data is already in memory, just pass it in.
	/// 	Callback = The callback to invoke with the data.
	/// Ownership:
	///		Any Data passed in will have ownership transferred away from the caller if DataFlags includes the AllowStorage bit.
	override DataRequestFlags GetNextChunk(size_t RequestedSize, scope void delegate(ubyte[], DataFlags) Callback) {

	}

private:
	
}
}