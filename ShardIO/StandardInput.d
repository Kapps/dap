module ShardIO.StandardInput;
private import core.thread;
private import std.parallelism;
public import ShardIO.InputSource;
private import ShardTools.Buffer;
private import std.stdio;

/// Provides an input source that reads from the standard input stream on a per-line basis.
class StandardInput : InputSource {

public:
	/// Initializes a new instance of the StandardInput object.
	this(IOAction Action) {
		super(Action);
		BufferedData = new Buffer(1024);
		Action.Completed.Add(&OnActionComplete);
		auto t = task(&WorkerThread);
		taskPool.put(t);
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
	///		Any Data passed in will have ownership transferred away from the caller if DataFlags includes the AllowStorage bit.
	override DataRequestFlags GetNextChunk(size_t RequestedSize, scope void delegate(ubyte[], DataFlags) Callback) {
		synchronized(this) {
			ubyte[] Data = BufferedData.Data;
			DataRequestFlags ResultFlags = IsComplete ? DataRequestFlags.Complete : (DataRequestFlags.Waiting | DataRequestFlags.Continue);
			if(Data.length == 0)
				Callback(null, DataFlags.None);			
			else {
				Callback(Data, DataFlags.None);
				BufferedData.Reuse(false);
			}
			return ResultFlags;
		}
	}

	/// Instructs the StandardInput source to stop waiting for new data, after going through the remainder of it's data.
	void Complete() {
		synchronized(this) {
			IsComplete = true;
		}
	}
	
private:
	Buffer BufferedData;
	bool IsComplete = false;

	void OnActionComplete(IOAction Action, CompletionType Type) {
		IsComplete = true;
	}

	void WorkerThread() {
		while(!IsComplete) {			
			foreach(string Line; lines(stdin)) {				
				synchronized(this) {
					if(Line.length >= 1 && Line[$-1] == '\n' && (Line.length < 2 || Line[$-2] != '\r'))
						Line = Line[0..$-1] ~ "\r\n";
					BufferedData.Write(Line);
					NotifyDataReady();
				}				
				if(IsComplete)
					break;
			}			
			Thread.sleep(dur!"msecs"(1));
		}
	}
}