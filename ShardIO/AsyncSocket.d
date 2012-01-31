module ShardIO.AsyncSocket;
private import std.stdio;
private import std.parallelism;
private import ShardTools.NativeReference;
private import ShardIO.AsyncFile;
private import ShardIO.SocketPool;
private import std.exception;
public import std.socket;
import std.c.stdlib;


version(Windows) {	
	import ShardIO.IOCP;
	import std.c.windows.winsock;
	import std.c.windows.windows;	

	enum : int {
		WSAENETDOWN = 10050,
		WSAEADDRINUSE = 10048,
		WSAEADDRNOTAVAIL = 10049,
	}

	enum int ERROR_IO_PENDING = 997;

	extern(Windows) {		
		struct WSABUF {
			size_t len;
			char* buf;
		}		
		alias WSABUF* LPWSABUF;
		BOOL AcceptEx(SOCKET, SOCKET, PVOID, DWORD, DWORD, DWORD, DWORD*, LPOVERLAPPED);
		int WSASend(SOCKET, LPWSABUF, DWORD, DWORD*, DWORD, OVERLAPPED*, LPWSAOVERLAPPED_COMPLETION_ROUTINE);
	}
}

/// Determines the state of a socket.
enum SocketState {
	Disconnected = 0,
	Bound = 1,
	Listening = 2,
	Connected = 4
}

/// Indicates what the controller is for asynchronous socket operations.
enum AsyncSocketHandler {
	/// Uses basic socket operations such as send and recv, with select in a different thread to notify when ready.
	Select =  0,
	/// Uses IO Completion Ports on Windows for managing socket operations with WSA functions such as WSASend and WSARecv, and AcceptEx / ConnectEx for listening / connecting.
	IOCP = 1,
	/// Uses Linux's epoll API in a different thread for notifying when ready.
	EPoll = 2,
	/// Uses OSX's kqueue API in a different thread for notifying when ready.
	KQueue = 4
}

alias socket_t AsyncSocketHandle;

/// Represents an asynchronous socket capable of accepting connections or connectin to a remote endpoint, and sending or receiving data.
/// This socket does not perform any internal buffering of packets too large to be sent without being split.
/// Some operations may not be asynchronous, and will be clearly marked as blocking in the documentation.
class AsyncSocket {

public:

	alias void delegate(void* State, AsyncSocket NewSocket) AcceptCallbackDelegate;	
	alias void delegate(void* State, size_t BytesSent) SocketWriteCallbackDelegate;
	alias void delegate(void* State, size_t BytesRead) SocketReadCallbackDelegate;

	/// Indicates the controller being used for handling files.
	version(Windows) {
		enum AsyncSocketHandler Controller = AsyncSocketHandler.IOCP;
	} else {
		enum AsyncSocketHandler Controller = AsyncSocketHandler.Select;
	}
	
	/// Creates a new AsyncSocket capable of connecting to a remote endpoint or receiving an arbitrary number of connections.
	/// Params:
	/// 	Family = The address family; usually either INET (IPv4) or INET6 (IPv6).
	/// 	Type = The type of the socket. For TCP, this is Stream.
	/// 	Protocol = The protocol the socket uses; this is usually TCP or UDP.
	this(AddressFamily Family, SocketType Type, ProtocolType Protocol) {
		this._Family = Family;
		this._Type = Type;
		this._Protocol = Protocol;
		_State = SocketState.Disconnected;
		socket_t sock;
		version(Windows) {
			sock = cast(socket_t)WSASocketA(cast(int)_Family, cast(int)_Type, cast(int)_Protocol, null, 0, WSA_FLAG_OVERLAPPED);
		} else {
			sock = cast(socket_t)socket(Family, Type, Protocol);
		}
		SetHandle(sock);
		IOCP.RegisterHandle(cast(HANDLE)_Handle);
	}

