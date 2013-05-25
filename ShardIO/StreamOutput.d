module ShardIO.StreamOutput;
import ShardTools.AsyncAction;

enum WaitMode {
	Block = 0,
	Yield = 1,
	Throw = 2
}
/// Provides an OutputSource that can be read from as a Stream, optionally awaiting until data is ready.
@disable class StreamOutput {
	this(bool AwaitAutomatically = false) {
		// Constructor code
	}
	
	AsyncAction NotifyAvailable(size_t Bytes) {
		assert(0);
	}
}

