module ShardIO.AsyncFile;
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

	HANDLE WriteFile(HANDLE, const void*, size_t, size_t*, OVERLAPPED*);
}

import ShardTools.ExceptionTools;

mixin(MakeException("FileNotFoundException"));
mixin(MakeException("AccessDeniedException"));
mixin(MakeException("FileAlreadyExistsException"));
mixin(MakeException("FileException"));

enum FileAccessMode {
	Read = 1,
	Write = 2,
	Both = Read | Write;
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

alias void* AsyncFileHandle;

/// Represents a file that uses asynchronous IO for reads and writes.
class AsyncFile  {

public:
	
	/// Creates a new AsyncFile that operates on the file at the given path.
	/// Params:
	/// 	FilePath = The path to the file.
	/// 	Access = The way in which to access the file.
	/// 	OpenMode = Determines how to open the file. Must be valid for the Access type (Open/OpenOrCreate for Read, CreateNew/CreateOrReplace for Write).
	/// 	Hint = An access hint for optimizing IO. Can be set to None for no specific hints.
	this(string FilePath, FileAccessMode Access, FileOpenMode OpenMode, FileOperationsHint Hint = FileOperationsHint.None) {
		FilePath = PathTools.MakeAbsolute(FilePath);
		if(Access == FileAccessMode.Read && (OpenMode != FileOpenMode.Open && OpenMode != FileOpenMode.OpenOrCreate))
			throw new FileException("Reading a file is only allowed with Open or OpenCreate file modes.");
		if(Access == FileAccessMode.Write && (OpenMode != FileOpenMode.CreateNew && OpenMode != FileOpenMode.CreateOrReplace))
			throw new FileException("Writing a file is only allowed with CreateNew or CreateOrReplace file modes.");
		this._Handle = CreateHandle(FilePath, Access, OpenMode, Hint);
	}

	/// Appends the given data to this file using asynchronous file IO.
	/// Params:
	/// 	Data = The data to append to the file. This array does not have a reference stored in memory known by the GC; thus, a reference to it must exist until Callback is called.
	/// 	State = A user-defined object to pass into callback. IMPORTANT: This object MUST maintain a reference by the caller somewhere. Can be null.
	/// 	Callback = A callback to invoke upon completion. For best performance, this callback should be light-weight and not queue more data itself. It should also be thread-safe.
	void Append(ubyte[] Data, Object State, void delegate(Object) Callback) {
		synchronized(this) {
			version(Windows) {
				// TODO: Find out if we can do something like GC.increaseCount here and GC.decreaseCount in callback.
				OVERLAPPED* lpOverlap = CreateOverlap(State, _Handle, Callback);
				WriteFile(cast(HANDLE)this._Handle, Data.ptr, Data.length, null, lpOverlap);
			}/+ else version(Posix) {
				// TODO: aio
			}+/ else {
				// Fall back to synchronous IO in a new thread.
				taskPool.put(task(&PerformWriteSync, Data, State, Callback));
			}	
		}
	}
	
private:
	AsyncFileHandle _Handle;
	void PerformWriteSync(ubyte[] Data, Object State, void delegate(Object) Callback) {
		fwrite(Data.ptr, 1, Data.length, File);
		fflush(File);
		Callback(State);
	}

	version(Windows) {
		AsyncFileHandle CreateHandle(string FilePath, FileAccessMode Access, FileOpenMode OpenMode, FileOperationsHint Hint) {
			const char* FilePathPtr = toStringz(FilePath);
			size_t Access = (Access == FileAccessMode.Read ? GENERIC_READ) : (Access == FileAccessMode.Write ? GENERIC_WRITE : GENERIC_READ | GENERIC_WRITE);
			size_t ShareMode = 0;
			if(Access == GENERIC_READ)
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

			HANDLE Handle = CreateFileA(FilePathPtr, Access, ShareMode, null, CreateDisp, Flags, null);
			if(Handle == INVALID_HANDLE_VALUE) {
				size_t LastErr = GetLastError();
				switch(LastErr) {
					case ERROR_FILE_NOT_FOUND:
						ThrowNotFound(FilePath);
						break;
					case ERROR_ACCESS_DENIED:
						throw new AccessDeniedException("Unable to open the file at " ~ FilePath ~ " -- access was denied.");
					case ERROR_ALREADY_EXISTS:
						break; // That's okay, it's not an error.
					case ERROR_FILE_EXISTS:
						ThrowAlreadyExists(FilePath);
						break;
					case ERROR_SUCCESS:
						break;
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
					else if(OpenMode != FileOpenMode.Open)
						throw new FileException("Opening a file must be done with OpenOrCreate or Open file modes only.");
					Flags ~= "r";
					break;
				case FileAccessMode.Write:
					if(OpenMode == FileOpenMode.CreateNew && exists(FilePath))
						ThrowAlreadyExists(FilePath);
					else if(OpenMode != FileOpenMode.CreateOrReplace)
						throw new FileException("Writing to a file is only allowed with the modes CreateOrReplace and CreateNew.");					
					Flags ~= "a";
					break;
				case FileAccessMode.Both:
					if(OpenMode == FileOpenMode.CreateNew && exists(FilePath))
						ThrowAlreadyExists(FilePath);
					if(OpenMode != FileOpenMode.CreateNew || OpenMode != FileOpenMode.CreateOrReplace)
						throw new FileException("Writing to a file, even with Read set as well, is only allowed wit hthe mdoes CreateOrReplace and CreateNew.");
					Flags ~= "a+";					
			}		
			Flags ~= "b";
			FILE* Handle = fopen(toStringz(FilePath), toStringz(Flags));
			if(HANDLE is null)
				throw new FileException("Opening the file at " ~ FilePath ~ " failed. No additional info is available.");
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