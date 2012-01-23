module ShardIO.IOManager;
private import std.stdio;
private import std.exception;
private import ShardIO.IOAction;
private import std.parallelism;


/// Manages any IOActions.
class IOManager  {

public:
	/// Initializes a new instance of the IOManager object.
	this(size_t NumWorkers = 0) {
		// TODO: DEBUG: REMEMBER TO REMOVE!
		debug NumWorkers = 8;
		if(NumWorkers == 0)
			Pool = new TaskPool();
		else
			Pool = new TaskPool(NumWorkers);		
		Pool.isDaemon = false; // Make sure all IO operations complete prior to the program ending.			
	}	

	/// Gets a default instance of the IOManager, lazily initialized with the same number of threads as the default TaskPool implementation.
	/// It is generally recommended to use this instance as opposed to creating your own. But there may be situations where more fine-grained control is desired,
	/// such as to prevent long operations from blocking smaller ones if there are too many of them.
	@property static IOManager Default() {
		if(_Default is null)
			_Default = new IOManager();
		return _Default;
	}

	/// Gets the number of worker threads this instance uses.
	@property size_t NumWorkers() const {
		return Pool.size;
	}

	/// Queues the given action to be executed.
	/// Params:
	/// 	Action = The action to queue.
	package void QueueAction(IOAction Action) {		
		//enforce(Action.HasBegun);
		Pool.put(task(&Action.ProcessData));
	}
	
private:
	TaskPool Pool;

	static IOManager _Default;
}