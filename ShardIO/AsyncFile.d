module ShardIO.AsyncFile;
private import core.stdc.config;
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
import std.c.stdlib : malloc;
import ShardIO.Internals;

version(Windows) {
	private import core.sys.windows.windows;
	private import ShardIO.IOCP;
	
enum : size_t {
		ERROR_ALREADY_EXISTS = 183,
		ERROR_FILE_EXISTS = 80
	}
	
	extern(Windows) {
		HANDLE WriteFile(HANDLE, const void*, size_t, size_t*, OVERLAPPED*);
		BOOL GetFileSizeEx(HANDLE, long*);
	}
}

import ShardTools.ExceptionTools;

mixin(MakeException("FileNotFoundException"));
mixin(MakeException("AccessDeniedException"));
mixin(MakeException("FileAlreadyExistsException"));
mixin(MakeException("FileException"));
mixin(MakeException("FileNotClosedException", "A file had it's destructor called prior to being closed. The file has been closed, but this indicates a bug in the code."));

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

alias void delegate(void* State) FileWriteCallbackDelegate;
alias void delegate(void* State, ubyte[] Data) FileReadCallbackDelegate;

/// Represents a file that uses asynchronous IO for reads and writes.
/// BUGS:
///		At the moment when using the Basic AsyncFileHandler, it is easy to surpass the maximum number of file descriptors (roughly 70).
///		Eventually, this should be fixed, but since basic is a fallback it is not a high priority.
class AsyncFile  {
	
public:	
	
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
	
	static if(Controller == AsyncFileHandler.IOCP) {
		alias HANDLE AsyncFileHandle;
	} else static if(Controller == AsyncFileHandler.Basic) {
		alias FILE* AsyncFileHandle;
	} else static assert("Unknown controller.");
	
	/// Indicates whether true asynchronous IO support is available, as opposed to synchronous operations in a new thread.
	enum bool SupportsTrueAsync = Controller != AsyncFileHandler.Basic;
	
	// TODO: This shall be problematic because you never know the actual offset.
	/+void Write(ulong Offset, ubyte[] Data, void* State, void delegate(void*) Callback) {
	 
	 }+/	
	
	/// Gets the total size, in bytes, of this file. This operation is $(B NOT) asynchronous.
	/// This function only exists because the file handle is platform-specific, and thus can not be used with the std.stdio module.
	/// The result of this function is undefined if there are writes pending.
	@property ulong Size() {
		enforce(IsOpen, "The file must be open to get the size of it.");
		static if(Controller == AsyncFileHandler.IOCP) {
			long SizeResult;			
			int CallResult = GetFileSizeEx(_Handle, &SizeResult);
			if(CallResult == 0)
				throw new FileException("Unable to get the size of the file. Error code was " ~ to!string(GetLastError()) ~ ".");
			return SizeResult;
		} else static if(Controller == AsyncFileHandler.Basic) {
			void ThrowEx() {
				throw new FileException("Unable to determine the size of the file. Error code " ~ to!string(errno) ~ ".");
			}
			long CurrPos = ftell(_Handle);						
			if(CurrPos == -1)
				ThrowEx();
			if(fseek(_Handle, 0, SEEK_END) != 0)
				ThrowEx();			
			long Result = ftell(_Handle);
			if(Result == -1)
				ThrowEx();
			if(fseek(_Handle, CurrPos, SEEK_SET) != 0)
				ThrowEx();
			return Result;
		} else static assert(0);
		
	}
	
