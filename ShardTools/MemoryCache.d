module ShardTools.MemoryCache;


/// Provides access to a hash-based memory cach
class MemoryCache  {

public:
	/// Initializes a new instance of the MemoryCache object.
	this() {
		
	}

	ValueType Get(ValueType, KeyType)(KeyType Key, lazy ValueType Default = ValueType.init) {
		hash_t hash = Key.opHash();
		void** lpPtr = (hash in Objects);
		if(lpPtr is null)
			return Default();
		return cast(ValueType)(*lpPtr);
	}
	
private:
	void*[hash_t] Objects;
}