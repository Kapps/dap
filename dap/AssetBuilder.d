module dap.AssetBuilder;
import ShardTools.ConcurrentStack;
import ShardTools.TaskManager;
import ShardTools.Untyped;

alias void delegate(Untyped) CompletionTask;

/// Provides a means of building any assets passed in, in parallel.
class AssetBuilder {

	this() {
		completionTasks = new typeof(completionTasks)();
		builder = TaskManager.Global;
	}
	
	
	/// Creates an AsyncAction that gets completed when there are no assets remaining that need to be built.
	/// It is still possible for other tasks to be added after the completion is notified, but the callback will only be invoked the first time there are no assets remaining.
	void notifyOnComplete(CompletionTask callback) {
		
	}
	
	ConcurrentStack!CompletionTask completionTasks;
	TaskManager builder;
}