	/// Appends the given data to this file using asynchronous file IO.
	/// Params:
	/// 	Data = The data to append to the file. Must not be altered until the completion of this method.
	/// 	State = A user-defined object to pass into callback. Can be null.
	/// 	Callback = A callback to invoke upon completion. For best performance, this callback should be light-weight and not queue more data itself. It must be thread-safe.
	void Append(ubyte[] Data, void* State, FileWriteCallbackDelegate Callback) {		
		synchronized(this) {
			enforce(IsOpen && !WaitingToClose, "Unable to write to a closed file.");
			auto Op = CreateOperation(Callback, State, Data);
			static if(Controller == AsyncFileHandler.IOCP) {		
				OVERLAPPED* Overlap = WrapOverlap(_Handle, &InitialReadCallback, Op);																		
				Overlap.Offset = 0xFFFFFFFF;
				Overlap.OffsetHigh = 0xFFFFFFFF;
				WriteFile(cast(HANDLE)this._Handle, Data.ptr, Data.length, null, Overlap);
			} else static if(Controller == AsyncFileHandler.Basic) {				
				// Fall back to synchronous IO in a new thread.
				taskPool.put(task(&PerformWriteSync, cast(void*)Op));
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
	void Read(ubyte[] Buffer, ulong Offset, void* State, FileReadCallbackDelegate Callback) {
		synchronized(this) {
			enforce(IsOpen && !WaitingToClose, "Unable to read from a closed file.");
			auto Op = CreateOperation(Callback, State, Buffer);			
			static if(Controller == AsyncFileHandler.IOCP) {				
				OVERLAPPED* Overlap = WrapOverlap(_Handle, &InitialReadCallback, Op);
				Overlap.Offset = cast(uint)(Offset >>> 0);
				Overlap.OffsetHigh = cast(uint)(Offset >>> 32);				
				ReadFile(cast(HANDLE)this._Handle, Buffer.ptr, cast(uint)Buffer.length, null, Overlap);
			} else static if(Controller == AsyncFileHandler.Basic) {
				taskPool.put(task(&PerformReadSync, Buffer, Offset, cast(void*)Op));
			} else static assert(0);
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
		if(IsOpen) {
			Close();
			std.stdio.stderr.writeln("A file was not closed prior to being deleted.");
			throw new FileNotClosedException();
		}
	}
	
private:	
	
	AsyncFileHandle _Handle;
	bool IsOpen;
	bool WaitingToClose;
	
	static if(Controller == AsyncFileHandler.IOCP) {
		void InitialReadCallback(void* State, int ErrorCode, size_t BytesRead) {		
			auto Op = UnwrapOperation!(FileReadCallbackDelegate, "Callback", void*, "State", ubyte[], "Data")(State);		
			ubyte[] Data = Op.Data[0 .. BytesRead];
			if(Op.Callback)
				Op.Callback(Op.State, Data);
		}
		
		void InitialWriteCallback(void* State, int ErrorCode, size_t BytesRead) {		
			auto Op = UnwrapOperation!(FileWriteCallbackDelegate, "Callback", void*, "State", ubyte[], "Data")(State);		
			if(Op.Callback)
				Op.Callback(Op.State);
		}	
	}
	
	static if(Controller == AsyncFileHandler.Basic) {
		void PerformWriteSync(void* State) {					
			synchronized(this) {
				auto Op = UnwrapOperation!(FileWriteCallbackDelegate, "Callback", void*, "State", ubyte[], "Data")(State);		
				size_t Result = fwrite(Op.Data.ptr, 1, Op.Data.length, _Handle);
				if(Result != Op.Data.length)
					throw new FileException("Writing to the file failed. Returned " ~ to!string(Result) ~ " when " ~ to!string(Op.Data.length) ~ " bytes were requested. Error: " ~ to!string(errno) ~ ".");		
				fflush(_Handle);
				if(Op.Callback)
					Op.Callback(State);
			}
		}	
		
		void PerformReadSync(ubyte[] Buffer, ulong Offset, void* State) {
			synchronized(this) {
				auto Op = UnwrapOperation!(FileReadCallbackDelegate, "Callback", void*, "State", ubyte[], "Data")(State);
				if(fseek(_Handle, Offset, SEEK_SET) != 0)
					throw new FileException("Unable to seek to perform a read. Error code " ~ to!string(errno) ~ ".");
				size_t BytesRead = fread(Buffer.ptr, 1, Buffer.length, _Handle);
				if(BytesRead != Buffer.length) {
					if(feof(_Handle) == 0) // Not EOF, thus error.
						throw new FileException("Unable to read the requested number of bytes due to an error. Error code " ~ to!string(errno) ~ ".");
				}
				Buffer = Buffer[0 .. BytesRead];
				assert(Op.Callback);
				Op.Callback(Op.State, Buffer);
			}
		}
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
			int Result = fclose(_Handle);			
			if(Result != 0)
				throw new FileException("Unable to close the file. Received error code " ~ to!string(errno) ~ ".");
			//perror(null);
			//enforce(Result == 0, "Attempting to close the file returned error code " ~ to!string(Result) ~ ".");			
		} else
			static assert(0, "Unknown controller.");
	}
	
	static if(Controller == AsyncFileHandler.IOCP) {
		AsyncFileHandle CreateHandle(string FilePath, FileAccessMode Access, FileOpenMode OpenMode, FileOperationsHint Hint) {
			const char* FilePathPtr = toStringz(FilePath);
			DWORD AccessFlags = Access == FileAccessMode.Read ? GENERIC_READ : (Access == FileAccessMode.Write ? GENERIC_WRITE : GENERIC_READ | GENERIC_WRITE);
			DWORD ShareMode = 0;
			if(AccessFlags == GENERIC_READ)
				ShareMode = FILE_SHARE_READ;
			DWORD CreateDisp;
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
			DWORD Flags = FILE_FLAG_OVERLAPPED;
			if(Hint == FileOperationsHint.RandomAccess)
				Flags |= FILE_FLAG_RANDOM_ACCESS;
			else if(Hint == FileOperationsHint.Sequential && Access == FileAccessMode.Read)
				Flags |= FILE_FLAG_SEQUENTIAL_SCAN;
			
			HANDLE Handle = CreateFileA(FilePathPtr, AccessFlags, ShareMode, null, CreateDisp, Flags, null);
			if(Handle == INVALID_HANDLE_VALUE) {
				DWORD LastErr = GetLastError();
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
			return Handle;
		}
	} else static if(Controller == AsyncFileHandler.Basic) {
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
						throw new FileException("Writing to a file, even with Read set as well, is only allowed with the modes CreateOrReplace, CreateNew, or OpenOrCreate.");
					Flags ~= "a+";					
			}		
			Flags ~= "b";
			FILE* Handle = fopen(toStringz(FilePath), toStringz(Flags));
			if(Handle is null) {
				string msg = "Opening the file at " ~ FilePath ~ " failed. Error code " ~ to!string(errno) ~ ".";
				debug writeln(msg);
				perror(null);
				throw new FileException(msg);
			}
			return Handle;
		}
	} else static assert(0);
	
	private void ThrowNotFound(string FilePath) {
		throw new FileNotFoundException("The file at " ~ FilePath ~ " was not found.");
	}
	
	private void ThrowAlreadyExists(string FilePath) {
		throw new FileAlreadyExistsException("Unable to create a file at " ~ FilePath ~ " because a file already exists there.");
	}
}