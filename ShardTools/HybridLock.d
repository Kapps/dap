module ShardTools.HybridLock;

/// Provides a monitor that first attempts to use a Spinlock for a period of time, then switches to a Mutex.
version(None) class HybridLock : Object.Monitor {

public:
	/// Initializes a new instance of the HybridLock object.
	this() {
		
	}
	
private:
}