module ShardIO.IOAction;
private import ShardTools.ExceptionTools;
private import std.datetime;
private import ShardTools.NativeReference;
private import std.conv;
private import core.atomic;
private import std.stdio;
private import core.thread;
private import std.algorithm;
public import ShardIO.IOManager;
private import core.sync.mutex;
private import std.exception;
private import ShardTools.Event;
private import ShardTools.Buffer;
public import ShardIO.OutputSource;
public import ShardIO.InputSource;
import std.array;

mixin(MakeException("TimeoutException", "An operation has timed out prior to completion."));

/// Indicates whether an IOAction is complete and whether it was aborted or finished successfully.
enum CompletionType {
	Incomplete = 0,
	Aborted = 1,
	Successful = 2
}

/// Indicates an operation retrieving input from an InputSource and then outputting it to an OutputSource.
/// All public methods in this class are thread-safe.
class IOAction {

public:

	alias Event!(void, IOAction, CompletionType) CompletionEvent;

	/// Initializes a new instance of the IOAction object.
	this(InputSource Input, OutputSource Output) {		
		this._Status = CompletionType.Incomplete;
		this._ChunkSize = DefaultChunkSize;
		this._MaxChunks = DefaultMaxChunks;				
		this._Input = Input;
		this._Output = Output;
		Input._Action = this;
		Output._Action = this;
	}

	/// Notifies the given callback when the action is complete.
	/// If the action is already complete, the callback is notified immediately and synchronously.	
	final void NotifyOnComplete(void delegate(IOAction Action, CompletionType Type) Callback) {
		synchronized(this) {
			if(_Status == CompletionType.Incomplete) {
				if(!_Completed)
					_Completed = new CompletionEvent();
				_Completed ~= Callback;
			} else {
				Callback(this, _Status);
			}
		}
	}

	/// Gets the input for this action.
	@property InputSource Input() {
		return _Input;
	}

	/// Gets the output for this action.
	@property OutputSource Output() {
		return _Output;
	}

	/// Gets a value indicating whether this action has started being processed.
	@property bool IsStarted() const {
		return HasBegun;
	}

	/// Indicates the status of this operation.
	final @property CompletionType CompletionStatus() const {
		return _Status;
	}

	/// Gets or sets the default value for ChunkSize for new IOActions.
	static @property size_t DefaultChunkSize() {
		return _DefaultChunkSize;
	}

	/// Ditto
	static @property void DefaultChunkSize(size_t Value) {
		enforce(Value >= 16);
		_DefaultChunkSize = Value;
	}

	/// Gets or sets the chunk size for new reads/writes.
	/// It is attempted that reads and writes operate on around this size per call.
	@property size_t ChunkSize() const {
		return _ChunkSize;
	}

	/// Ditto
	@property void ChunkSize(size_t Value) {
		enforce(Value >= 16);
		_ChunkSize = Value;
	}

	/// Gets or sets the default value for MaxChunks for new IOActions.
	static @property size_t DefaultMaxChunks() {
		return _DefaultMaxChunks;
	}

	/// Ditto
	static @property void DefaultMaxChunks(size_t Value) {
		enforce(Value > 0);
		_DefaultMaxChunks = Value;
	}

	/// Gets or sets the maximum number of chunks that can be buffered at a time.
	/// When the input is read faster than can be outputted, it is possible to buffer the input.
	/// The amount of input buffered is equal to this value.
	@property size_t MaxChunks() const {
		return _MaxChunks;
	}

	/// Ditto
	@property void MaxChunks(size_t Value) {
		enforce(Value > 0);
		_MaxChunks = Value;
	}
	
	/// Begins this operation asynchronously.	
	void Start() {
		// Called from: Non-Process Thread. Thread-safe: With Lock. Dead-Lock Risk: None.
		synchronized(this) {
			enforce(!HasBegun, "The operation had already been begun.");
			if(_Manager is null)
				_Manager = IOManager.Default;
			HasBegun = true;			
			ProcessIfNeeded();
			NativeReference.AddReference(cast(void*)this);
		}
	}

	/// Aborts the operation, preventing any new data being written (unless it has already begun being written).
	void Abort() {		
		AttemptFinish(CompletionType.Aborted);
	}

