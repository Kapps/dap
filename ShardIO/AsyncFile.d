module ShardIO.AsyncFile;
import std.stdio : write;
private import core.stdc.errno;
import std.stdio : writeln;
private import ShardTools.NativeReference;
import std.file : exists;
private import std.exception;
private import ShardTools.PathTools;
private import std.conv;
private import std.string;
private import std.parallelism;
public import core.stdc.stdio;

version(Windows) {
	private import core.sys.windows.windows;
	private import ShardIO.IOCP;

	enum : size_t {
		ERROR_ALREADY_EXISTS = 183,
		ERROR_FILE_EXISTS = 80
	}

	extern(Windows) {
		HANDLE WriteFile(HANDLE, const void*, size_t, size_t*, OVERLAPPED*);
	}
}

import ShardTools.ExceptionTools;

mixin(MakeException("FileNotFoundException"));
mixin(MakeException("AccessDeniedException"));
mixin(MakeException("FileAlreadyExistsException"));
mixin(MakeException("FileException"));

enum FileAccessMode {
	Read = 1,
	Write = 2,
	Both = Read | Write
}

/// Determines how to open a file.
enum FileOpenMode {
	/// Create a new file; throw if the file already exists.
	CreateNew = 1,
	/// Open an existing file; throw if the file does not exist.
	Open = 2,
	/// Open an existing file if it exists, or create a new one if it doesn't.
	OpenOrCreate = 3,
	/// Create a new file; replace the old one if the file already exists.
	CreateOrReplace = 4
}

/// Provides optional details about how the file will be accessed, allowing for more optimized IO.
enum FileOperationsHint {
	/// No hint is specified.
	None = 0,
	/// The file will be accessed randomly.
	RandomAccess = 1,
	/// The file will be accessed sequentially.
	Sequential = 2
}

/// Indicates the way that async operations are performed.
enum AsyncFileHandler {
	/// The basic fopen and fwrite mechanisms are used.
	Basic = 0,
	/// Windows' IO Completion Ports are being used.
	IOCP = 1,
	/// Posix's Async IO is being used.
	AIO = 2,
	/// OSX's kqueue is being used.
	KQueue = 3
}

alias void* AsyncFileHandle;

/// Represents a file that uses asynchronous IO for reads and writes.
/// BUGS:
///		At the moment when using the Basic AsyncFileHandler, it is easy to surpass the maximum number of file descriptors (roughly 70).
///		Eventually, consider supporting this. But keep in mind Basic is meant to be a fallback anyways, so that may not be an issue.
class AsyncFile  {

public:

	alias void delegate(void*) WriteCallbackDelegate;
	alias void delegate(void*, ubyte[]) ReadCallbackDelegate;

	/// Creates a new AsyncFile that operates on the file at the given path.
	/// Params:
	/// 	FilePath = The path to the file.
	/// 	Access = The way in which to access the file.
	/// 	OpenMode = Determines how to open the file. Must be valid for the Access type (Open/OpenOrCreate for Read, CreateNew/CreateOrReplace/OpenOrCreate for Write).
	/// 	Hint = An access hint for optimizing IO. Can be set to None for no specific hints.
	this(string FilePath, FileAccessMode Access, FileOpenMode OpenMode, FileOperationsHint Hint = FileOperationsHint.None) {
		FilePath = PathTools.MakeAbsolute(FilePath);
		if(Access == FileAccessMode.Read && (OpenMode != FileOpenMode.Open && OpenMode != FileOpenMode.OpenOrCreate))
			throw new FileException("Reading a file is only allowed with Open or OpenCreate file modes.");
		if(Access == FileAccessMode.Write && (OpenMode != FileOpenMode.CreateNew && OpenMode != FileOpenMode.CreateOrReplace && OpenMode != FileOpenMode.OpenOrCreate))
			throw new FileException("Writing a file is only allowed with CreateNew or CreateOrReplace file modes.");
		this._Handle = CreateHandle(FilePath, Access, OpenMode, Hint);
		IsOpen = true;
	}

	/// Indicates the controller being used for handling files.
	version(Windows) {
		enum AsyncFileHandler Controller = AsyncFileHandler.IOCP;
	} else {
		enum AsyncFileHandler Controller = AsyncFileHandler.Basic;
	}

