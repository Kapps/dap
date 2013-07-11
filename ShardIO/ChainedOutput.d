module ShardIO.ChainedOutput;

import ShardIO.OutputSource;
/+
/// An OutputSource used to chain input to multiple sources.
@disable class ChainedOutput : OutputSource {
// TODO: This shall be annoying to implement.
// Need to keep track of Waitings and things like that. This also means it's as slow as the slowest operation unless this class internally buffers.
// But then it uses much more memory than needed. T'is a lose-lose situation.

public:
	/// Initializes a new instance of the ChainedOutput object.
	this(OutputSource[] Outputs...) {
		this.Outputs = Outputs.dup;
	}

protected:

	/// Must be overridden if ProcessNextChunk completes asynchronously.
	/// Called after the last call to ProcessNextChunk, with a callback to invoke when the chunk is fully finished being processed.
	/// For example, when using overlapped IO, the callback would be invoked after the actual write is complete, as opposed to queueing the write.
	/// The base method should not be called if overridden.
	override void NotifyOnCompletion(void delegate() Callback) {
		foreach(OutputSource Output; Outputs)
			Output.NotifyOnCompletion(&NotifyCompleteCallback);
	}
	
private:

	void NotifyCompleteCallback() {
		
	}

	OutputSource[] Outputs;
	size_t NumSourcesComplete;
}+/