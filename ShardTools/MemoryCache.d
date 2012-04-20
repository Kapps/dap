module ShardTools.MemoryCache;
private import ShardTools.LocalMemoryCache;
private import std.functional;

// TODO: Consider a Least Recently Used approach.

/// Provides access to a hash-based memory cache that keeps track of how often an object is accessed and expels infrequently accessed objects when needed.
@disable class MemoryCache  {

public:
	/// Initializes a new instance of the MemoryCache object.
	this(size_t MaxSize, size_t MaxSizePerObject) {
		this._MaxSize = MaxSize;
		this._MaxSizePerObject = MaxSizePerObject;	
	}

	/// Gets the maximum size, in bytes, that this cache can store.
	@property size_t MaxSize() const {
		return	_MaxSize;
	}

	/// Gets the maximum size of a single object stored in the cache.
	/// Objects with a higher size than this will never be stored.
	@property size_t MaxSizePerObject() const {
		return _MaxSizePerObject;
	}

	/// Returns a global memory cache instance to use. The actual implementation used is undefined.
	/// Once this property has been accessed, it is unable to be changed.
	/// However, it may be set prior to being accessed.
	/// If a specific instance is not assigned prior to being accessed, a LocalMemoryCache of 64 megabytes is used.
	@property static MemoryCache Global() {
		if(_Global is null) {
			synchronized(typeid(typeof(this))) {
				assert(0);
				//_Global = new LocalMemoryCache();
			}
		}
		return _Global;
	}

	/// Gets the object with the given key from the cache.
	/// If no object with the key is found, fun will be invoked and the return value stored and associated with Key.
	/// Params:
	/// 	fun = A function to return the object to store.
	/// 	KeyType = The type of the key for the object.
	/// 	ValueType = The type of the value of the object.
	/// 	Key = The key that the object is associated with.
	void GetOrStore(alias fun, KeyType, ValueType)(KeyType Key) if(is(typeof(unaryFun!fun))) {
		
	}

	/// Attempts to get the value associated with the given key, returning if successful.
	/// Params:
	/// 	KeyType = The type of the key for the object.
	/// 	ValueType = The type of the value of the object.
	/// 	Key = The key associated with the object.
	/// 	Value = The Value, which will be populated with the result if successful, or assigned to init if this function returns false.
	bool TryGet(KeyType, ValueType)(KeyType Key, out ValueType Value);

	/// Removes the object with the given key from the cache.
	void Remove(KeyType)(KeyType Key);

	/// Replaces the object already associated with the given Key, with the specified Value.
	/// Inheriting:
	/// 	The default implementation of this method calls Remove followed by Store, an implementor may wish to optimize it.
	void Replace(KeyType, ValueType)(KeyType Key, ValueType Value) {
		
	}

protected:

	/// Removes objects from the cache until at least Bytes bytes are available.
	void ExpelUntil(size_t Bytes) {

	}

	/// Removes the next object from the cache.
	void ExpelNextObject() {
		
	}
	
private:
	size_t _MaxSize;
	size_t _MaxSizePerObject;
	void*[hash_t] Objects;

	static MemoryCache _Global;

	struct ObjectReference {
		size_t TimesAccessed;
		size_t SizeInBytes;
		void* Value;
	}	
}

// TODO: Store CacheElements and such. This way, even if not stored in memory, we can see how often accessed and thus whether to store.

/// Provides a single cacheable object.
class CachedObject {
	size_t SizeInBytes;
	size_t NumAccesses;
	void* CachedValue;
	bool IsCached;
}