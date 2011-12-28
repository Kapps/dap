module ShardTools.Pool;
private import ShardTools.List;
private import ShardTools.Stack;
private import ShardTools.ConcurrentStack;
import ShardTools.IPoolable;

/// A class used to provide simple pooling of objects.
class Pool(T) {

public:
	/// Initializes a new instance of the Pool object.
	/// Initializing a Pool only creates the data to store the number of elements required.
	/// The caller should push default values into the pool.
	/// Params:
	///		Capacity = The maximum number of objects this Pool is capable of storing. 
	///					  Attempting to Push a value past the maximum size will simply ignore the call.
	///					  This value is a close estimate, but will not be exact due to threading issues. 	
	this(size_t Capacity) {
		this.Capacity = Capacity;		
		this.Elements = new List!(T)();		
	}

	/// Pushes the specified instance back into the pool.
	/// Params:
	///		Instance = The instance to push back in to the pool.
	void Push(T Instance) {		
		if(Elements.Count < Capacity)
			Elements.Add(Instance);		
	}

	/// Pops an object from the pool, initializing it and returning the initialized instance.	
	/// Returns:
	///		An initialized instance of the object to create, or init if the pool was empty.
	T Pop() {
		return Pop(T.init);	
	}
		
	/// Pops an object from the pool, initializing it and returning the initialized instance.
	/// Params:
	/// 	DefaultValue = The default value to use if there were no elements remaining.
	/// Returns:
	///		An initialized instance of the object to create, or DefaultValue if the pool was empty.
	T Pop(lazy T DefaultValue) {				
		if(Elements.Count == 0)
			return DefaultValue;
		T Result = Elements[0];
		Elements.RemoveAt(0);
		return Result;		
	}

	/// Gets a default pool for this type, lazily initialized with a maximum of 1024 elements.
	/// This pool is thread-local.
	@property static Pool!(T) Default() {
		if(_Default is null)
			_Default = new Pool!(T)(1024);
		return _Default;
	}
	
private:
	static Pool!(T) _Default;
	List!(T) Elements;	
	size_t Capacity;	
}