	/// Indicates whether true asynchronous IO support is available, as opposed to synchronous operations in a new thread.
	enum bool SupportsTrueAsync = Controller != AsyncFileHandler.Basic;
	
	// TODO: This shall be problematic because you never know the actual offset.
	/+void Write(ulong Offset, ubyte[] Data, void* State, void delegate(void*) Callback) {
		
	}+/

	private static QueuedOperation* CreateOp(T)(void* State, ubyte[] Data, T Callback) {
		QueuedOperation* Op = new QueuedOperation();
		Op.State = State;
		Op.Data = Data;
		static if(is(T : ReadCallbackDelegate))
			Op.ReadCallback = Callback;
		else static if(is(T : WriteCallbackDelegate))
			Op.WriteCallback = Callback;
		else static assert(0);
		NativeReference.AddReference(cast(void*)Op);
		return Op;
	}

	/// Appends the given data to this file using asynchronous file IO.
	/// Params:
	/// 	Data = The data to append to the file.
	/// 	State = A user-defined object to pass into callback. Can be null.
	/// 	Callback = A callback to invoke upon completion. For best performance, this callback should be light-weight and not queue more data itself. It must be thread-safe.
	void Append(ubyte[] Data, void* State, WriteCallbackDelegate Callback) {		
		synchronized(this) {
			enforce(IsOpen && !WaitingToClose, "Unable to write to a closed file.");
			QueuedOperation* QueuedOp = CreateOp(State, Data, Callback);			
			static if(Controller == AsyncFileHandler.IOCP) {																
				OVERLAPPED* lpOverlap = CreateOverlap(cast(void*)QueuedOp, _Handle, &InitialWriteCallback);				
				lpOverlap.Offset = 0xFFFFFFFF;
				lpOverlap.OffsetHigh = 0xFFFFFFFF;
				WriteFile(cast(HANDLE)this._Handle, Data.ptr, Data.length, null, lpOverlap);
			} else static if(Controller == AsyncFileHandler.Basic) {				
				// Fall back to synchronous IO in a new thread.
				taskPool.put(task(&PerformWriteSync, cast(void*)QueuedOp));
			} else // TODO: AIO and KQueue
				static assert(0, "Unknown controller " ~ to!string(Controller) ~ ".");
		}
	} 

	/// Reads the given number of bytes from the file at the given offset using asynchronous file IO.
	/// Params:
	///		Buffer = A buffer to read in to. The size of the buffer is the number of bytes attempted to be read.
	/// 	Offset = The offset within the file to read from.
	/// 	State = A user-defined object to pass into callback. Can be null.
	/// 	Callback = A callback to invoke upon completion. For best performance, this callback should be light-weight and not queue more data itself. It must be thread-safe. This is invoked with State and the same instance of Buffer, but sliced to the actual number of bytes read.
	void Read(ubyte[] Buffer, size_t Offset, void* State, ReadCallbackDelegate Callback) {
		synchronized(this) {
			enforce(IsOpen && !WaitingToClose, "Unable to read from a closed file.");
			QueuedOperation* Op = CreateOp(State, Buffer, Callback);
			static if(Controller == AsyncFileHandler.IOCP) {
				OVERLAPPED* lpOverlap = CreateOverlap(Op, _Handle, &InitialReadCallback);
				lpOverlap.Offset = Offset;
				static if(size_t.sizeof == 4)
					lpOverlap.OffsetHigh = 0;
				else
					lpOverlap.OffsetHigh = Offset >>> 32;
				ReadFile(cast(HANDLE)this._Handle, Buffer.ptr, Buffer.length, null, lpOverlap);
			}
		}
	}

	// TODO: Consider implementing below.
	/+ /// Closes this file, preventing any further writes and releasing the memory associated with it.	
	/// The actual close will not take effect until all queued writes are complete.
	/// Params:
	/// 	State = A user-defined object to pass into callback. IMPORTANT: This object MUST maintain a reference by the caller somewhere. Can be null.
	/// 	Callback = A callback to invoke upon completion of the close. Can be null.
	void Close(Object State, void delegate(Object) Callback) {
		// Occurs in destructor, so try to avoid allocations.
		if(!IsOpen || WaitingToClose)
			throw new FileException("Unable to close an already closed file.");
		PerformClose();
	}+/

