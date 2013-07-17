module ShardIO.CallbackOutput;
private import std.exception;
private import ShardIO.OutputSource;


/// An OutputSource that invokes a callback with the data being sent to it.
/// This is similar to simply implementing your own OutputSource, but prevents the need to implement your own OutputSource.
/// This class assumes that the callback is always available and always capable of handling all of the data.
/// For a more customizable approach, you will need to implement OutputSource yourself.
/// There is, at the moment, no CallbackInput. Instead, consider using a StreamInput to write the data.
/// To make it easier to keep track of State, the CallbackOutput takes in a State pointer passed in to the Callback.
class CallbackOutput : OutputSource {

public:
	
	alias void delegate(void*, ubyte[]) CallbackType;

	/// Initializes a new instance of the CallbackOutput object.
	this(void* State, CallbackType Callback) {		
		this._Callback = Callback;
		this._State = State;
		enforce(Callback !is null);		
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
		_Callback(_State, Chunk);
		BytesHandled = Chunk.length;
		return DataRequestFlags.Continue;		
	}
	
private:
	CallbackType _Callback;
	void* _State;
}