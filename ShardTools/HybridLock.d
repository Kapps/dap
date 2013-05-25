module ShardTools.HybridLock;
/+
 + Is this necessary? Wouldn't this be the default? I'm not sure...
 + Also, if the Spinlock isn't re-entrant or ordered, the Mutex wouldn't be either, has to have the lowest common set of properties.
/// Provides a monitor that first attempts to use a Spinlock for a period of time, then switches to a Mutex.
@disable class HybridLock : Object.Monitor {

public:
	/// Initializes a new instance of the HybridLock object.
	this() {
		
	}
	
private:
}+/