	/// Closes this file, preventing any further writes and releasing the file handle.
	/// The caller must take care to make sure all pending writes are completed.
	/// If there are writes pending, the result is undefined.
	void Close() {
		synchronized(this) {
			if(!IsOpen) {
				debug writeln("Attempting to close a file failed; it was already closed.");
				throw new FileException("Unable to close an already closed file.");
			}
			PerformClose();
			IsOpen = false;
		}
	}

	~this() {
		if(IsOpen)
			Close();
	}
	
private:	
	struct QueuedOperation {
		void* State;
		ubyte[] Data;
		union {
			ReadCallbackDelegate ReadCallback;
			WriteCallbackDelegate WriteCallback;
		}
	}

	AsyncFileHandle _Handle;
	bool IsOpen;
	bool WaitingToClose;

	void InitialReadCallback(void* State, size_t BytesRead) {
		QueuedOperation* Op = cast(QueuedOperation*)State;
		scope(exit)
			NativeReference.RemoveReference(cast(void*)Op);		
		ubyte[] Data = Op.Data[0 .. BytesRead];
		if(Op.ReadCallback)
			Op.ReadCallback(Op.State, Data);
	}
	
	void InitialWriteCallback(void* State, size_t BytesRead) {
		QueuedOperation* Op = cast(QueuedOperation*)State;
		scope(exit)
			NativeReference.RemoveReference(cast(void*)Op);		
		if(Op.WriteCallback)
			Op.WriteCallback(Op.State);
	}	
	
	void PerformWriteSync(void* State) {			
		QueuedOperation* Op = cast(QueuedOperation*)State;
		scope(exit)
			NativeReference.RemoveReference(Op);
		FILE* File = cast(FILE*)_Handle;
		size_t Result = fwrite(Op.Data.ptr, 1, Op.Data.length, File);							
		if(Result != Op.Data.length) {			
			string msg = "Writing to the file failed. Returned " ~ to!string(Result) ~ " when " ~ to!string(Op.Data.length) ~ " bytes were requested. Error: " ~ to!string(errno) ~ ".";
			perror(null);
			debug writeln(msg);
			throw new FileException(msg);
		}
		fflush(File);		
		if(Op.WriteCallback)
			Op.WriteCallback(State);
	}

	void PerformClose() {		
		static if(Controller == AsyncFileHandler.IOCP) {
			int Result = CloseHandle(cast(HANDLE)_Handle);
			if(Result == 0) {
				string msg = "Unable to close a file. Returned error code " ~ to!string(GetLastError()) ~ ".";
				debug writeln(msg);
				throw new FileException(msg);
			}
		} else static if(Controller == AsyncFileHandler.Basic) {
			int Result = fclose(cast(FILE*)_Handle);			
			//perror(null);
			//enforce(Result == 0, "Attempting to close the file returned error code " ~ to!string(Result) ~ ".");			
		} else
			static assert(0, "Unknown controller.");
	}

