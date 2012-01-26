﻿module ShardTools.NativeReference;
private import std.exception;
private import std.container;


/// A helper class used to keep a reference to a desired object, ensuring the garbage collector knows about it while it gets passed into non-GC code.
class NativeReference  {

public static:

	/// Adds a reference to the given object.
	/// Params:
	/// 	Obj = The object to add a reference to.
	void AddReference(void* Obj) {
		synchronized(typeid(NativeReference)) {
			if(Objects is null)
				Objects = new Collection();
			Objects.insert(Obj);
		}
	}
	
	/// Removes a single reference to the given object.
	/// Params:
	/// 	Obj = The object to remove the reference to.
	void RemoveReference(void* Obj) {
		synchronized(typeid(NativeReference)) {	
			if(Objects is null)
				Objects = new Collection();
			enforce(Objects.removeKey(Obj) == 1, "The object to remove was not found.");
		}
	}
	
private static:
	alias RedBlackTree!(void*) Collection;
	__gshared Collection Objects;
}