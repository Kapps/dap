module ShardIO.SocketOutput;
public import ShardIO.AsyncSocket;
public import ShardIO.OutputSource;


/// Provides an OutputSource that writes to a socket.
@disable class SocketOutput : OutputSource {

public:
	/// Initializes a new instance of the SocketOutput object.	
	this(AsyncSocket Socket, IOAction Action) {
		super(Action);
		this._Socket = Socket;
	}

	/// Gets the socket that the output is being sent to.
	@property AsyncSocket Socket() {
		return _Socket;
	}

	/// Attempts to handle the given chunk of data.
	/// It is allowed to not handle the entire chunk; the remaining will be buffered and attempted to be written after NotifyReady is called.
	/// For details about the return value, see $(D, DataRequestFlags).
	/// In most situations, this function should return Continue. But if the source can't handle more data, then Complete should be returned.
	/// It is assumed that the write is fully handled by the end of this method. If this is not the case, then NotifyOnCompletion must be overridden.
	/// Params:
	///		Chunk = The chunk to attempt to process.
	///		BytesHandled = The actual number of bytes that were able to be handled.
	override DataRequestFlags ProcessNextChunk(ubyte[] Chunk, out size_t BytesHandled) {
		assert(0);
	}
	
private:
	AsyncSocket _Socket;
}