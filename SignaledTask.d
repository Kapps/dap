module ShardTools.SignaledTask;
public import ShardTools.Event;
import std.typecons;

public import ShardTools.AsyncAction;
import ShardTools.Untyped;

/// Gets a task that is completed only by a call to the Complete method.
class SignaledTask : AsyncAction {

public:
	/// Creates a new SingaledTask that must be called manually.
	this() {
		
	}
	
	/// Notifies the signaled task that it has completed.
	void Complete(Untyped CompletionData) {
		this.NotifyComplete(CompletionType.Successful, CompletionData);
	}

	/// Notifies the signaled task that it has failed.
	void Abort(Untyped CompletionData) {
		this.NotifyComplete(CompletionType.Aborted, CompletionData);
	}
	
protected:

	/// Implement to handle the actual cancellation of the action.
	/// If an action does not support cancellation, CanAbort should return false, and this method should throw an error.
	override bool PerformAbort() {
		throw new NotImplementedError("PerformAbort");
	}

private:
}