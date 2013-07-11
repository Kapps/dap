module ShardTools.Untyped;
private import core.memory;
import std.conv;
import std.traits;
import ShardTools.ExceptionTools;
import std.exception;

mixin(MakeException("InvalidCastError", "The type stored in Untyped did not match the given type."));

/// Provides a lightweight structure to store a value without type information.
/// The result must be the exact same type as was passed in.
/// Details on how the data is stored are subject to change and should not be relied upon.
struct Untyped  {	

	this(T)(T Value) {
		StoredType = typeid(T);
		static if(is(T == class)) {
			Data = cast(void*)Value;
		} else {
			// Optimization for small values.
			static if(T.sizeof <= (void*).sizeof)
				Data = cast(void*)Value;
			else {
				Data = GC.malloc(T.sizeof);
				*(cast(T*)Data) = Value;
			}
		}
	}

	T opCast(T)() {
		return get!T;
	}
	
	/// Gets the type that's stored within this instance.
	@property TypeInfo type() {
		return StoredType;	
	}

	/// Gets the underlying value as the given type.
	/// This must be the exact type of the value that was passed in.
	@property T get(T)() {
		TypeInfo ti = typeid(T);
		if(StoredType !is ti)
			throw new InvalidCastError("Unable to cast from " ~ to!string(StoredType) ~ " to " ~ to!string(ti) ~ ".");
		static if(is(T == class)) {
			return cast(T)Data;
		} else {
			static if(T.sizeof <= (void*).sizeof) {
				return cast(T)Data;
			} else {
				T* ptr = cast(T*)Data;
				return *ptr;
			}
		}
	}

	bool opEquals(T)(T other) {
		T OtherVal;
		static if(is(T == Untyped)) {
			if(StoredType !is other.StoredType)
				return false;
			OtherVal = cast(T)other;
		} else {
			if(typeid(other) !is StoredType)
				return false;
			OtherVal = other;
		} 
		return OtherVal == get!T;
	}

	private TypeInfo StoredType;
	private void* Data;


	unittest {
		auto stored = Untyped(2);
		assert(cast(int)stored == 2);
		assert(stored == 2);
		assert(stored != 3);
		assert(stored != 2f);
		assert(stored != Untyped(3));
		assert(stored == Untyped(2));
		assertThrown!(InvalidCastError)(cast(float)stored);
		auto a = new Object();
		auto b = new Object();
		auto c = Untyped(a);
		assert(cast(Object)c == a);
		assert(cast(Object)c != a);
		assert(c == a);
		assert(c != b);
		Untyped d = null;
		assert(d is null);		
	}
}