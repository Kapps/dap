module ShardIO.SocketOutput;
private import core.sync.mutex;
private import std.stdio;
private import core.atomic;
private import std.exception;
public import ShardIO.AsyncSocket;
public import ShardIO.OutputSource;


/// Provides an OutputSource that writes to an AsyncSocket until the InputSource is depleted.
/// If a socket error occurs, the action is aborted.
class SocketOutput : OutputSource {

public:
	/// Initializes a new instance of the SocketOutput object.	
	this(AsyncSocket Socket) {		
		this._Socket = Socket;
		this.StateLock = new Mutex();
		enforce(_Socket.IsAlive(), "The socket for a SocketOutput must be alive and connected.");
		_Socket.RegisterNotifyDisconnected(cast(void*)Socket, &OnDisconnect);
	}

	version(D_Ddoc) {
		//static assert(0, "Due to bug 5930, this module may not be compiled with -D.");		
	}

	void OnDisconnect(void* State, string Reason, int ErrorCode) {
		synchronized(StateLock) {			
			if(!IsComplete)
				Action.Abort();
		}
	}

	/// Gets the socket that the output is being sent to.
	/// The socket must be alive when passed in, and will not be closed when the input is depleted.
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
		size_t BytesSent = _Socket.Send(Chunk, cast(void*)Chunk, &OnWriteComplete);
		if(BytesSent == -1) {
			Action.Abort();
			return DataRequestFlags.Complete;
		}
		BytesHandled = BytesSent;
		atomicOp!("+=", size_t, int)(NumSent, 1);			
		// debug writefln("Handled %s bytes for send number %s on SocketOutput.", BytesHandled, NumSent);
		// TODO: Notify?
		return DataRequestFlags.Continue | DataRequestFlags.Waiting;		
	}

protected:
	/// Must be overridden if ProcessNextChunk completes asynchronously.
	/// Called after the last call to ProcessNextChunk, with a callback to invoke when the chunk is fully finished being processed.
	/// For example, when using overlapped IO, the callback would be invoked after the actual write is complete, as opposed to queueing the write.
	/// The base method should not be called if overridden.
	override void NotifyOnCompletion(void delegate() Callback) {		
		CompletionCallback = Callback;
		AttemptCompletion();		
	}

	
	/// Occurs when the action completes for whatever reason.
	override void OnComplete(IOAction Action, CompletionType Type) {
		super.OnComplete(Action, Type);
		if(_Socket)
			_Socket.RemoveNotifyDisconnected(&OnDisconnect);
	}
	
private:
	AsyncSocket _Socket;	
	size_t NumSent;
	size_t NumReceived;
	void delegate() CompletionCallback;
	bool IsComplete = false;
	Mutex StateLock;

	bool AttemptCompletion() {
		bool InvokeCallback = false;
		bool RetVal;
		synchronized(StateLock) {
			if(NumSent == NumReceived && CompletionCallback !is null) {			
				if(!IsComplete) {
					IsComplete = true;
					InvokeCallback = true;
					//CompletionCallback();			
				}
				RetVal = true;
			}
			RetVal = false;		
		}
		if(InvokeCallback)
			CompletionCallback(); // Do this outside a lock.
		return RetVal;
	}

	void OnWriteComplete(void* State, size_t BytesSent) {		
		atomicOp!("+=", size_t, int)(NumReceived, 1);			
		if(!AttemptCompletion())
			NotifyReady();		
	}
}