	private this(AsyncSocket Parent, socket_t Handle) {
		this._Family = Parent._Family;
		this._Type = Parent._Type;
		this._Protocol = Parent._Protocol;
		_State = SocketState.Connected;
		SetHandle(Handle);
		IOCP.RegisterHandle(cast(HANDLE)_Handle);
	}

	/// Sends the given data asynchronously. It is possible for the data to be split if the send buffer is full, or even for zero bytes to be sent.
	/// This method returns the number of bytes sent; the rest must be handled by the caller.
	/// It is safe to assume that once Callback is invoked, the send buffer is no longer full.
	/// It is the responsibility of the caller to ensure that split messages are delivered in order, as the remote endpoint will get them in the order they are received.
	/// Note that Data is transfered ownership to the socket until Callback is invoked.
	/// Params:
	/// 	Data = The data to send. This data is now taken over by the socket, and the application may not modify nor delete it.
	/// 	State = A user-defined object to pass in to Callback. Can be null.
	/// 	Callback = The callback to invoke with State when the operation is complete. Can be null.
	/// Returns:
	/// 	The actual number of bytes sent.
	size_t Send(ubyte[] Data, void* State, SocketWriteCallbackDelegate Callback) {				
		// TODO: Consider removing synchronization.
		synchronized {
			enforce(this.State == SocketState.Connected, "Unable to send to a not-connected socket.");
			static if(Controller == AsyncSocketHandler.IOCP) {
				// TODO: IMPORTANT: Attempt to detect if sending too large a buffer, and then split it if so. Use SO_MAX_MSG_SIZE.
				WSABUF* buf = cast(WSABUF*)malloc(WSABUF.sizeof);
				buf.buf = cast(char*)Data.ptr;
				buf.len = Data.length;
				SendState* SS = cast(SendState*)malloc(SendState.sizeof);
				SS.Buffer = buf;
				SS.State = State;
				QueuedOperation!SocketWriteCallbackDelegate* Op = CreateOp(cast(void*)SS, Data, Callback);
				OVERLAPPED* lpOverlap = CreateOverlap(cast(void*)Op, cast(HANDLE)_Handle, &OnSend);				
				size_t BytesSent;
				int Result = WSASend(cast(SOCKET)_Handle, buf, 1, &BytesSent, 0, lpOverlap, null);
				if(Result == 0) {
					/* Maybe not!
					// Completed immediately.
					if(BytesSent == Data.length) {
						Callback(State, BytesSent);
						return BytesSent;
					} else if(BytesSent != 0) {
						return Send(Data[BytesSent..$], State, Callback);
					} else
						assert(0, "Expected send to be asynchronous, yet returned zero bytes synchronously.");
					*/
				} else {
					int LastErr = WSAGetLastError();
					if(LastErr != ERROR_IO_PENDING)
						throw new SocketOSException("Failed to send data over socket", LastErr);
				}
				return Data.length;
			} else static assert(0);
		}		
	}

	/// Gets the current state of the socket.
	/// This is zero, one, or more of the bits in the SocketState enum.
	/// This is accurate as of the last operation explicitly invoked that changes state.
	@property SocketState State() const {
		return _State;
	}

	/// Begins listening for connections to this socket, invoking Callback upon receiving one.
	/// This operation is not asynchronous, and instead blocks.
	void Listen(int Backlog = 128) {		
		synchronized {			
			if(listen(cast(SOCKET)_Handle, Backlog) == SOCKET_ERROR)
				HandleSocketException();			
			_State = SocketState.Listening;
		}
	}

	/// Binds this socket to the given address.
	/// This operation is not asynchronous, and instead blocks.
	/// Params:
	/// 	Addr = The address to bind to.
	void Bind(Address Addr) {
		synchronized {			
			_State = SocketState.Bound;
			if(bind(cast(SOCKET)_Handle, Addr.name(), Addr.nameLen()) == SOCKET_ERROR)			
				HandleSocketException();
		}
	}