	/// Blocks the calling thread until this action completes. This has, at most, 1 millisecond precision.
	/// Returns the way in which this action was completed.
	/// Params:
	/// 	Timeout = A duration after which to throw an exception if not yet complete.
	CompletionType WaitForCompletion(Duration Timeout) {
		// Called from: Non-Process Thread. Thread-safe: Yes.
		SysTime Start = Clock.currTime();
		while(_Status == CompletionType.Incomplete) {
			Thread.sleep(dur!"msecs"(1));
			SysTime Current = Clock.currTime();
			if((Current - Start) > Timeout)
				throw new TimeoutException();
		}
		return _Status;
	}

	/// Gets or sets the IO Manager executing this action.
	/// This value is only allowed to be set before Start is called.
	@property IOManager Manager() {		
		return _Manager;
	}

	/// Ditto
	@property void Manager(IOManager Value) {
		enforce(!HasBegun, "Unable to set the IO Manager for a started action.");
		_Manager = Value;
	}

package:
	// TODO: Would be nice to remove the locks on Notify____Ready without breaking everything in race conditions. Even with atomics though it breaks.
	// The actual process / input checks can stay locked, that's not a big deal. We just want to know that input/output is ready without needing a lock.
	void NotifyInputReady() {
		// Called from: Non-Process Thread. Thread-safe: With Lock. Race Risk: None				
		synchronized(this) {		
			if(!HasBegun)
				return;
			WaitingOn &= ~DataOperation.Read;
			if(IsInputComplete || (AreBuffersFull() && (WaitingOn & DataOperation.Write) == 0)) {				
				return; // Waiting for output, so no need to do anything here.
			}
			ProcessIfNeeded();
		}
	}

	void NotifyOutputReady() {
		// Called from: Non-Process Thread. Thread-safe: With Lock. Race Risk: None		
		synchronized(this) {			
			if(!HasBegun)
				return;
			WaitingOn &= ~DataOperation.Write;
			if(Buffers.length == 0 && (WaitingOn & DataOperation.Read) == 0) {				
				return; // We're just waiting for the input source to notify us we're ready.
			}
			ProcessIfNeeded();	
		}
	}	

protected:
	
	void OnDataReceived(ubyte[] Data, DataFlags Flags) {	
		// Called from: Process Thread; automatically thread-safe.
		if((Flags & DataFlags.AllowStorage) == 0) {
			Data = Data.dup; // TODO: Try to optimize this. But how?
			Flags |= DataFlags.AllowStorage;
		}
		if((WaitingOn & DataOperation.Write) != 0) {
			// Waiting on a write, so buffer this.			
			BufferData(Data, Flags);
		} else if(Data.length > 0) { // Nothing to do on a 0 byte buffer.
			// Otherwise, try to handle it.
			size_t NumHandled;
			DataRequestFlags OutFlags = Output.InvokeProcessNextChunk(Data, NumHandled);
			if(NumHandled > 0) {
				enforce(NumHandled <= Data.length);
				Data = Data[NumHandled..$];												
			}
			ProcessFlags(OutFlags, DataOperation.Write);
			// If nothing handled or anything left, buffer the rest.
			if(Data.length > 0)
				BufferData(Data, Flags); // We already duplicated it.
		}		
	}
	
private:
	static __gshared size_t _DefaultChunkSize = 16384;
	static __gshared size_t _DefaultMaxChunks = 4;

	InputSource _Input;
	OutputSource _Output;
	CompletionType _Status;
	CompletionEvent _Completed;
	
	size_t _ChunkSize;
	size_t _MaxChunks;	
	
	// TODO: Make this a linked-list.
	Buffer[] Buffers;
	bool HasBegun;
	DataOperation WaitingOn;	
	package bool InDataOperation;	
	CompletionType CompleteOnBreakType;
	IOManager _Manager;
	bool IsInputComplete; // Because Input needs to wait for Output to complete. If Output says we're done though, we're done.
	CompletionType OutputCompletionCallbackState; // When using asynchronous output, need to know what type of completion we're waiting on.

