module dap.AssetBuilder;
import ShardTools.ConcurrentStack;
import ShardTools.TaskManager;
import ShardTools.Untyped;

alias void delegate(Untyped) CompletionTask;

/// Provides a means of building any assets passed in, in parallel.
class AssetBuilder {

	this() {
		builder = TaskManager.Global;
	}

	/// Asynchronously begins building all assets within the context.
	AsyncAction build() {
		return null;
	}

	TaskManager builder;
}

