/// A helper module to provide basic operations for vibe.d streams, such as writing or reading primitives.
/// All methods are implemented as UFCS extensions.
module dap.StreamOps;

import vibe.core.stream;
import ShardTools.ExceptionTools;
import std.traits;
import std.array;

/// Writes the given struct or primitive to the stream directly.
/// If T is an array, it will be written without any prefix or terminators.
void write(T)(OutputStream stream, T val) if(!is(T == class) && !is(T == interface))  {
	static if(isArray!T) {
		stream.write(cast(ubyte[])val);
	} else {
		stream.write(cast(ubyte[])(&val)[0..1]);
	}
}

/// Forwards to write for situations where UFCS is used and write!T is not considered valid due to a compiler bug.
void writeVal(T)(OutputStream stream, T val) if(!is(T == class) && !is(T == interface))  {
	write!T(stream, val);
}

/// Writes the given array with an int32 prefix indicating the length of the array.
void writePrefixed(T)(OutputStream stream, T[] val) if(!is(T == class) && !is(T == interface)) {
	static if(size_t.max > uint.max) {
		if(val.length > uint.max)
			throw new NotSupportedException("Writing arrays with a length greater than int.max is not supported.");
	}
	write(stream, cast(int)val.length);
	stream.write(cast(ubyte[])val);
}

/// Reads the given type from the stream. Reading arrays in this form is not allowed.
T read(T)(InputStream stream) if(!is(T == class) && !is(T == interface)) {
	ubyte[T.sizeof] bytes;
	stream.read(bytes);
	return *(cast(T*)bytes.ptr);
}

/// Forwards to write for situations where UFCS is used and write!T is not considered valid due to a compiler bug.
T readVal(T)(InputStream stream) if(!is(T == class) && !is(T == interface)) {
	return read!T(stream);
}

/// Reads an array with the given length (in elements) from the stream.
T[] readArray(T)(InputStream stream, size_t length) if(!is(T == class) && !is(T == interface)) {
	T[] result = minimallyInitializedArray!(T[])(length);
	stream.read(cast(ubyte[])result);
	return result;
}

/// Reads an array prefixed with an int32 length from the stream.
T[] readPrefixed(T)(InputStream stream) {
	size_t length = cast(size_t)read!int(stream);
	return readArray!T(stream, length);
}