module ShardTools.SpinLock;
private import core.thread;
private import core.atomic;

// TODO: Should probably have a SlimSpinLock that's just a single boolean.
// Use an alias, and use UFCS.

/// Provides a monitor that continuously attempts to acquire a lock until it succeeds.
/// Unlike Mutex, a single unlock will make the SpinLock available, until another lock call is made.
/// This means that SpinLock's are not re-entrant. SpinLocks also do not have any guaranteed ordering.
final class SpinLock : Object.Monitor {

public:
	/// Initializes a new instance of the SpinLock object.
	this() {
		
	}

	/// Attempts to acquire the lock, blocking until done.
	void lock() nothrow {
		bool GotLock;
		do {
			// Manually inline CAS, as it can not be inlined due to asm instructions.
			/+version(D_InlineAsm_X86_64) {
				asm {
					mov DL, 1;
					mov AL, 0;
					mov RCX, &HasLock;
					lock;
					cmpxchg [RCX], DL;
					setz AL;
				}
			} else version(D_InlineAsm_X86) {
				asm {
					mov DL, 1;
					mov AL, 0;
					mov ECX, &HasLock;
					lock;
					cmpxchg [ECX], DL;
					setz AL;
				}
			} else+/ {
				//static assert(0, "Temporarily disabled.");
				// TODO: Implement the above.					
				GotLock = cas(cast(shared)&HasLock, cast(shared)false, cast(shared)true);
			}
		} while(!GotLock);
	}

	/// Removes any existing locks, regardless of who owns them.
	void unlock() nothrow {
		// TODO: Do we need to atomic store here? I assume not...
		HasLock = false;
	}

	/// Attempts once to acquire a lock, returning whether it was acquired.
	bool tryLock() nothrow {		
		return cas(cast(shared)&HasLock, false, true);		
	}
	
private:
	bool HasLock = false;
	
}