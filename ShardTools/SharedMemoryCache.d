module ShardTools.SharedMemoryCache;
public import ShardTools.MemoryCache;

version(None) {
/// Represents a MemoryCache implementation that uses shared memory to store objects.
class SharedMemoryCache : MemoryCache {

public:
	/// Initializes a new instance of the SharedMemoryCache object.
	private this() {
		
	}

	/// Opens an already existing shared memory cache.
	static SharedMemoryCache Open(string FileName) {
		assert(0);
	}
	
private:
}
}