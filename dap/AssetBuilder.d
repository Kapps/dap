module dap.AssetBuilder;

/// Provides a means of building any assets passed in, in parallel.
class AssetBuilder {

	this() {
		
	}
	
	
	/// Creates an AsyncAction that gets completed when there are no assets remaining that need to be built.
	/// It is still possible for other tasks to be added after the completion is notified, but the callback will only be invoked the first time there are no assets remaining.
	void notifyOnComplete() {
		
	}
	
	ConcurrentStack!CompletionTask completionTasks;
	TaskManager builder;
}

