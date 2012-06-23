module ShardIO.DataSource;
private import core.sync.mutex;
private import std.exception;
public import ShardIO.IOAction;

/// Indicates whether to do a read operation, write operation, or both a read and a write.
enum DataOperation {
	None = 0,
	Read = 1,
	Write = 2,
	Both = Read | Write
}

/// Provides flags for when data is requested from a DataSource.
enum DataRequestFlags {
	/// No flags are set.
	None = 0,
	/// The operation was successful, but more data may be available. If Waiting is not set, it may be queried immediately.
	Continue = 1,
	/// There was no data available. Will wait for more and then notify.
	Waiting = 2,
	/// This call marks the completion of this source's data. For an InputSource, this means the data should be written to then the Action complete. For an OutputSource, this means the action is complete.
	Complete = 4,	
}

/// Provides the base class for either an InputSource or OutputSource.
abstract class DataSource  {

public:
	/// Initializes a new instance of the DataSource object.
	this() {
		
	}

	/// Gets the action this DataSource is a part of.
	/// If this DataSource is not yet part of an action (because no IOAction has been created that uses it), this returns null.
	final @property IOAction Action() {		
		return _Action;
	}

package:

	void NotifyInitialize(IOAction Action) {
		Initialize(Action);
	}

protected:

	/// Called to initialize the DataSource after the action is set.
	/// Any DataSources that require access to the IOAction they are part of should use this to do so.
	void Initialize(IOAction Action) {	
		synchronized(this) {		
			this._Action = Action;
			Action.NotifyOnComplete(null, &OnCompleteInternal);
		}
	}

	private void OnCompleteInternal(void* State, AsyncAction Action, CompletionType Type) {
		OnComplete(cast(IOAction)Action, Type);
	}

	/// Occurs when the action completes for whatever reason.
	protected void OnComplete(IOAction Action, CompletionType Type) {

	}
	
private:		
	private IOAction _Action;
}