module ShardIO.SocketInput;
public import ShardIO.AsyncSocket;
public import ShardIO.InputSource;


/// Provides an InputSource that reads from a socket.
/// The InputSource is considered complete only once the socket is closed, but can be aborted prior to that.
@disable class SocketInput : InputSource {

public:
	/// Initializes a new instance of the SocketInput object.
	/// Params:
	/// 	Socket = The socket to use for the input. Must be open. This input will only be considered complete once the socket is no longer alive.
	this(AsyncSocket Socket) {		
		this._Socket = Socket;		
	}

	/// Gets the socket that the input is coming from.
	/// Once the socket is no longer alive, the input shall be considered complete.
	@property AsyncSocket Socket() {
		return _Socket;
	}

	/// Called by the IOAction after this InputSource notifies it is ready to have input received.
	/// The InputSource should have roughly RequestedSize bytes ready and then invoke Callback with the available data.
	/// If the InputSource is unable to get an acceptable number of bytes without blocking, then Waiting should be returned.
	/// The RequestedSize parameter is only a hint; as much or little data may be passed in as desired. The unused data will then be buffered.
	/// See $(D, DataRequestFlags) and $(D, DataFlags) for more information as to what the allowed flags are.
	/// Params:
	///		RequestedSize = A rough number of bytes requested to be passed into Callback. This is simply to prevent buffering too much, so if the data is already in memory, just pass it in.
	///		Callback = The callback to invoke with the data.
	/// Ownership:
	///		Any Data passed in will have ownership transferred away from the caller if and only if DataFlags includes the AllowStorage bit.
	override DataRequestFlags GetNextChunk(size_t RequestedSize, scope void delegate(ubyte[], DataFlags) Callback) {
		assert(0);
	}
	
private:
	AsyncSocket _Socket;
}