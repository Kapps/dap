module ShardIO.DataSource;
private import core.sync.mutex;
private import std.exception;
import ShardTools.Untyped;
public import ShardIO.IOAction;
import ShardIO.DataTransformerCollection;

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
/// DataSources are similar to one-way streams, with all methods being asynchronous.
/// DataSources can read or write a variable amount of data, ideally close to a certain limit.
/// Any data that can not be operated on immediately is buffered.
/// Once the buffers are getting close to being emptied, the DataSource requests additional data
/// from the other source.
abstract class DataSource  {

public:
	/// Initializes a new instance of the DataSource object.
	this() {
		this._DataTransformers = new DataTransformerCollection();
	}

	/// Gets the action this DataSource is a part of.
	/// If this DataSource is not yet part of an action (because no IOAction has been created that uses it), this returns null.
	final @property IOAction Action() {		
		return _Action;
	}
		
	// TODO: Implement this. There is some complications with it though.
	// First, we'd ideally transform as we send the source data. 
	// In fact, this is probably a requirement, as sources may expect any transformers they changeto take effect instantly.
	// Secondly, we'd want to transform in place.
	// Unfortunately, we can't easily do that, because we may have buffered it.
	// So this means that buffers will need to keep track of whether they were already transformed; easy enough.
	// Though now issues with who owns data being written? Don't remember at this point what rules for that are, but documented they are.
	// Lastly, transformers at this moment don't exactly indicate that they can transform in place. Indicate it.
	// But then what about when people don't want to transform in place? 
	// The logical solution is to create a copy of the data, but that's not ideal because the transformer may not perform in-place transforms.
	// So the transformer could get a boolean indicating whether it performs transforms in-place, but that then gets ugly.
	// Not to mention some operations may be able to be done in-place, and some not. Ex) Convert encoding. Different chars different size.
	/// Returns the DataTransformers operating on this DataSource.
	final @disable @property DataTransformerCollection DataTransformers() {
		return _DataTransformers;
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
			Action.NotifyOnComplete(Untyped.init, &OnCompleteInternal);
		}
	}

	private void OnCompleteInternal(Untyped State, AsyncAction Action, CompletionType Type) {
		OnComplete(cast(IOAction)Action, Type);
	}

	/// Occurs when the action completes for whatever reason.
	protected void OnComplete(IOAction Action, CompletionType Type) {

	}
	
private:		
	private IOAction _Action;
	private DataTransformerCollection _DataTransformers;
}