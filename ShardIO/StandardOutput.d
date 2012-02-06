module ShardIO.StandardOutput;
private import std.exception;
private import std.string;
private import std.stdio;
private import std.parallelism;
private import ShardTools.Buffer;

import ShardIO.OutputSource;

enum StandardOutputSource {
	StdOut = 1,
	StdErr = 2
}

/// Provides an OutputSource to write to either stdout or stderr.
class StandardOutput : OutputSource {

public:
	/// Initializes a new instance of the StandardOutput object.
	this(StandardOutputSource Source) {		
		this._Source = Source;	
	}

	/// Gets the StandardOutputSource this OutputSource writes to.
	@property StandardOutputSource Source() const {
		return _Source;
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
			BytesHandled = Chunk.length;
			taskPool.put(task(&WriteOutput, cast(char[])Chunk));
			return DataRequestFlags.Continue;
		}
	}
	
private:	
	StandardOutputSource _Source;

	void WriteOutput(char[] Chunk) {
		synchronized(this) {
			final switch(Source) {
				case StandardOutputSource.StdOut:
					stdout.write(Chunk);
					stdout.flush();
					break;
				case StandardOutputSource.StdErr:
					stderr.write(Chunk);
					stderr.flush();
					break;
			}
			/*FILE* file = stdin.getFP();
			int NumWritten = 0;
			do {
				int Result = fprintf(file, "%s",  toStringz(Chunk));
				fflush(file);
				enforce(Result >= 0, "Unable to write to stdout or stderr.");
				NumWritten += Result;
				//fflush(std.c.stdio.stdin);
			} while(NumWritten < Chunk.length);*/
			//fflush(file);			
		}
	}
}