	/// Gets the handle of the socket being used.
	@property AsyncSocketHandle Handle() const {
		return _Handle;
	}

	/// Sets the given socket option to the given value.
	/// Params:
	/// 	Option = The option to set.
	/// 	Value = The value to set the option to.
	/// 	Level = The level to set the option at.
	void SetSocketOption(SocketOptionLevel Level, SocketOption Option, void[] Value) {
		if(setsockopt(_Handle, cast(int)Level, cast(int)Option, Value.ptr, cast(uint)Value.length) == SOCKET_ERROR)
			HandleSocketException();
	}

	/// Ditto
	void SetSocketOption(SocketOptionLevel Level, SocketOption Option, int Value) {
		SetSocketOption(Level, Option, (&Value)[0..1]);
	}

	/// Gets the value of the given socket option.
	/// Params:
	/// 	Level = The level to get the option at.
	/// 	Option = The option to get the value of.
	/// 	Output = A buffer to write the result to.
	/// Returns:
	///		The number of bytes written to Output.
	int GetSocketOption(SocketOptionLevel Level, SocketOption Option, void[] Output) {
		socklen_t Length = cast(uint)Output.length;
		if(getsockopt(_Handle, cast(int)Level, cast(int)Option, Output.ptr, &Length) == SOCKET_ERROR)
			HandleSocketException();
		return Length;
	}

	/// Ditto
	void GetSocketOption(SocketOptionLevel Level, SocketOption Option, out uint Output) {
		int Result = GetSocketOption(Level, Option, (&Output)[0..1]);
		enforce(Result == 1 || Result == 4, "The returned socket option value was not exactly one integer.");
	}
	
	/// Begins preparing for a connection to be accepted, invoking Callback when one is accepted.	
	/// Params:
	/// 	State = A user-defined object to pass into Callback. Can be null.
	/// 	Callback = The callback to invoke when a connection is accepted. Can be null.
	void StartAccepting(void* State, AcceptCallbackDelegate Callback) {	
		enforce(!IsAccepting, "Already accepting connections.");
		IsAccepting = true;
		static if(Controller == AsyncSocketHandler.IOCP) {			
			Pool = SocketPool.GetPool(_Family, _Type, _Protocol);		
			Accept(State, Callback);	
		} else static assert(0);
	}

protected:
	void SetHandle(AsyncSocketHandle Handle) {
		if(Handle == socket_t.init)
			throw new SocketOSException("Failed to create the socket");
		this._Handle = Handle;
		// TODO: OSX fix from std.socket.
		static if (is(typeof(SO_NOSIGPIPE))) {
            SetSocketOption(SocketOptionLevel.SOCKET, cast(SocketOption)SO_NOSIGPIPE, 1);
        }
	}
	
private:
	AddressFamily _Family;
	ProtocolType _Protocol;
	SocketType _Type;
	AsyncSocketHandle _Handle;	
	SocketState _State;
	SocketPool Pool;
	bool IsAccepting = false;

	void HandleSocketException(int ErrorCode = int.max) {		
		version(Windows) {
			if(ErrorCode == -1)
				ErrorCode = WSAGetLastError();
		}
		if(ErrorCode == int.max)
			throw new SocketOSException("A socket exception has occurred");
		version(Windows) {
			switch(ErrorCode) {
				case WSAENETDOWN:
					throw new SocketOSException("The operation failed because the network device was not responding", ErrorCode);
				case WSAEADDRINUSE:
					throw new SocketOSException("The operation failed because the address was already in use", ErrorCode);
				case WSAEWOULDBLOCK:
					return;				
				case 10022: // WSAINEVAL
					throw new SocketOSException("Attempted to listen or connect without binding the socket", ErrorCode);
				case 10056: // WSAEISCONN
					throw new SocketOSException("The socket was already connected; unable to listen or connect", ErrorCode);
				case 10057: // WSAENOTCONN
					throw new SocketOSException("Attempted to send or receive when the socket was not connected", ErrorCode);
				case 10058: // WSAESHUTDOWN
					throw new SocketOSException("The socket has already been shut down, unable to perform further sends or receives", ErrorCode);
				case 10060: // WSAETIMEOUT
					throw new SocketOSException("A socket operation timed out prior to completion", ErrorCode);
				case 10061: // WSAECONNREFUSED
					throw new SocketOSException("The remote host refused the connection", ErrorCode);									
				default:
					break; // Fall down to throw.
			}
		}
		throw new SocketOSException("A socket exception has occurred", ErrorCode);
	}
	
