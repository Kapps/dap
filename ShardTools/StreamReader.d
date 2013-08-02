﻿/// Scheduled to be deprecated upon completion of StreamOutput.
module ShardTools.StreamReader;
private import std.exception;
import core.stdc.string;
import std.traits;

/// Helper class to read a stream of bytes.
class StreamReader  {

	// TODO: Decide whether to use assert or enforce.
	// Definitely enforce, because a stream can always be malformed, and thus assert will lead to buffer overflows.
	private alias enforce ensure;

public:
	/// Initializes a new instance of the StreamReader object.
	/// Params:
	/// 
	this(ubyte[] Data, bool Copy) {
		if(Copy)
			Data = Data.dup;	
		this.Data = Data;
	}

	/// The number of bytes total.
	@property size_t Length() const {
		return Data.length;
	}

	/// The number of available bytes to be read.
	@property size_t Available() const {
		return Data.length - Position;
	}

	/// Reads a struct of the given type from the stream.
	/// Params:
	/// 	T = The type of struct to read.
	@property T Read(T)() if(!is(T == class) && !is(T == interface) && !isArray!T) {
		ensure(Available >= T.sizeof);
		ubyte[] Slice = Data[Position..Position + T.sizeof];
		ubyte* ptr = Slice.ptr;	
		T Result = *(cast(T*)ptr);
		Position += T.sizeof;
		return Result;
	}

	/// Reads Count elements into Buffer from the current position in the stream.
	/// Params:
	/// 	Buffer = The buffer to read elements into.
	/// 	Count = The number of elements to read.
	void ReadInto(void* Buffer, size_t Count) {
		ensure(Count <= Available);
		memcpy(Buffer, &this.Data[Position], Count);
		Position += Count;
	}
	
	/// Reads a null terminated string.
	string ReadTerminatedString() {
		// TODO: What a terrible implementation; optimize it.
		// Do just a slice, not N appends.
		string Result = "";
		for(size_t i = Position; i < Data.length; i++) {
			if(Data[i] == 0) {
				Position = i + 1;
				return Result;
			} else
				Result ~= cast(char)Data[i];
		}
		throw new Exception("String was not terminated.");
	}

	/// Returns the remaining data left to be read.
	/// Keep in mind that this array will get out of sync with the reader after any more calls to the reader.
	@property ubyte[] RemainingData() {
		return Data[Position..Length];
	}

	/// Reads an array of T with the given number of elements.
	/// Note that this array is still a reference to the underlying data, and should be duplicated if intended to be stored longer than the life of the reader.
	/// Params:
	/// 	Count = The number of elements to read.
	/// 	T = The type of struct to read.
	T[] ReadArray(T)(size_t Count) if(!is(T == class) && !is(T == interface)) {
		ensure(T.sizeof * Count <= Available);
		ubyte[] Section = Data[Position .. Position + (T.sizeof * Count)];
		T[] Result = cast(T[])Section;
		Position += Count * T.sizeof;
		return Result;
	}

	/// Reads a variable length number of T's from the stream, prefixed by an integer array length.
	/// Note that this array is still a reference to the underlying data, and should be duplicated if intended to be stored longer than the life of the reader.
	/// Params:
	/// 	T = The type of the struct to read.
	@property T[] ReadPrefixed(T)() if(!is(T == class) && !is(T == interface)) {
		ensure(int.sizeof <= Available);
		uint Count = Read!uint;
		return ReadArray!T(Count);
	}

	unittest {
		string String = "abc";
		int TestInt = 3;
		string OtherString = "test";
		int OtherLength = cast(int)OtherString.length;
		ubyte[] Data = cast(ubyte[])String ~ cast(ubyte)0 ~ (cast(ubyte*)&TestInt)[0..4] ~ (cast(ubyte*)&OtherLength)[0..4] ~ cast(ubyte[])OtherString;
		StreamReader Reader = new StreamReader(Data, false);
		assert(Reader.Available == Data.length);
		assert(Reader.Length == Data.length);
		string ReceivedString = Reader.ReadTerminatedString;		
		assert(ReceivedString == "abc");	
		int ReceivedInt = Reader.Read!int;	
		assert(ReceivedInt == 3);
		ReceivedString = Reader.ReadPrefixed!char().idup;
		assert(ReceivedString == "test");
		assert(Reader.Available == 0);
		assert(Reader.Length == Data.length);
	}
	
private:
	ubyte[] Data;
	size_t Position;
}