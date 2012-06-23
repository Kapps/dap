module ShardTools.Spinlock;
private import core.thread;
private import core.atomic;

/// Provides a monitor that continuously attempts to acquire a lock until it succeeds.
/// Unlike Mutex, a single unlock will make the Spinlock available, until another lock call is made.
class Spinlock : Object.Monitor {

public:
	/// Initializes a new instance of the Spinlock object.
	this() {
		
	}

	/// Attempts to acquire the lock, blocking until done.
	void lock() {
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
				version(GNU) {
					synchronized {
						if(!HasLock) {
							HasLock = true;
							GotLock = true;
						}
					}
				} else	
					GotLock = cas(cast(shared)&HasLock, cast(shared)false, cast(shared)true);
			}
		} while(!GotLock);
	}

	/// Removes any existing locks, regardless of who owns them.
	void unlock() {
		HasLock = false;
	}

	/// Attempts once to acquire a lock, returning whether it was acquired.
	bool tryLock() {		
		bool GotLock = cas(cast(shared)&HasLock, false, true);
		return GotLock;
	}
	
private:
	bool HasLock = false;
	
}