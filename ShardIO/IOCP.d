﻿module ShardIO.IOCP;
private import core.memory;
private import std.conv;
private import std.stdio;
private import core.stdc.stdio;
private import core.thread;
private import std.exception;
import core.stdc.stdlib;
import core.stdc.string;
import std.c.windows.winsock;

version(Windows){		
	extern(Windows) {		
		alias void function(size_t, size_t, OVERLAPPED*) LPOVERLAPPED_COMPLETION_ROUTINE;		
		alias OVERLAPPED WSAOVERLAPPED;
		alias OVERLAPPED* LPOVERLAPPED;				
		HANDLE CreateIoCompletionPort(HANDLE, HANDLE, void*, size_t);
		int BindIoCompletionCallback(HANDLE, LPOVERLAPPED_COMPLETION_ROUTINE, size_t);		
	}	
	extern(C) {	
		HANDLE _get_osfhandle(int);		
	}

	private import core.sys.windows.windows;

	private HANDLE FileToHandle(FILE* File) {	
		HANDLE Result = _get_osfhandle(_fileno(File));
		enforce(Result != INVALID_HANDLE_VALUE);
		return Result;
	}

	alias void delegate(void* UserData, size_t ErrorCode, size_t BytesSent) IOCPCallbackDelegate;

	/// Provides the implementation of OVERLAPPED that should be used for operations used by handles registered with the IOCP class.
	/// This struct should never have instances created manually; instead, use CreateOverlap.
	public struct OVERLAPPEDExtended {
		OVERLAPPED Overlap;	
		void* UserData;
		IOCPCallbackDelegate Callback;
		HANDLE Handle;	
	}	

	/// Creates an instance of OVERLAPPED using OVERLAPPEDExtended with the given data.
	/// The resulting structure is not allowed to be stored for longer than the lifespan of the callback invoked.
	/// Params:
	/// 	UserData = Any user-defined data to store. It is passed into the callback. IMPORTANT: It must have at least one reference until the end of the callback!
	/// 	Handle = The handle for the object the operation is being performed on.
	///		Callback = A callback to invoke upon completion.
	OVERLAPPED* CreateOverlap(void* UserData, HANDLE Handle, IOCPCallbackDelegate Callback) {		
		OVERLAPPEDExtended* Result = cast(OVERLAPPEDExtended*)malloc(OVERLAPPEDExtended.sizeof);	
		memset(&Result.Overlap, 0, OVERLAPPED.sizeof);
		Result.UserData = UserData;
		Result.Handle = Handle;	
		Result.Callback = Callback;		
		return cast(OVERLAPPED*)cast(void*)Result;
	}


	/// Provides a wrapper around Windows' IO Completion Ports.
	/// This class uses the default ThreadPool's IOCP instance, and thus is limited to a single instance.
	static class IOCP  {

	public static:	

		/// Registers a handle to be owned by this completion port, and be notified of completions.
		/// Params;
		/// 	Handle = The handle to register.
		void RegisterHandle(HANDLE Handle) {
			int Result = BindIoCompletionCallback(Handle, &CompletionCallback, 0);
			if(Result == 0) {
				DWORD LastErr = GetLastError();
				throw new Exception("Unable to bind to IO Completion port. Returned result " ~ to!string(Result) ~ " and last error was " ~ to!string(LastErr) ~ ".");			
			}
		}

		/// Unregisters the given handle.
		@disable void RemoveHandle(HANDLE Handle) {
			// TODO? Probably not needed; probably done automatically on close.
		}
	}

	/// A thread-local boolean so that we can initialize each thread exactly once with the runtime.
	private static bool IsRegisteredWithRuntime; // Thread-local
	extern(Windows) private void CompletionCallback(size_t dwError, size_t cbTransfered, OVERLAPPED* lpOverlapped) {		
		if(!IsRegisteredWithRuntime) {
			synchronized {
				if(!IsRegisteredWithRuntime) {
					thread_attachThis();
					IsRegisteredWithRuntime = true;
				}
			}
		}
		OVERLAPPEDExtended* Extended = cast(OVERLAPPEDExtended*)cast(void*)lpOverlapped;		
		void* State = Extended.UserData;		
		Extended.Callback(State, dwError, cbTransfered);
		free(Extended);
	}
}