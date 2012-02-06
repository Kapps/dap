module ShardIO.FileOutput;
import std.stdio : writeln;
private import core.atomic;
private import ShardIO.AsyncFile;
private import std.string;
private import core.stdc.stdio;

import ShardIO.OutputSource;
import core.stdc.stdlib;

/// Provides an OutputSource that appends to a file.
/// This OutputSource attempts to use asynchronous IO when possible, and falls back to fwrite when not.
/// The file remains open by this source for the entire duration.
class FileOutput : OutputSource {
// TODO: Needs support for non-append.
public:
	/// Initializes a new instance of the FileOutput object.
	/// Params:
	/// 	File = The file to append to. This file must remain open. It is closed automatically after completion.
	///		Action = The IOAction that will be using this OutputSource.
	this(AsyncFile File) {		
		this.File = File;
	}	

	/// Initializes a new instance of the FileOutput object.
	/// Params:
	/// 	FilePath = The path to the file to append to. It is created if it does not exist.
	///		Action = The IOAction that will be using this OutputSource.
	this(string FilePath) {
		AsyncFile File = new AsyncFile(FilePath, FileAccessMode.Write, FileOpenMode.OpenOrCreate, FileOperationsHint.Sequential);
		this(File);
	}

	/// Attempts to handle the given chunk of data.
	/// It is allowed to not handle the entire chunk; the remaining will be buffered and attempted to be written after NotifyReady is called.
	/// For details about the return value, see $(D, DataRequestFlags).
	/// In most situations, this function should return Continue. But if the source can't handle more data, then Complete should be returned.
	/// It is assumed that the write is fully handled by the end of this method. If this is not the case, then NotifyOnCompletion must be overridden.
	/// Params:
	///		Chunk = The chunk to attempt to process.
	///		BytesHandled = The actual number of bytes that were able to be handled.
	override DataRequestFlags ProcessNextChunk(ubyte[] Chunk, out size_t BytesHandled) {		
		synchronized(this) {		
			File.Append(Chunk, cast(void*)this, &WriteCompleteCallback);
			NumSent++;		
			BytesHandled = Chunk.length;		
			// TODO: Consider waiting until write callback.
			return DataRequestFlags.Continue;		
		}
	}

	
	/// Must be overridden if ProcessNextChunk completes asynchronously.
	/// Called after the last call to ProcessNextChunk, with a callback to invoke when the chunk is fully finished being processed.
	/// For example, when using overlapped IO, the callback would be invoked after the actual write is complete, as opposed to queueing the write.
	/// The base method should not be called if overridden.
	override void NotifyOnCompletion(void delegate() Callback) {
		synchronized(this) {
			CompletionCallback = Callback;
			AttemptCompletion();
		}
	}
	
private:
	AsyncFile File;
	size_t NumSent;
	size_t NumReceived;
	void delegate() CompletionCallback;	

	bool AttemptCompletion() {
		if(NumSent == NumReceived && CompletionCallback !is null) {
			File.Close();
			File = null;
			CompletionCallback();			
			return true;
		}
		return false;		
	}

	void WriteCompleteCallback(void* State) {
		synchronized(this) {
			NumReceived++;									
			AttemptCompletion();
		}
	}
}