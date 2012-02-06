module ShardIO.OutputSource;
private import ShardIO.IOAction;

public import ShardIO.DataSource;


/// Provides a DataSource used as the output for an operation.
abstract class OutputSource : DataSource {

public:
	/// Initializes a new instance of the OutputSource object.
	this() {
		
	}

package:
	DataRequestFlags InvokeProcessNextChunk(ubyte[] Chunk, out size_t BytesHandled) {
		return ProcessNextChunk(Chunk, BytesHandled);
	}
	void InvokeNotifyCompletion(void delegate() Callback) {
		NotifyOnCompletion(Callback);
	}

protected:
	
	/// Attempts to handle the given chunk of data.
	/// It is allowed to not handle the entire chunk; the remaining will be buffered and attempted to be written after NotifyReady is called.	
	/// For details about the return value, see $(D, DataRequestFlags).	
	/// In most situations, this function should return Continue. But if the source can't handle more data, then Complete should be returned.
	/// It is assumed that the write is fully handled by the end of this method. If this is not the case, then NotifyOnCompletion must be overridden.
	/// Params:
	/// 	Chunk = The chunk to attempt to process.
	/// 	BytesHandled = The actual number of bytes that were able to be handled.	
	abstract DataRequestFlags ProcessNextChunk(ubyte[] Chunk, out size_t BytesHandled);
	
	/// Must be overridden if ProcessNextChunk completes asynchronously.
	/// Called after the last call to ProcessNextChunk, with a callback to invoke when the chunk is fully finished being processed.
	/// For example, when using overlapped IO, the callback would be invoked after the actual write is complete, as opposed to queueing the write.	
	/// The base method should not be called if overridden.
	void NotifyOnCompletion(void delegate() Callback) {
		// Default implementation completes immediately.
		Callback();
	}

	/// Notifies the IOAction owning this OutputSource that it is ready to handle more data.
	final void NotifyReady() {
		synchronized(this) {
			if(Action)
				Action.NotifyOutputReady();
		}
	}
	
private:
}