module ShardTools.AsyncAction;
private import std.functional;
private import std.range;
private import std.stdio;
private import core.sync.mutex;
private import ShardTools.ConcurrentStack;
private import std.container;
private import std.exception;
private import ShardTools.NativeReference;
private import core.thread;
private import std.datetime;
private import std.typecons;
public import std.variant;
private import ShardTools.ExceptionTools;

/// Indicates whether an AsyncAction is complete and whether it was aborted or finished successfully.
enum CompletionType {
	/// The action is not yet complete.
	Incomplete = 0,
	/// The action has been cancelled or aborted.
	Aborted = 1,
	/// The action completed successfully.
	Successful = 2
}

mixin(MakeException("TimeoutException", "An operation has timed out prior to completion."));

/// Provides information about an action executed asynchronously.
abstract class AsyncAction  {

public:
	
	alias void delegate(void*, AsyncAction, CompletionType) CompletionCallback;

	/// Initializes a new instance of the AsyncAction object.
	this() {
		NativeReference.AddReference(cast(void*)this);
		_TimeoutDuration = dur!"hnsecs"(0);
		_StartTime = Clock.currTime();
	}

	/// Indicates whether this action will ever time out if not completed within TimeoutTime.
	@property bool CanTimeout() const {
		return _TimeoutDuration.total!("hnsecs") > 0;
	}

	/// Indicates whether this action can be canceled, disregarding the current completion state of the action.
	@property bool CanAbort() const {
		return true;
	}

	/// Gets or sets the amount of time that an action can run before timing out.
	/// If CanTimeout is false, this will return zero.
	@property Duration TimeoutTime() const {
		return _TimeoutDuration;
	}

	/// Indicates when this action was started.
	@property const(SysTime) StartTime() const {
		return _StartTime;
	}

	/// Indicates how long has passed since the creation of this action.
	@property Duration Elapsed() const {
		return Clock.currTime() - _StartTime;
	}

	/// Indicates the status of this operation.
	@property CompletionType Status() const {
		return _Status;
	}

	/// Invokes the given callback when this action is complete or aborted.
	/// If the operation is already finished, Callback is invoked immediately and synchronously.
	/// Params:
	/// 	State = A user-defined value to pass in to Callback.
	/// 	Callback = The callback to invoke.
	void NotifyOnComplete(void* State, CompletionCallback Callback) {
		synchronized(this) {
			if(_Status == CompletionType.Incomplete) {
				CompletionSubscribers ~= cast(typeof(CompletionSubscribers[0]))tuple(State, Callback);
			} else {
				Callback(State, this, _Status);
			}
		}
	}

	/// Attempts to cancel this operation, either synchronously or asynchronously.
	/// Because this may be executed asynchronously, it is possible that the action will complete prior to being cancelled.
	/// If this is the case, the cancel operation will effectively do nothing.	
	/// Returns:
	/// 	Whether the action was successfully aborted; false if the action was already complete.
	bool Abort() {
		synchronized(this) {
			if(!CanAbort)
				throw new NotSupportedException("Attempted to abort an AsyncAction that does not support the Abort operation.");
			if(Status != CompletionType.Incomplete)
				return false;			
			return PerformAbort();
		}
	}

	/// Blocks the calling thread until this action completes. This has, at most, 1 millisecond precision.
	/// Returns the way in which this action was completed.
	/// Params:
	/// 	Timeout = A duration after which to throw an exception if not yet complete.
	CompletionType WaitForCompletion(Duration Timeout) {
		SysTime Start = Clock.currTime();
		while(_Status == CompletionType.Incomplete) {
			Thread.sleep(dur!"msecs"(1));
			SysTime Current = Clock.currTime();
			if((Current - Start) > Timeout)
				throw new TimeoutException();
		}
		return _Status;
	}

protected:
	
	/// Implement to handle the actual cancellation of the action.
	/// If an action does not support cancellation, CanCancel should return false, and this method should throw an error.
	abstract bool PerformAbort();

	/// Called when this action is completed.
	void OnComplete(CompletionType Status) {
		synchronized(this) {
			foreach(ref Subscriber; CompletionSubscribers) {
				Subscriber.Callback(Subscriber.State, this, Status);
			}
		}
	}
	
	/// Notifies this AsyncAction that the operation was completed.
	void NotifyComplete(CompletionType Status) {
		synchronized(this) {
			enforce(this.Status == CompletionType.Incomplete);
			enforce(Status == CompletionType.Successful || Status == CompletionType.Aborted);
			this._Status = Status;				
			NativeReference.RemoveReference(cast(void*)this);
			OnComplete(Status);
		}
	}

private:
	CompletionType _Status;
	Duration _TimeoutDuration;
	Tuple!(void*, "State", CompletionCallback, "Callback")[] CompletionSubscribers;
	SysTime _StartTime;
}

private class ActionManager {

	shared static this() {
		Actions = new RedBlackTree!AsyncAction();
		ToAdd = new ConcurrentStack!AsyncAction();
		ToRemove = new ConcurrentStack!AsyncAction();
	}

	static void RegisterAction(AsyncAction Action) {
		ToAdd.Push(Action);
		Action.NotifyOnComplete(null, toDelegate(&ActionComplete));
	}

	static void ActionComplete(void* State, AsyncAction Action, CompletionType Status) {
		ToRemove.Push(Action);
	}

	static void RunLoop() {
		while(true) {
			// Note that ToAdd must be first, in case it gets removed prior to a call.
			foreach(AsyncAction Action; ToAdd)
				Actions.insert(Action);
			foreach(AsyncAction Action; ToRemove)
				enforce(Actions.removeKey(Action) == 1);
			foreach(AsyncAction Action; Actions) {
				if(Action.CanTimeout && (Action.StartTime + Action.TimeoutTime) < Clock.currTime()) {
					// TODO: Raise a condition here when implemented... else this will just be hidden.
					// No way to really communicate to the action or to a main thread...
					// Most important is to abort the action.
					// TODO: Consider using some form of exception catching here, or throw an error.
					// Again, issue is any thrown exceptions just get hidden; an error may be needed.
					debug writeln("Action timeout.");					
					Action.Abort();										
				}
			}
			Thread.sleep(dur!"seconds"(1));
		}
	}

	// We want to make sure to not force a synchronize and thus delay any action from running yet blocking.
	// So, we wait until after Actions is accessed, and then carry out the calls that were made.
	private static __gshared ConcurrentStack!AsyncAction ToAdd;
	private static __gshared ConcurrentStack!AsyncAction ToRemove;

	private static __gshared RedBlackTree!AsyncAction Actions;
		
}