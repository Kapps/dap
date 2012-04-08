module ShardTools.ThreadPool;
private import std.exception;
private import core.thread;
private import ShardTools.NativeReference;
private import std.parallelism;

version(NoWTP) {
	
} else {
	version(Windows) {
		// Because the ThreadPool implementation on Windows is Vista or higher, NoWTP can be passed in to use the TaskPool instead.
		//version=WindowsThreadPool;
	}
}

version(WindowsThreadPool) {
	extern(Windows) {
		void* CreateThreadpoolWork(void*, void*, void*);
		void SubmitThreadpoolWork(void*);
		void CloseThreadpoolWork(void*);
		void CloseThreadpool(void*);
		void* CreateThreadpool(void*);
		void SetThreadpoolThreadMaximum(void*, size_t);
		void SetThreadpoolThreadMinimum(void*, size_t);
		void InitializeThreadpoolEnvironment(void*);
		void SetThreadpoolCallbackPool(void*, void*);
	}
}

/// Provides access to a ThreadPool using either the OS implementation, or a fallback to TaskPool.
class ThreadPool  {

public:
	
	/// Creates a new ThreadPool with the given number of worker threads.
	/// Params:
	/// 	NumWorkers = The number of worker threads, or zero for a default value.
	this(size_t NumWorkers = 0) {
		version(WindowsThreadPool) {
			// TODO: Figure out actual implementation.
			_PoolPtr = CreateThreadpool(null);
			SetThreadpoolThreadMaximum(_PoolPtr, NumWorkers);
			SetThreadpoolThreadMinimum(_PoolPtr, NumWorkers);
			InitializeThreadpoolEnvironment(cast(void*)&_EnvPtr);
			SetThreadpoolCallbackPool(&_EnvPtr, _PoolPtr);
			enforce(_PoolPtr);
		} else {
			if(NumWorkers == 0)
				_TaskPool = new TaskPool();
			else
				_TaskPool = new TaskPool(NumWorkers);
		}
	}

	~this() {
		version(WindowsThreadPool) {
			CloseThreadpoolWork(_PoolPtr);
		}
	}

	/// Gets a default instance of ThreadPool to use.
	/// When a TaskPool is used, this default pool uses the default TaskPool; otherwise, it uses the default pool for whatever the OS-specific ThreadPool is when possible.
	static ThreadPool Default() {
		if(_Default is null) {
			synchronized {
				if(_Default is null)
					_Default = new ThreadPool(true);				
			}
		}
		return _Default;
	}

	private this(bool DefaultImplementationFlagUnused) {
		this._IsDefault = true;
		version(WindowsThreadPool) {
			_PoolPtr = null;
		} else {
			_TaskPool = taskPool;
		}
	}
	
	/// Queues the given task to be executed.
	/// State is guaranteed to have a reference to it even though it may be going outside garbage collector bounds.
	void Queue(void* State, void delegate(void*) WorkCallback) {
		version(WindowsThreadPool) {
			QueuedWork* Work = new QueuedWork();
			NativeReference.AddReference(Work);
			Work.UserState = State;
			Work.WorkCallback = WorkCallback;			
			void* lpWork = CreateThreadpoolWork(&OnThreadPoolWork, Work, _PoolPtr);			
			assert(lpWork);
			SubmitThreadpoolWork(lpWork);
			CloseThreadpoolWork(lpWork);
		} else {
			_TaskPool.put(task(WorkCallback, State));			
		}
	}
	
private:	
	// Register our ThreadPool threads with the GC if needed.
	static bool IsThreadRegistered; // Thread-local
	static __gshared ThreadPool _Default;

	bool _IsDefault;
	version(WindowsThreadPool) {
		void* _PoolPtr;
		void* _EnvPtr;
	} else {
		TaskPool _TaskPool;
	}

	version(WindowsThreadPool) extern(Windows) static void OnThreadPoolWork(void* instance, void* State, void* lpWork) {
		if(!IsThreadRegistered) {
			synchronized {
				if(!IsThreadRegistered) {
					thread_attachThis();
					IsThreadRegistered = true;
				}
			}
		}
		QueuedWork* Work = cast(QueuedWork*)State;
		NativeReference.RemoveReference(Work);
		Work.WorkCallback(Work.UserState);
	}

	version(WindowsThreadPool) struct QueuedWork {
		void* UserState;		
		void delegate(void*) WorkCallback;
	}
}