	static if(Controller == AsyncFileHandler.IOCP) {
		AsyncFileHandle CreateHandle(string FilePath, FileAccessMode Access, FileOpenMode OpenMode, FileOperationsHint Hint) {
			const char* FilePathPtr = toStringz(FilePath);
			size_t AccessFlags = Access == FileAccessMode.Read ? GENERIC_READ : (Access == FileAccessMode.Write ? GENERIC_WRITE : GENERIC_READ | GENERIC_WRITE);
			size_t ShareMode = 0;
			if(AccessFlags == GENERIC_READ)
				ShareMode = FILE_SHARE_READ;
			size_t CreateDisp;
			final switch(OpenMode) {
				case FileOpenMode.CreateNew:
					CreateDisp = CREATE_NEW;
					break;
				case FileOpenMode.CreateOrReplace:
					CreateDisp = CREATE_ALWAYS;
					break;
				case FileOpenMode.Open:
					CreateDisp = OPEN_EXISTING;
					break;
				case FileOpenMode.OpenOrCreate:
					CreateDisp = OPEN_ALWAYS;
					break;
			}
			// TODO: Enable NoBuffering support. Requires annoying things to do so, and need to look more into where it's actually a benefit.
			size_t Flags = FILE_FLAG_OVERLAPPED;
			if(Hint == FileOperationsHint.RandomAccess)
				Flags |= FILE_FLAG_RANDOM_ACCESS;
			else if(Hint == FileOperationsHint.Sequential && Access == FileAccessMode.Read)
				Flags |= FILE_FLAG_SEQUENTIAL_SCAN;

			HANDLE Handle = CreateFileA(FilePathPtr, AccessFlags, ShareMode, null, CreateDisp, Flags, null);
			if(Handle == INVALID_HANDLE_VALUE) {
				size_t LastErr = GetLastError();
				switch(LastErr) {
					case ERROR_FILE_NOT_FOUND:
						ThrowNotFound(FilePath);
						break;
					case ERROR_ACCESS_DENIED:
						throw new AccessDeniedException("Unable to open the file at " ~ FilePath ~ " -- access was denied.");
					case ERROR_ALREADY_EXISTS:
						ThrowAlreadyExists(FilePath);
						break;
					case ERROR_FILE_EXISTS:
						ThrowAlreadyExists(FilePath);
						break;
					case ERROR_SUCCESS:
						throw new FileException("An unknown error occurred when opening a file. Error code was ERROR_SUCCESS."); // .. what?
					default:
						throw new FileException("Unable to access file at " ~ FilePath ~ ". Error code was " ~ to!string(LastErr) ~ ".");
				}
			}
			IOCP.RegisterHandle(Handle);
			return cast(AsyncFileHandle)Handle;
		}
	} else {
		AsyncFileHandle CreateHandle(string FilePath, FileAccessMode Access, FileOpenMode OpenMode, FileOperationsHint Hint) {			
			string Flags = "";
			final switch(Access) {
				case FileAccessMode.Read:
					if(OpenMode == FileOpenMode.OpenOrCreate && !exists(FilePath))
						std.file.write(FilePath, null);
					if(OpenMode != FileOpenMode.Open && OpenMode != FileOpenMode.OpenOrCreate)
						throw new FileException("Opening a file must be done with OpenOrCreate or Open file modes only.");
					Flags ~= "r";
					break;
				case FileAccessMode.Write:
					if(OpenMode == FileOpenMode.CreateNew && exists(FilePath))
						ThrowAlreadyExists(FilePath);
					if(OpenMode != FileOpenMode.CreateOrReplace && OpenMode != FileOpenMode.CreateNew && OpenMode != FileOpenMode.OpenOrCreate)
						throw new FileException("Writing to a file is only allowed with the modes CreateOrReplace, OpenOrCreate, or CreateNew.");					
					Flags ~= "a";
					break;
				case FileAccessMode.Both:
					if(OpenMode == FileOpenMode.CreateNew && exists(FilePath))
						ThrowAlreadyExists(FilePath);
					if(OpenMode != FileOpenMode.CreateNew && OpenMode != FileOpenMode.CreateOrReplace && OpenMode != FileOpenMode.OpenOrCreate)
						throw new FileException("Writing to a file, even with Read set as well, is only allowed with the mdoes CreateOrReplace, CreateNew, or OpenOrCreate.");
					Flags ~= "a+";					
			}		
			Flags ~= "b";
			FILE* Handle = fopen(toStringz(FilePath), toStringz(Flags));
			if(Handle is null) {
				string msg = "Opening the file at " ~ FilePath ~ " failed. No additional info is available.";
				debug writeln(msg);
				perror(null);
				throw new FileException(msg);
			}
			return cast(AsyncFileHandle)Handle;
		}
	}

	private void ThrowNotFound(string FilePath) {
		throw new FileNotFoundException("The file at " ~ FilePath ~ " was not found.");
	}

	private void ThrowAlreadyExists(string FilePath) {
		throw new FileAlreadyExistsException("Unable to create a file at " ~ FilePath ~ " because a file already exists there.");
	}
}