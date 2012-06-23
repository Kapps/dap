module ShardIO.InputSource;

public import ShardIO.DataSource;

/// Provides information about data read from an InputSource.
enum DataFlags {
	None = 0,
	/// Indicates the data may be safely stored without needing to be copied.
	/// Setting this flag removes ownership from the caller, and allows the data to be used directly (and possibly changed).
	AllowStorage = 1
}

/// Provides a data source used as an input for an operation.
abstract class InputSource : DataSource {

public:
	/// Initializes a new instance of the InputSource object.
	this() {
		
	}

package:
	DataRequestFlags InvokeGetNextChunk(size_t RequestedSize, scope void delegate(ubyte[], DataFlags) Callback) {
		return GetNextChunk(RequestedSize, Callback);
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
	abstract DataRequestFlags GetNextChunk(size_t RequestedSize, scope void delegate(ubyte[], DataFlags) Callback);

	/// Notifies the IOAction owning this InputSource that there is some data ready to be written.
	final void NotifyDataReady() {		
		if(Action) // If not, we're ready prior to a call to Start, so it's fine anyways.
			Action.NotifyInputReady();		
	}

	/// Notifies the IOAction that there is data available that must be processed immediately.
	/// This is useful for when the input source receives data that must be disposed of prior to the end of the callback function.
	/// The data is processed in the calling thread, and is guaranteed to be fully processed prior to returning.
	/// Params:
	/// 	Data = 
	@disable final void NotifyDataReadyDirect(ubyte[] Data, DataFlags Flags) {
		// Problems with this:
		//	1) The data may still need to be buffered. A copy works here though. But it defeats the purpose. Still, can be beneficial if the output can write it all.
		//	2) More importantly, it is guaranteed that the output owns the data after it is passed in. Perhaps this should be changed. Maybe let Flags pass in to output?
	}
}