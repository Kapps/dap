module ShardIO.IOAction;
private import ShardTools.LinkedList;
public import ShardTools.AsyncAction;
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
import ShardTools.Untyped;

/// Indicates an operation retrieving input from an InputSource and then outputting it to an OutputSource.
/// All public methods in this class are thread-safe.
class IOAction : AsyncAction {

public:

	// TODO: Remove IOManager, and instead use the TaskManager.
	// Just yield when there's no input ready.
	// Consider using a TaskRepeater to check for a delegate, and have an AsyncAction that does that.	

	/// Initializes a new instance of the IOAction object.
	this(InputSource Input, OutputSource Output) {				
		super();
		this._ChunkSize = DefaultChunkSize;
		this._MaxChunks = DefaultMaxChunks;				
		this._Input = Input;
		this._Output = Output;		
		this.Buffers = new LinkedList!(Buffer)();
		this.DataLock = new Mutex();
		this.StateLock = new Mutex();
		// To allow setting IS/OS monitor to this action's.						
		Input.NotifyInitialize(this);
		Output.NotifyInitialize(this);		
	}

	/// Gets the input for this action.
	@property InputSource Input() {
		return _Input;
	}

	/// Gets the output for this action.
	@property OutputSource Output() {
		return _Output;
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

	/// Gets or sets the IO Manager executing this action.
	/// This value is only allowed to be set before Start is called.
	/// If no value is set, the default IOManager is used.
	@property IOManager Manager() {				
		return _Manager;
	}

	/// Ditto
	@property void Manager(IOManager Value) {
		enforce(!HasBegun, "Unable to set the IO Manager for a started action.");
		_Manager = Value;
	}

	/// Begins this operation asynchronously.
	/// If no Manager has been set yet, a default instance will be set now.
	override void Start() {
		super.Start();
		// TODO: LDC says can not cast from null to IOManager with the below line.
		// So just make it not thread-safe for now. It seems unlikely to actually be an issue.
		//cas(cast(shared)&_Manager, cast(shared)null, cast(shared)IOManager.Default);
		if(_Manager is null)
			_Manager = IOManager.Default;
		ProcessIfNeeded();
	}

package:
	void NotifyInputReady() {					
		synchronized(DataLock, StateLock) {		
			if(!HasBegun)
				throw new InvalidOperationException("An action that has not yet begun should not be notified of being ready.");
			if((WaitingOn & DataOperation.Read) == 0) 
				return;			
			WaitingOn &= ~DataOperation.Read;
			if(IsInputComplete || (AreBuffersFull() && (WaitingOn & DataOperation.Write) == 0))				
				return; // Just waiting for output, so no need to do anything here.			
		}
		ProcessIfNeeded();
	}

	void NotifyOutputReady() {
		synchronized(DataLock, StateLock) {			
			if(!HasBegun)
				return;
			WaitingOn &= ~DataOperation.Write;
			if(Buffers.Count == 0 && (WaitingOn & DataOperation.Read) == 0)
				return; // We're just waiting for the input source to notify us we're ready.						
		}
		ProcessIfNeeded();	
	}	

protected:
	
	void OnDataReceived(ubyte[] Data, DataFlags Flags) {			
		if((Flags & DataFlags.AllowStorage) == 0) {
			Data = Data.dup; // TODO: Try to optimize this. But how? At the least we could use a buffer. Could also try processing some first.
			Flags |= DataFlags.AllowStorage;
		}
		bool Buffered = false;
		synchronized(DataLock) {
			if((WaitingOn & DataOperation.Write) != 0) {
				// Waiting on a write, so buffer this.			
				BufferData(Data, Flags);
			}
		}
		if(!Buffered && Data.length > 0) { // Nothing to do on a 0 byte buffer.
			// Otherwise, try to handle it.
			size_t NumHandled;
			DataRequestFlags OutFlags = Output.InvokeProcessNextChunk(Data, NumHandled);
			if(NumHandled > 0) {
				enforce(NumHandled <= Data.length);
				Data = Data[NumHandled..$];												
			}
			ProcessFlags(OutFlags, DataOperation.Write);
			// If nothing handled or anything left, buffer the rest.
			if(Data.length > 0) {					
				BufferData(Data, Flags); // We already duplicated it.
			}		
		}
	}	

	/// Implement to handle the actual canceling of the action.	
	override void PerformAbort() {
		if(HasBegun)
			AttemptFinish(CompletionType.Aborted);
	}
	
private:
	static __gshared size_t _DefaultChunkSize = 16384;
	static __gshared size_t _DefaultMaxChunks = 4;

	InputSource _Input;
	OutputSource _Output;		
	
	Mutex DataLock, StateLock;
	size_t _ChunkSize;
	size_t _MaxChunks;		
	LinkedList!(Buffer) Buffers;
	bool HasBegun;
	DataOperation WaitingOn;	
	package bool InDataOperation;	
	CompletionType CompleteOnBreakType;
	IOManager _Manager;
	bool IsInputComplete; // Because Input needs to wait for Output to complete. If Output says we're done though, we're done.
	CompletionType OutputCompletionCallbackState; // When using asynchronous output, need to know what type of completion we're waiting on.	

	bool AreBuffersFull() {
		// TODO: Consider optimizing. Probably not needed.
		size_t ResultSize = 0;
		foreach(Buffer b; Buffers)
			ResultSize += b.Data.length;
		return ResultSize >= MaxChunks * ChunkSize;
	}

	void BufferData(ubyte[] Data, DataFlags Flags) {								
		if(Data.length == 0)
			return;		
		synchronized(DataLock) {
			// If we're allowed to store directly, and the data is large enough to warrant a buffer of it's own, we just copy a reference.			
			if((Flags & DataFlags.AllowStorage) && (Data.length > ChunkSize * 0.1f || Data.length > 2048))
				Buffers ~= Buffer.FromExistingData(Data);
			// Otherwise, we have to copy into an existing buffer.
			else if(Buffers.Count == 0) {
				// Even if it was small, can still create a buffer in this case because no existing one.
				if((Flags & DataFlags.AllowStorage))
					Buffers ~= Buffer.FromExistingData(Data);
				else // Otherwise, a buffer with a copy of the contents.
					Buffers ~= Buffer.FromExistingData(Data.dup);
			} else if(Data.length > 0) {
				// Lastly, we copy into an existing buffer.
				// It's okay to make a large buffer, as we're forced to buffer all this data since we can't just tell the input source to put it back (and there would be no point in doing so).
				ptrdiff_t AmountToCopy = min(ChunkSize - Buffers.Tail.Value.Data.length, Data.length);
				if(AmountToCopy > 0) { // It may be less than zero because of creating too large a buffer.
					Buffers.Tail.Value.Write(Data[0 .. AmountToCopy]);
					Data = Data[AmountToCopy .. $];
				}
				// The data that remains all goes into a possibly larger-than-chunksize buffer.
				// Note: Requires a dup because AllowStorage is false in this else if, but we can still optimize by using an existing buffer and copying into it.
				Buffer Next = Buffer.FromExistingData(Data.dup);
				Buffers ~= Next;
			}
		}
	}

	private void ProcessIfNeeded() {		
		// Basically, we don't want to actually manipulate the data in the main thread.
		// Instead, when we receive a notification that data is ready, we process the data in a worker thread.
		// This means we're limited to a certain number of threads, but it's not too big a deal. Remember that they're only used when data is actually moved.
		// Not to mention that most of the data operations should be asynchronous IO, such as with AIO or IOCP.
		// When we're just waiting for data, we don't need to waste a worker thread for it.
		// The IOManager gets to take care of this. We just need to make sure we don't queue the same action multiple times at once.		
		if(cas(cast(shared)&InDataOperation, cast(shared)false, cast(shared)true))
			Manager.QueueAction(this);
	}	

	/// Processes the flags returned by a DataSource. Returns whether more data should be handled for this source.
	bool ProcessFlags(DataRequestFlags Flags, DataOperation Operation) {		
		synchronized(StateLock) {
			// First, check if something caused a completion or abort during the operation itself:
			if(CompleteOnBreakType != CompletionType.Incomplete)
				return false;
		
			// Otherwise, if the operation is a write operation that's completely queued, tell it to notify when complete.
			// If it's a read, check if no data needs to be written and do the above.
			if((Flags & DataRequestFlags.Complete) != 0) {			
				if(Operation == DataOperation.Write) {
					OutputCompletionCallbackState = CompletionType.Successful;
					Output.InvokeNotifyCompletion(&NotifyOutputComplete);
				} else {
					IsInputComplete = true;
					if(Buffers.Count == 0) {					
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
	}	

	void NotifyOutputComplete() {		
		// Called from: Any Thread. Thread-safe: With locks.
		synchronized(StateLock) {			
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
		bool CheckCompletion() {
			synchronized(this) {
				bool Result = false;
				// We're complete when Output says we are, or when Input says we are and Output finishes.								
				if(Buffers.Count == 0 && IsInputComplete) {
					if(OutputCompletionCallbackState == CompletionType.Incomplete) {
						// Already processed this.
						assert(CompleteOnBreakType == CompletionType.Incomplete);
						OutputCompletionCallbackState = CompletionType.Successful;						
						Output.InvokeNotifyCompletion(&NotifyOutputComplete);
					}
					// In case they made Notify be blocking (which default implementation is).					
					Result = true;
				}				
				if(CompleteOnBreakType != CompletionType.Incomplete) {
					Result = true;
					NotifyComplete(CompleteOnBreakType, Untyped.init);
				}				
				return Result;
			}
		}
			
		// TODO: These have to become atomic. So it has to become TryRead and TryWrite, to write or read into a buffer.
		// ..probably should have given more information as to the why above, given that I'm not sure now.
		bool CanRead() {	
			synchronized(this) {			
				return !AreBuffersFull() && (WaitingOn & DataOperation.Read) == 0 && !IsInputComplete && CompleteOnBreakType == CompletionType.Incomplete;
			}
		}
		bool CanWrite() {				
			synchronized(this) {
				return Buffers.Count > 0 && (WaitingOn & DataOperation.Write) == 0 && CompleteOnBreakType == CompletionType.Incomplete;				
			}
		}	

		synchronized(this) {
			scope(exit)
				InDataOperation = false;
			try {
				// TODO: Split in to two parts; one with a buffer lock, one with a state lock.
				while(CanRead() || CanWrite()) {
					// Try to use buffers first as much as possible.				
					while(CanWrite()) {					
						ubyte[] BufferData = Buffers.Head.Value.Data;
						size_t NumHandled;
						DataRequestFlags Flags = Output.InvokeProcessNextChunk(BufferData, NumHandled);												
						if(NumHandled > 0) {								
							enforce(NumHandled <= BufferData.length);
							BufferData = BufferData[NumHandled..$];								
							if(BufferData.length == 0) {		
								if(Buffers.Count > 0)
									Buffers.Remove(Buffers.Head);
								//Buffers = (Buffers.length == 1 ? null : Buffers[1..$].dup);
							} else {
								Buffer Remaining = Buffer.FromExistingData(BufferData);
								Buffers.Head.Value = Remaining;
								//Buffers[0] = Remaining;
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
						// TODO: What happens if the above is asynchronous, returns Complete, and thus we have nothing in the buffer and InputComplete is true, but have data incoming?
						if(!ProcessFlags(Flags, DataOperation.Read))
							break;
					}
				}	
				if(CheckCompletion())
						return;			
			} catch (Throwable e) {
				NotifyComplete(CompletionType.Aborted, Untyped(e));				
				throw e;
			}					
		}
	}	

	void AttemptFinish(CompletionType Type) {	
		synchronized(this) {
			if(Status != CompletionType.Incomplete)
				return;
			if(InDataOperation)			
				CompleteOnBreakType = Type;
			else
				NotifyComplete(Type, Untyped.init);
		}
	}

	/// Called when this action is completed.
	protected override void OnComplete(CompletionType Status) {
		enforce(HasBegun, "Unable to finish an action that has not yet started.");
		CompleteOnBreakType = CompletionType.Incomplete;
		super.OnComplete(Status);
	}
}