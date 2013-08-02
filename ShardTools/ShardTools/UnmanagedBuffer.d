module ShardTools.UnmanagedBuffer;

/+ TODO: Fix compiler errors and get this working.
import core.stdc.stdlib;
import std.exception;
import std.conv;
import ShardTools.ExceptionTools;

mixin(MakeException("IndexOutOfRangeException", "The given index was out of range."));

/// Represents an unmanaged buffer in memory. Boundary checks are NOT performed, and thus it is very important to perform manual checks.
/// The buffer may or may not be managed by the garbage collector, and thus copying or storing it is not allowed.
struct UnmanagedBuffer  {

public:
	/// The number of bytes this buffer contains.
	const size_t length;

	/// The underlying buffer. This buffer is not in GC memory, and thus it is invalid to use it after this instance is deallocated.
	ubyte* buffer;

	/// Default constructor is disabled.
	@disable this();

	/// Copy constructor is disabled.
	@disable this(this);

	/// Creates a new unmanaged buffer of the specified size.
	/// Params:
	/// 	Size = The size, in bytes, that this buffer can hold.
	this(size_t Size) {
		buffer = cast(ubyte*)malloc(Size);
		enforce(buffer, "Unable to allocate " ~ to!string(Size) ~ " bytes, probably due to being out of memory");
		this.FreeOnDtor = true;
	}

	/// Provides a reference to an existing buffer of a given size.
	/// The existing data is not managed by this
	/// Params:
	/// 	Existing = The existing buffer to wrap.
	/// 	Length = The size of the existing buffer.
	this(void* Existing, size_t Length) {
		this.buffer = cast(ubyte*)Existing;
		this.length = length;
		this.FreeOnDtor = false;
	}

	/// Returns an array that represents the underlying buffer, subject to the same restrictions as the buffer.
	@property void[] array() {
		return buffer[0 .. length];
	}

	~this() {
		if(FreeOnDtor)
			free(buffer);
	}

	ubyte opIndex(size_t Index) {
		assert(Index < length);			
		return buffer[Index];
	}

	void opIndexAssign(size_t Index, ubyte Value) {
		assert(Index < length);
		buffer[Index] = Value;
	}
	
private:	
	bool FreeOnDtor;
}
+/