	bool AreBuffersFull() {
		// Called from: Process Thread; automatically thread-safe.

		/+ // TODO: Try to take into consideration data larger than BufferSize for MaxChunks.
		// Aka, two chunks 50% larger than BufferSize should result in no more buffering when MaxChunks is three.	
		// Do it in a fast way though, maybe cache it. Probaly doesn't need to be too fast though, we operate on chunks after all and it's only checked per-chunk.
		return Buffers.length >= MaxChunks;		+/

		// TODO: Consider optimizing. Probably not needed.
		size_t ResultSize = 0;
		foreach(Buffer b; Buffers)
			ResultSize += b.Data.length;
		return ResultSize >= MaxChunks * ChunkSize;
	}

	void BufferData(ubyte[] Data, DataFlags Flags) {		
		// Called from: Process Thread; automatically thread-safe.

		if(Data.length == 0)
			return;
		// If we're allowed to store directly, and the data is large enough to warrant a buffer of it's own, we just copy a reference.			
		if((Flags & DataFlags.AllowStorage) && (Data.length > ChunkSize * 0.1f || Data.length > 2048))
			Buffers ~= Buffer.FromExistingData(Data);
		// Otherwise, we have to copy into an existing buffer.
		else if(Buffers.length == 0) {
			// Even if it was small, can still create a buffer in this case because no existing one.
			if((Flags & DataFlags.AllowStorage))
				Buffers ~= Buffer.FromExistingData(Data);
			else // Otherwise, a buffer with a copy of the contents.
				Buffers ~= Buffer.FromExistingData(Data.dup);
		} else if(Data.length > 0) {
			// Lastly, we copy into an existing buffer.
			// It's okay to make a large buffer, as we're forced to buffer all this data since we can't just tell the input source to put it back (and there would be no point in doing so).
			ptrdiff_t AmountToCopy = min(ChunkSize - Buffers[$-1].Data.length, Data.length);
			if(AmountToCopy > 0) { // It may be less than zero because of creating too large a buffer.
				Buffers[$-1].Write(Data[0 .. AmountToCopy]);
				Data = Data[AmountToCopy .. $];
			}
			// The data that remains all goes into a possibly larger-than-chunksize buffer.
			Buffer Next = Buffer.FromExistingData(Data.dup);
			Buffers ~= Next;
		}		
	}

	private void ProcessIfNeeded() {
		// Called from: Non-Process Thread. Thread-safe: With Lock. Race Risk: None?
		// Basically, we don't want to acutally manipulate the data in the main thread.
		// Instead, when we receive a notification that data is ready, we process the data in a worker thread.
		// This means we're limited to a certain number of threads, but it's not too big a deal. Remember that they're only used when data is actually moved.
		// When we're just waiting for data, we don't need to waste a worker thread for it.
		// The IOManager gets to take care of this. We just need to make sure we don't queue the same action multiple times at once.		
		//debug writeln("PIF");		
		synchronized(this) {			
			//debug writeln("PIF lock received");
			if(InDataOperation) {				
				return;
			}
			InDataOperation = true;
			Manager.QueueAction(this);
			//debug writeln("Queued");
		}		
	}	

	/// Processes the flags returned by a DataSource. Returns whether more data should be handled for this source.
	bool ProcessFlags(DataRequestFlags Flags, DataOperation Operation) {
		// Called from: Process Thread; automatically thread-safe.
		if((Flags & DataRequestFlags.Complete) != 0) {			
			if(Operation == DataOperation.Write) {
				OutputCompletionCallbackState = CompletionType.Successful;
				Output.InvokeNotifyCompletion(&NotifyOutputComplete);
			} else {
				IsInputComplete = true;
				if(Buffers.length == 0) {					
					OutputCompletionCallbackState = CompletionType.Successful;
					Output.InvokeNotifyCompletion(&NotifyOutputComplete);
				}
			}			
			return false;
		}
		if((Flags & DataRequestFlags.Waiting) != 0) {
			WaitingOn |= Operation;
			return false;
		}
		enforce((Flags & DataRequestFlags.Continue) != 0, "Return flags must either include Complete, Continue, or Waiting.");
		return true;
	}	

	void NotifyOutputComplete() {		
		// Called from: Any Thread. Thread-safe: With locks.
		synchronized(this) {			
			enforce(OutputCompletionCallbackState != CompletionType.Incomplete);
			AttemptFinish(OutputCompletionCallbackState);
		}		
	}
	
