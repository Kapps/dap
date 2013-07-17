module ShardTools.MemoryCache;
private import std.functional;
import std.datetime;
import MessagePack;
import std.array;
import std.typecons;
import ShardTools.AsyncAction;

// TODO: For LMC, consider a Least Recently Used approach instead of worrying about size vs access count.
// TODO: For LMC determine if memory is low and try to FreeUntil 20% memory available.

/// Provides access to a hash-based memory cache that keeps track of how often an object is accessed and expels infrequently accessed objects when needed.
/// The base class exposes the most basic API that all providers should implement.
/// Additional features, such as operating on sets or performing operations on stored objects may be exposed by subclasses.
/// All operations operate on a snapshot of the value, by default serialized with MessagePack.
/// This means that any changes to the value after a call to Set will not be visible after getting the value again.
/// All operations in this class are thread-safe.
@disable shared class MemoryCache {

public:

	// TODO: Move below into LocalMemoryCache.
	// Things like memcached may have this set in the config and we can't change it.
	/+/// Initializes a new instance of the MemoryCache object.
	this(size_t MaxSize, size_t MaxSizePerObject) {
		this._MaxSize = MaxSize;
		this._MaxSizePerObject = MaxSizePerObject;	
	}

	/// Gets the maximum size, in bytes, that this cache can store.
	@property size_t MaxSize() const {
		return	_MaxSize;
	}

	/// Gets the maximum size of a single object stored in the cache.
	/// Objects with a larger size than this will never be stored.
	@property size_t MaxSizePerObject() const {
		return _MaxSizePerObject;
	}+/

	/// Returns a global memory cache instance to use.
	/// If a specific instance is not assigned prior to being accessed, a LocalMemoryCache of 1/8th of total RAM is used.
	/// It is possible to change this value once it has already been created, but the old cache will remain until garbage collected.
	@property static MemoryCache Global() {
		if(_Global is null) {
			synchronized(typeid(typeof(this))) {
				throw new NotImplementedError();
				//_Global = new LocalMemoryCache();
			}
		}
		return _Global;
	}

	/// Gets the value associated with the specified key, evaluating and returning DefaultValue if a value for the Key was not found.
	final T Get(T)(string Key, lazy T DefaultValue) {
		T Result;
		if(!TryGet(Key, Result))
			Result = DefaultValue();
		return Result;
	}

	/// Gets the object with the given key from the cache.
	/// If no object with the key is found, DefaultValue will be evaluated and stored.
	/// Either the retrieved value or newly created value is returned.
	final T GetOrStore(T)(string Key, lazy T DefaultValue) {
		T Result;
		if(TryGet(Key, Result))
			return Result;
		Result = DefaultValue();
		Set(Key, Result);
		return Result;
	}

	/// Attempts to get the value associated with the given key, returning if successful.
	/// Params:
	/// 	KeyType = The type of the key for the object.
	/// 	ValueType = The type of the value of the object.
	/// 	Key = The key associated with the object.
	/// 	Value = The Value, which will be populated with the result if successful, or assigned to init if this function returns false.
	final bool TryGet(KeyType, ValueType)(KeyType Key, out ValueType Value) {
		ubyte[] Data = PerformGet(Key);
		if(Data.empty)
			return false;
		Value = Deserialize!(T)(Data);
		return true;
	}

	/// Removes the object with the given key from the cache.
	/// If the key is not found, no operation is performed.
	final void Remove(string Key) {
		PerformRemove(Key);
	}

	/// Sets the given key to be associated with the specified value.
	/// If a value already exists for this key, it is replaced.
	void Set(ValueType)(string Key, ValueType Value) {
		ubyte[] Data = Serialize(Value);
		PerformSet(Key, Data);
	}

protected:

	/// Serializes the given value, returning an array of bytes to store.
	/// At the moment this will always use MessagePack, as templates can not be overriden.
	ubyte[] Serialize(T)(T Value) {
		return pack(Value);
	}

	/// Deserializes the given data, returning an object of type T.
	/// If the value passed in was not of type T, an exception is thrown.
	T Deserialize(T)(ubyte[] Data) {
		T result;
		unpack(Data, result);
		return result;
	}

	/// Override to add or replace the value associated with the given key.
	abstract void PerformSet(string Key, ubyte[] Data);

	/// Override to return the value associated with the given key.
	/// If the key is not found, null should be returned.
	/// Once the action is complete, the completion data should be a byte[] containing the serialized data.
	abstract AsyncAction PerformGetAsync(string Key);

	/// Performs a synchronous get request.
	/// The default implementation simply waits on PerformGetAsync.
	ubyte[] PerformGet(string Key) {
		AsyncAction Action = PerformGetAsync(Key);
		Action.WaitForCompletion();
		if(Action.Status != CompletionType.Successful) {

		}
		assert(0);
	}

	/// Override to remove the value associated with the given key.
	/// If the key is not found, no operation should be performed.
	abstract void PerformRemove(string Key);

	
private:
	static __gshared MemoryCache _Global;
}