module ShardIO.DataSource;
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
// TODO: Allow an IsAsynchronous setting.
// For an InputSource, this means that it gives a callback to invoke upon data received, as opposed to NotifyDataReceived.
// For an OutputSource, this means that upon the final write (no need for all writes option because we can just use Waiting then), it invokes a callback when complete.
// Example of OutputSource: Overlapped IO. We can queue all the writes just fine, but after the last write, have to wait.
// Example of InputSource: Anything that returns a non-copyable array that must be freed prior to the end of the current stack frame.
public:
	/// Initializes a new instance of the DataSource object.
	this() {
		this._Action = Action;
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
		this._Action = Action;
	}
	
private:	
	private IOAction _Action;
}