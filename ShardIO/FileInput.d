module ShardIO.FileInput;
private import std.conv;
private import std.stdio;
private import ShardTools.BufferPool;
private import std.algorithm;
private import ShardTools.Buffer;
private import std.file;
public import ShardIO.AsyncFile;

import ShardIO.InputSource;

/// A DataSource that asynchronously reads input from a file.
class FileInput : InputSource {

public:
	/// Initializes a new instance of the FileInput object.
	/// Params:
	/// 	File = The file to read input from. Input is read starting from the beginning of the file. The file must be open. The file will be closed after the source is fully read.
	this(AsyncFile File) {		
		this.File = File;
		Offset = 0;
		Length = File.Size;		
		ChunkSize = Action.DefaultChunkSize;
		LoadChunk();	
	}		

	/// Initializes a new instance of the FileInput object.
	/// Params:
	/// 	FilePath = The path to the file to read input from. An exception is thrown if it does not exist.
	this(string FilePath) {
		if(!exists(FilePath))
			throw new FileNotFoundException("The file at " ~ FilePath ~ " was not found.");
		AsyncFile File = new AsyncFile(FilePath, FileAccessMode.Read, FileOpenMode.Open, FileOperationsHint.Sequential);
		this(File);
	}

	/// Called by the IOAction after this InputSource notifies it is ready to have input received.
	/// The InputSource should have roughly RequestedSize bytes ready and then invoke Callback with the available data.
	/// If the InputSource is unable to get an acceptable number of bytes without blocking, then Waiting should be returned.
	/// The RequestedSize parameter is only a hint; as much or little data may be passed in as desired. The unused data will then be buffered.
	/// See $(D, DataRequestFlags) and $(D, DataFlags) for more information as to what the allowed flags are.
	/// Params:
	///		RequestedSize = A rough number of bytes requested to be passed into Callback. This is simply to prevent buffering too much, so if the data is already in memory, just pass it in.
	///		Callback = The callback to invoke with the data.
	protected override DataRequestFlags GetNextChunk(size_t RequestedSize, scope void delegate(ubyte[], DataFlags) Callback) {		
		synchronized(this) {
			Buffer Next;
			if(Caches.length == 0)
				Next = null;
			else {
				Next = Caches[0];
				Caches = Caches[1..$].dup;
			}
			if(!Next) {
				Callback(null, DataFlags.None);
				return DataRequestFlags.Waiting | DataRequestFlags.Continue;
			}
			ChunkSize = Action.ChunkSize;
			DataFlags Flags = DataFlags.None;
			Callback(Next.Data, Flags);
			Processed += Next.Data.length;
			BufferPool.Global.Release(Next);
			if(Offset < Length)
				LoadChunk();
			if(Processed >= Length) {
				assert(Caches.length == 0);
				return DataRequestFlags.Complete;			
			}
			if(Caches.length > 0)
				return DataRequestFlags.Continue;
			return DataRequestFlags.Waiting | DataRequestFlags.Continue;
		}
	}

	/// Called to initialize the DataSource after the action is set.
	/// Any DataSources that require access to the IOAction they are part of should use this to do so.
	protected override void Initialize(IOAction Action) {
		super.Initialize(Action);
		ChunkSize = Action.ChunkSize;
	}
	
private:
	ulong Offset;
	ulong Length;
	ulong Processed;
	size_t ChunkSize;	
	Buffer[] Caches;
	AsyncFile File;

	void LoadChunk() {
		synchronized(this) {
			size_t BytesToRead = min(Length - Offset, ChunkSize);			
			Buffer buffer = BufferPool.Global.Acquire(BytesToRead);			
			File.Read(buffer.FullData[0 .. BytesToRead], Offset, cast(void*)buffer, &ReadCallback);
			Offset += BytesToRead;
		}
	}

	private void ReadCallback(void* State, ubyte[] Data) {
		synchronized(this) {
			Buffer Original = cast(Buffer)State;
			Original.AdvancePosition(Data.length);
			Caches ~= Original;
			assert(Data == Original.Data);			
			NotifyDataReady();			
		}
	}
}