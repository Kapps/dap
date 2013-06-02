module ShardTools.IPoolable;

// This should be redone.
// It's inelegant and doesn't take advantage of D.
// Perhaps something with destroy and __ctor or emplace should be used, and arguments being specified in Get? But then that kinda defeats the purpose in a way.
// Also, Pool should just take a template type and no need for IPoolable at all, as it can be checked at compile-time.

/// An interface used to represent an object capable of being pooled.
@disable interface IPoolable {

	/// Initializes this object. Called when an object requests it from the pool either for the first time,
	/// or after it was released.
	/// Params:
	///		Parameters = Implementation-specific parameters used to initialize this object.
	void Initialize();

	/// Releases this object, freeing any memory it may be holding on to, and preparing it to be initialized when needed.
	/// Any sensitive data should be zeroed out at this step.
	/// This step should null any references to objects that may require Garbage Collection, so as not to prevent it.
	void Release();

}