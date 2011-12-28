module ShardTools.Library;

import std.exception;
import core.runtime;

/// Represents a single library loaded at runtime.
/// It is generally assumed that any dynamic libraries needed will derive from this class for easier use.
/// If so, the derived class should be global, usually with the name of the library.
/// For example, using a library for ShardTools would mean 'class ShardTools : Library' in the global namespace.
/// Then it would be accessed with 'ShardTools.SomeGlobalMethod(2);'.
class Library  {

// TODO: How do we handle creating instances of classes and such?
// Ideally, should be able to do new SomeClass(2) for example. At worst, new MyLibrary.SomeClass(2).
// It's possible to work around it with ShardTools.CreateInstance!"SomeClass"(2) but that's ugly.
// Also, if we're doing above, just make this derive from Assembly which has things like CreateInstance or GetType or whatever.

public:
	/// Initializes a new instance of the Library object.
	/// Params:
	/// 	FilePath = The path to the library to load.
	this(in char[] FilePath) {
		this.FilePath = cast(immutable)FilePath;
	}

	/// Loads this library, returning this instance.
	Library Load() {
		enforce(Handle is null, "The library was already loaded.");
		Handle = enforce(Runtime.loadLibrary(FilePath), "Loading the library at " ~ FilePath ~ " failed.");
		return this;
	}

	~this() {
		if(Handle)
			enforce(Runtime.unloadLibrary(Handle), "Unloading the library at " ~ FilePath ~ " failed.");
	}
	
private:
	void* Handle;
	string FilePath;
	void*[string] CachedProcAddresses;
}