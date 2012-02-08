module ShardIO.SocketOutput;
private import std.exception;
public import ShardIO.AsyncSocket;
public import ShardIO.OutputSource;


/// Provides an OutputSource that writes to an AsyncSocket until the InputSource is depleted or the socket receives an error.
class SocketOutput : OutputSource {

public:
	/// Initializes a new instance of the SocketOutput object.	
	this(AsyncSocket Socket) {		
		this._Socket = Socket;
		enforce(_Socket.IsAlive(), "The socket for a SocketOutput must be alive and connected.");
		_Socket.RegisterNotifyDisconnected(cast(void*)Socket, &OnDisconnect);
	}

	void OnDisconnect(void* State, string Reason, int ErrorCode) {
		synchronized(this) {
			ForceComplete = true;
			if(CompletionCallback && !IsComplete) {
				CompletionCallback();
				IsComplete = true;
			}
			NotifyReady();
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
		synchronized(this) {
			if(ForceComplete) {
				BytesHandled = 0;
				if(CompletionCallback && !IsComplete) {
					CompletionCallback();
					IsComplete = true;
				}
				return DataRequestFlags.Complete;
			}
			size_t BytesSent = _Socket.Send(Chunk, cast(void*)Chunk, &OnWriteComplete);
			if(BytesSent == -1) {
				BytesHandled = 0;
				return DataRequestFlags.Complete;
			}
			BytesHandled = BytesSent;
			this.NumSent++;
			return DataRequestFlags.Continue | DataRequestFlags.Waiting;
		}
	}

protected:
	/// Must be overridden if ProcessNextChunk completes asynchronously.
	/// Called after the last call to ProcessNextChunk, with a callback to invoke when the chunk is fully finished being processed.
	/// For example, when using overlapped IO, the callback would be invoked after the actual write is complete, as opposed to queueing the write.
	/// The base method should not be called if overridden.
	override void NotifyOnCompletion(void delegate() Callback) {
		synchronized(this) {
			CompletionCallback = Callback;
			AttemptCompletion();
		}
	}
	
private:
	AsyncSocket _Socket;
	bool ForceComplete = false;
	size_t NumSent;
	size_t NumReceived;
	void delegate() CompletionCallback;
	bool IsComplete = false;

	bool AttemptCompletion() {
		if(NumSent == NumReceived && CompletionCallback !is null) {			
			if(!IsComplete)
				CompletionCallback();			
			return true;
		}
		return false;		
	}

	void OnWriteComplete(void* State, size_t BytesSent) {
		synchronized(this) {
			if(ForceComplete) {
				if(!IsComplete && CompletionCallback)
					CompletionCallback();
				return;
			}		
			NumReceived++;
			if(!AttemptCompletion())
				NotifyReady();
		}
	}
}