	package void ProcessData() {		
		// This is where we actually get data from the input and transfer it to output.
		// Even though we can be notified at any time, we don't execute it until this is reached.
		// Note that this is run in a separate worker thread.
		// So if we get an abort in the middle of this, we need to wait for this write to finish then call the completion event.
		// Likewise, we don't want this to start in the middle of Abort.
		//debug writeln("PD");			
		synchronized(this) {			
			bool CheckCompletion() {
				// We're complete when Output says we are, or when Input says we are and Output finishes.				
				if(Buffers.length == 0 && IsInputComplete) {
					if(OutputCompletionCallbackState == CompletionType.Incomplete) {
						// Already processed this.
						assert(CompleteOnBreakType == CompletionType.Incomplete);
						OutputCompletionCallbackState = CompletionType.Successful;						
						Output.InvokeNotifyCompletion(&NotifyOutputComplete);
					}
					// In case they made Notify be blocking (which default implementation is).
					if(CompleteOnBreakType != CompletionType.Incomplete)
						CompleteFinish(CompleteOnBreakType);
					return true;
				}				
				return false;
			}
			
			bool CanRead() {				
				return !AreBuffersFull() && (WaitingOn & DataOperation.Read) == 0 && !IsInputComplete && CompleteOnBreakType == CompletionType.Incomplete;
			}
			bool CanWrite() {				
				return Buffers.length > 0 && (WaitingOn & DataOperation.Write) == 0 && CompleteOnBreakType == CompletionType.Incomplete;				
			}	
			
			scope(exit)
				InDataOperation = false;
			try {
				while(CanRead() || CanWrite()) {
					// Try to use buffers first as much as possible.				
					while(CanWrite()) {					
						ubyte[] BufferData = Buffers[0].Data;
						size_t NumHandled;
						DataRequestFlags Flags = Output.InvokeProcessNextChunk(BufferData, NumHandled);
						if(NumHandled > 0) {							
							enforce(NumHandled <= BufferData.length);
							BufferData = BufferData[NumHandled..$];								
							if(BufferData.length == 0) {		
								Buffers = (Buffers.length == 1 ? null : Buffers[1..$].dup);
							} else {
								Buffer Remaining = Buffer.FromExistingData(BufferData);
								Buffers[0] = Remaining;
							}					
						} 
						// 0 bytes handled; nothing to do here. So, just break. They probably should return Complete or Waiting, but not necessarily.
						// But, we may as well read some more data if needed to give them a bit more time.
						if(!ProcessFlags(Flags, DataOperation.Write))
							break;
					}

					if(CheckCompletion())
						return;
			
					// Otherwise, we do this to get more input. Then the input goes into DataReceived, which attempts to process as much as possible before buffering the rest.			
					while(CanRead()) {				
						DataRequestFlags Flags = Input.InvokeGetNextChunk(ChunkSize, &OnDataReceived);							
						if(!ProcessFlags(Flags, DataOperation.Read))
							break;
					}					

					if(CheckCompletion())
						return;				
				}	
			} catch (Throwable e) {
				CompleteFinish(CompletionType.Aborted);
				throw e;
			}					
		}
	}	

	void AttemptFinish(CompletionType Type) {
		// TODO: See what happens if CompleteOnBreakType is set here. Nothing should really care much if it is..?
		// But possibly subtle race conditions that will be difficult to spot.
		// At the moment, if on the last loop of CanRead/Write, it will probably break.
		synchronized(this) {
			enforce(_Status == CompletionStatus.Incomplete);			
			if(InDataOperation)			
				CompleteOnBreakType = Type;
			else
				CompleteFinish(Type);
		}
	}

	void CompleteFinish(CompletionType Type) {
		synchronized(this) {
			enforce(_Status == CompletionType.Incomplete);
			enforce(Type == CompletionType.Successful || Type == CompletionType.Aborted);
			_Status = Type;
			if(_Completed) {
				_Completed.Execute(this, Type);
				_Completed = null; // Don't allow memory leaks by keeping this referenced.
			}
			CompleteOnBreakType = CompletionType.Incomplete;
			NativeReference.RemoveReference(cast(void*)this);
		}
	}
}