	struct AcceptState {
		void* State;
		socket_t Socket;
	}

	struct SendState {
		void* State;
		LPWSABUF Buffer;		
	}

	void Accept(void* State, AcceptCallbackDelegate Callback) {		
		socket_t Sock = Pool.Acquire();		
		static if(Controller == AsyncSocketHandler.IOCP) {			
			enum BufferSize = 128;
			ubyte[] InBuffer = cast(ubyte[])(malloc(BufferSize)[0 .. BufferSize]);
			AcceptState* AS = cast(AcceptState*)malloc(AcceptState.sizeof);
			AS.State = State;
			AS.Socket = Sock;
			QueuedOperation!(AcceptCallbackDelegate)* Op = CreateOp(cast(void*)AS, InBuffer, Callback);			
			OVERLAPPED* Overlap = CreateOverlap(Op, cast(HANDLE)_Handle, &OnAccept);			
			if(AcceptEx(cast(SOCKET)_Handle, Sock, InBuffer.ptr, 0, BufferSize / 2, BufferSize / 2, null, Overlap) == 0) {				
				int LastErr = WSAGetLastError();
				if(LastErr != ERROR_IO_PENDING)
					throw new SocketOSException("Unable to start accepting a connection", LastErr);
			}			
		} else static assert(0);
	}		

	private void OnAccept(void* State, size_t ErrorCode, size_t Unused) {		
		QueuedOperation!AcceptCallbackDelegate* Op = cast(QueuedOperation!AcceptCallbackDelegate*)State;
		NativeReference.RemoveReference(Op);
		static if(Controller == AsyncSocketHandler.IOCP) {
			AcceptState* AS = cast(AcceptState*)Op.State;
			void* OrigState = AS.State;
			socket_t Socket = AS.Socket;
			free(AS);
			AsyncSocket NewSock = new AsyncSocket(this, Socket);	
			if(Op.Callback)	
				Op.Callback(State, NewSock);
			// TODO: Check if we need to do this in a task thread.
			// MSDN is not perfectly clear whether doing this in in this callback thread causes problems.
			//taskPool.put(task(&Accept, OrigState, Op.Callback));
			Accept(OrigState, Op.Callback);
		} else static assert(0);		
	}

	private void OnSend(void* State, size_t ErrorCode, size_t BytesSent) {
		QueuedOperation!SocketWriteCallbackDelegate* Op = cast(QueuedOperation!SocketWriteCallbackDelegate*)State;
		NativeReference.RemoveReference(Op);
		version(Windows) {
			SendState* SS = cast(SendState*)Op.State;
			void* UserState = SS.State;
			LPWSABUF Buffer = SS.Buffer;
			ubyte[] OrigData = cast(ubyte[])Buffer.buf[0 .. Buffer.len];
			if(OrigData.length != 0 && BytesSent == 0)
				throw new SocketException("Attempted to send more bytes than possible. This is an internal error as it should have been split automatically.");
			free(SS.Buffer);
			free(SS);
			bool OperationComplete = OrigData.length == BytesSent;
			if(OperationComplete && Op.Callback)
				Op.Callback(UserState, BytesSent);
			else if(!OperationComplete) // We didn't finish; queue the remaining bytes.
				Send(OrigData[BytesSent .. $], State, Op.Callback);
		} else static assert(0);
	}
}