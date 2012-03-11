module ShardIO.AsyncSocket;
private import ShardTools.Event;
private import std.stdio;
private import std.parallelism;
private import ShardTools.NativeReference;
private import ShardIO.AsyncFile;
private import ShardIO.SocketPool;
private import std.exception;
public import std.socket;
import std.c.stdlib;
import std.c.string;


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
		int WSARecv(SOCKET, LPWSABUF, DWORD, DWORD*, DWORD*, OVERLAPPED*, LPWSAOVERLAPPED_COMPLETION_ROUTINE);		
		void GetAcceptExSockaddrs(void*, DWORD, DWORD, DWORD, sockaddr**, int*, sockaddr**, int*);
		__gshared BOOL function(SOCKET, const sockaddr*, int, void*, DWORD, DWORD*, LPOVERLAPPED) ConnectEx;
		__gshared BOOL function(SOCKET, LPOVERLAPPED, DWORD, DWORD) DisconnectEx;
	}		
		
}

/// Determines the state of a socket.
enum SocketState {
	Disconnected = 0,
	Bound = 1,
	Listening = 2,
	Connecting = 4,
	Connected = 8
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
/// Note that callbacks are not guaranteed to execute. If an error occurs (such as the connection is closed), the socket will be disconnected instead.
/// In this situation, Disconnected will be called.
/// Note that an AsyncSocket is not eligible for Garbage Collection until it is closed.
class AsyncSocket {

public:

	alias void delegate(void* State, AsyncSocket NewSocket) AcceptCallbackDelegate;
	alias void delegate(void* State, Address RemoteEndPoint) ConnectCallbackDelegate;	
	alias void delegate(void* State, size_t BytesSent) SocketWriteCallbackDelegate;
	alias void delegate(void* State, ubyte[] DataRead) SocketReadCallbackDelegate;	
	alias void delegate(void* State, string Reason, int PlatformCode) SocketCloseNotificationCallback;
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
		socket_t sock;
		version(Windows) {
			sock = cast(socket_t)WSASocketA(cast(int)Family, cast(int)Type, cast(int)Protocol, null, 0, WSA_FLAG_OVERLAPPED);
		} else {
			sock = cast(socket_t)socket(Family, Type, Protocol);
		}
		this(Family, Type, Protocol, SocketState.Disconnected, sock);				
	}

	private this(AsyncSocket Parent, socket_t Handle) {
		this(Parent._Family, Parent._Type, Parent._Protocol, SocketState.Connected, Handle);				
	}

	private this(AddressFamily Family, SocketType Type, ProtocolType Protocol, SocketState State, socket_t Handle) {
		this._Family = Family;
		this._Type = Type;
		this._Protocol = Protocol;
		_State = State;		
		SetHandle(Handle);
		IOCP.RegisterHandle(cast(HANDLE)_Handle);
		NativeReference.AddReference(cast(void*)this);
	}

	/// Adds a callback to be invoked upon the first disconnect of this socket.
	/// A socket is disconnected either when Disconnect is called, or when an error occurs.
	/// Because errors leave sockets in an undefined state, it is assumed to be disconnected after all errors.
	/// If the error did not leave it disconnected, it will be manually disconnected.
	void RegisterNotifyDisconnected(void* State, SocketCloseNotificationCallback Callback) {
		synchronized(this){
			EnforceDisposed();
			DisconnectSubscriber sub;
			sub.Callback = Callback;
			sub.State = State;
			this.DisconnectNotifiers ~= sub;
		}
	}

	/// Receives the next data sent by the socket in to the given buffer.
	/// Note that with certain protocols (such as TCP), the data being received may be split. 
	/// As such, the caller will likely want to put in their own message length system to determine when a message is finished.
	/// Also, the messages may be combined, leading to the same result as above.
	/// Also note that buffer is considered owned by this socket until Callback is invoked, and as such should not be altered nor deleted by the user.
	/// Params:
	/// 	Buffer = A buffer to read the resulting data in to. At most Buffer.length bytes are read.
	/// 	State = A user-defined object to pass in to Callback. Can be null.
	/// 	Callback = The callback to invoke with State and the resulting read data (a slice of Buffer with the length being the number of bytes read). Must not be null. It is not safe to queue many more operations from this callback.
	void Receive(ubyte[] Buffer, void* State, SocketReadCallbackDelegate Callback) {				
		EnforceDisposed();
		enforce(this.State == SocketState.Connected, "Unable to receive data on a socket that is not connected.");
		enforce(Callback !is null, "Callback must not be null.");
		static if(Controller == AsyncSocketHandler.IOCP) {
			WSABUF* Buf = cast(WSABUF*)malloc(WSABUF.sizeof);
			Buf.buf = cast(char*)Buffer.ptr;
			Buf.len = Buffer.length;
			SendReceiveState* RS = new SendReceiveState();
			RS.State = State;
			RS.Buffer = Buf;
			QueuedOperation!SocketReadCallbackDelegate* Op = CreateOp(cast(void*)RS, Buffer, Callback);
			OVERLAPPED* lpOverlap = CreateOverlap(cast(void*)Op, cast(HANDLE)_Handle, &OnReceive);
			DWORD Flags = 0;
			if(WSARecv(cast(SOCKET)_Handle, Buf, 1, null, &Flags, lpOverlap, null) != 0) {
				int LastErr = WSAGetLastError();
				if(LastErr != ERROR_IO_PENDING)
					OnSocketError("Unable to prepare to receive data", LastErr, false);
			}
					
		} else static assert(0);		
	}

	/// Sends the given data asynchronously. It is possible for the data to be split if the send buffer is full, or even for zero bytes to be sent.
	/// This method returns the number of bytes sent; the rest must be handled by the caller.
	/// It is safe to assume that once Callback is invoked, the send buffer is no longer full.
	/// It is the responsibility of the caller to ensure that split messages are delivered in order, as the remote endpoint will get them in the order they are received.
	/// Note that Data is transfered ownership to the socket until Callback is invoked.
	/// Params:
	/// 	Data = The data to send. This data is now taken over by the socket, and the application may not modify nor delete it.
	/// 	State = A user-defined object to pass in to Callback. Can be null.
	/// 	Callback = The callback to invoke with State when the operation is complete. Can be null. It is not safe to queue many more operations from this callback.
	/// Returns:
	/// 	The actual number of bytes sent, or -1 in case of error.
	size_t Send(ubyte[] Data, void* State, SocketWriteCallbackDelegate Callback) {								
		EnforceDisposed();
		enforce(this.State == SocketState.Connected, "Unable to send to a not-connected socket.");		
		static if(Controller == AsyncSocketHandler.IOCP) {
			// TODO: IMPORTANT: Attempt to detect if sending too large a buffer, and then split it if so. Use SO_MAX_MSG_SIZE.
			WSABUF* buf = cast(WSABUF*)malloc(WSABUF.sizeof);
			buf.buf = cast(char*)Data.ptr;
			buf.len = Data.length;
			SendReceiveState* SS = new SendReceiveState();
			SS.Buffer = buf;
			SS.State = State;
			QueuedOperation!SocketWriteCallbackDelegate* Op = CreateOp(cast(void*)SS, Data, Callback);
			OVERLAPPED* lpOverlap = CreateOverlap(cast(void*)Op, cast(HANDLE)_Handle, &OnSend);				
			size_t BytesSent;
			int Result = WSASend(cast(SOCKET)_Handle, buf, 1, &BytesSent, 0, lpOverlap, null);
			if(Result != 0) {
				int LastErr = WSAGetLastError();
				if(LastErr != ERROR_IO_PENDING) {
					OnSocketError("Failed to send data over socket", LastErr, false);
					return -1;
				}
			}
			return Data.length;
		} else static assert(0);		
	}

	/// Gets the current state of the socket.
	/// This is zero, one, or more of the bits in the SocketState enum.
	/// This is accurate as of the last operation explicitly invoked that changes state.
	@property SocketState State() const {		
		return _State;
	}

	/// Gets the Address of the remote or local endpoint for this socket.
	/// Though this call is synchronous, the provider attempts to cache them from an accept, bind, or connect whenever possible.
	@property Address RemoteAddress() {
		return _RemoteAddr;
	}

	/// Ditto
	@property Address LocalAddress() {
		return _LocalAddr;
	}

	/// Begins listening for connections to this socket, invoking Callback upon receiving one.
	/// This operation is not asynchronous, and instead blocks.
	void Listen(int Backlog = 128) {		
		synchronized(this){			
			EnforceDisposed();
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
		synchronized(this) {			
			EnforceDisposed();					
			if(bind(cast(SOCKET)_Handle, Addr.name(), Addr.nameLen()) == SOCKET_ERROR)			
				HandleSocketException();
			_LocalAddr = Addr;
			_State = SocketState.Bound;		
		}
	}

	/// Connects to the given address, invoking Callback when ready.
	/// If the socket is not currently bound and the AddressFamily is INET or INET6, it is bound to any address.
	/// Otherwise, depending on the controller, the operation may succeed (by binding to any address) or fail with an exception.
	/// Params:
	/// 	Addr = The address to connect to.
	/// 	State = A user-defined object to pass in to Callback when ready. Can be null.
	/// 	Callback = The callback to invoke when the operation is complete. Can be null.
	void Connect(Address Addr, void* State, ConnectCallbackDelegate Callback) {		
		synchronized(this) {
			EnforceDisposed();
			if((_State & SocketState.Bound) == 0) {
				if(_Family == AddressFamily.INET)
					Bind(new InternetAddress(InternetAddress.ADDR_ANY, InternetAddress.PORT_ANY));
				else if(_Family == AddressFamily.INET6)
					Bind(new Internet6Address(Internet6Address.ADDR_ANY, Internet6Address.PORT_ANY));
			}
			_RemoteAddr = Addr;
			_State = SocketState.Connecting;
		}			
		static if(Controller == AsyncSocketHandler.IOCP) {
			EnsureConnectExPtr();
			ConnectState* CS = new ConnectState(); // Has to be GC heap.
			CS.State = State;
			CS.Endpoint = Addr;
			auto Op = CreateOp(cast(void*)CS, null, Callback);
			auto lpOverlap = CreateOverlap(Op, cast(HANDLE)_Handle, &OnConnect);						
			if(ConnectEx(cast(SOCKET)_Handle, Addr.name(), cast(int)Addr.nameLen(), null, 0, null, lpOverlap) == 0) {
				int LastErr = WSAGetLastError();
				if(LastErr != ERROR_IO_PENDING) {
					OnSocketError("Unable to connect to the server", LastErr, false);
					return;
				}
			}					
		}					
	}

	version(Windows) {
		private static void EnsureFunctionLoaded(T)(T* Func, lazy ubyte[] GUID) {
			if(*Func !is null)
				return;
			synchronized(typeid(AsyncSocket)){
				if(*Func !is null)
					return;
				enum int SIO_GET_EXTENSION_FUNCTON_POINTER = -939524090; 
				ubyte[] ID = GUID();
				assert(ID.length == 16);
				SOCKET FakeSock = socket(cast(int)AddressFamily.INET, cast(int)SocketType.STREAM, cast(int)ProtocolType.TCP);			
				size_t ReturnedSize;
				int Result = WSAIoctl(FakeSock, SIO_GET_EXTENSION_FUNCTON_POINTER, ID.ptr, ID.length, Func, Func.sizeof, &ReturnedSize, null, null);
				if(Result != 0)
					throw new SocketOSException("Unable to acquire function pointer for socket operation.");
				if(*Func is null)
					throw new SocketException("Unable to acquire function pointer for socket operation; returned value was null.");
			}
		}

		private static void EnsureConnectExPtr() {		
			EnsureFunctionLoaded(&ConnectEx, cast(ubyte[])[185, 7, 162, 37, 243, 221, 96, 70, 142, 233, 118, 229, 140, 116, 6, 62]);	
		}
		private static void EnsureDisconnectExPtr() {
			EnsureFunctionLoaded(&DisconnectEx, cast(ubyte[])[17, 46, 218, 127, 48, 134, 111, 67, 160, 49, 245, 54, 166, 238, 193, 87]);
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
		EnforceDisposed();
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
		EnforceDisposed();
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
	
	/// Begins preparing for a connection to be accepted, invoking Callback whenever any connections are accepted.	
	/// Params:
	/// 	State = A user-defined object to pass into Callback. Can be null.
	/// 	Callback = The callback to invoke when a connection is accepted. Can be null. It is not safe to queue many more operations from this callback.
	void StartAccepting(void* State, AcceptCallbackDelegate Callback) {	
		EnforceDisposed();
		enforce(!IsAccepting, "Already accepting connections.");
		IsAccepting = true;
		static if(Controller == AsyncSocketHandler.IOCP) {			
			Pool = SocketPool.GetPool(_Family, _Type, _Protocol);		
			Accept(State, Callback);	
		} else static assert(0);
	}

	/// Disconnects this socket.
	/// The socket must be either Connected or Listening in order to be disconnected.
	/// Params:
	///		State = A user-defined object to pass in to Callback. Can be null.
	/// 	Callback = The callback to invoke when the disconnect is complete. Can be null.
	void Disconnect(string Reason, void* State, SocketCloseNotificationCallback Callback) {
		EnforceDisposed();
		Disconnect(Reason, 0, State, Callback, false);
	}

	/// Gets a value indicating whether this socket is currently listening or connected.
	/// This operation blocks, and updates State if need be.
	bool IsAlive() {		
		if(IsDisposed)
			return false;
		int type;
		socklen_t typesize = cast(socklen_t)type.sizeof;
		bool Result = !getsockopt(cast(SOCKET)_Handle, SOL_SOCKET, SO_TYPE, cast(char*)&type, &typesize);
		if(!Result)
			_State = SocketState.Disconnected;
		else if(_State == SocketState.Disconnected)
			_State = SocketState.Connected;
		return Result;		
	}

protected:
	void SetHandle(AsyncSocketHandle Handle) {
		if(Handle == socket_t.init || cast(int)Handle == SOCKET_ERROR) {
			int LastErr = WSAGetLastError();
			throw new SocketOSException("Failed to create the socket", LastErr);
		}
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
	Address _RemoteAddr;
	Address _LocalAddr;
	SocketState _State;
	SocketPool Pool;
	bool IsAccepting = false;
	bool IsDisposed;
	DisconnectSubscriber[] DisconnectNotifiers;

	void OnSocketError(string Message, int ErrorCode, bool Throw) {	
		//Disconnect(Message, ErrorCode, null, null, false);
		NotifyDisconnect(Message, ErrorCode);
		if(Throw)
			throw new SocketOSException(Message, ErrorCode);
	}

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
		ubyte[] InBuffer;
	}

	struct SendReceiveState {
		void* State;
		LPWSABUF Buffer;		
	}

	struct ConnectState {
		void* State;
		Address Endpoint;
	}
	
	struct DisconnectSubscriber {
		void* State;
		SocketCloseNotificationCallback Callback;
	}

	void Disconnect(string Message, int ErrorCode, void* State, SocketCloseNotificationCallback Callback, bool ThrowIfDisconnected) {		
		if(!IsAlive()) {
			if(ThrowIfDisconnected)
				throw new SocketException("Unable to disconnect an already-disconnected socket.");
			else {
				assert(Callback is null);
				return;
			}
		}		
		static if(Controller == AsyncSocketHandler.IOCP) {
			QueuedOperation!SocketCloseNotificationCallback* Op = CreateOp(State, cast(ubyte[])Message.dup, Callback);				
			OVERLAPPED* lpOverlap = CreateOverlap(cast(void*)Op, cast(HANDLE)_Handle, &OnDisconnect);
			EnsureDisconnectExPtr();
			if(DisconnectEx(cast(SOCKET)_Handle, lpOverlap, 0, 0) == 0) {
				int Result = WSAGetLastError();
				if(Result != ERROR_IO_PENDING && Callback) {
					if(Callback)
						Callback(State, Message, ErrorCode);
					NotifyDisconnect(Message, ErrorCode);					
					Callback(State, Message, ErrorCode);						
				}
			}					
		}
	}

	void EnforceDisposed() {			
		if(IsDisposed)
			throw new SocketException("Attempted to access a disposed socket.");				
	}

	void NotifyDisconnect(string Reason, int Code) {
		synchronized(this){
			if(IsDisposed)
				return;			
			IsDisposed = true;
			//_RemoteAddr = null;
			//_LocalAddr = null;
			_State = SocketState.Disconnected;		
			NativeReference.RemoveReference(cast(void*)this);						
			foreach(DisconnectSubscriber sub; DisconnectNotifiers)
				sub.Callback(sub.State, Reason, Code);			
			DisconnectNotifiers = null;
		}
	}

	void OnDisconnect(void* State, size_t ErrorCode, size_t Unused) {		
		if(IsDisposed)
			return;			
		QueuedOperation!SocketCloseNotificationCallback* Op = cast(QueuedOperation!SocketCloseNotificationCallback*)State;
		scope(exit)
			NativeReference.RemoveReference(Op);
		string Reason = cast(string)Op.Data;			
		// It's okay if there's an error.
		if(Op.Callback)
			Op.Callback(State, Reason, ErrorCode);				
		NotifyDisconnect(Reason, ErrorCode);								
	}

	void OnConnect(void* State, size_t ErrorCode, size_t Unused) {		
		_State = SocketState.Connected;		
		QueuedOperation!ConnectCallbackDelegate* Op = cast(QueuedOperation!ConnectCallbackDelegate*)State;
		scope(exit)
			NativeReference.RemoveReference(Op);
		ConnectState* CS = cast(ConnectState*)Op.State;
		void* UserState = CS.State;
		Address EndPoint = CS.Endpoint;			
		if(ErrorCode != 0) {
			OnSocketError("Unable to connect to remote endpoint", ErrorCode, false);
			return;
		}
		if(Op.Callback)
			Op.Callback(UserState, EndPoint);		
	}
	

	void Accept(void* State, AcceptCallbackDelegate Callback) {		
		socket_t Sock = Pool.Acquire();		
		static if(Controller == AsyncSocketHandler.IOCP) {	
			enum int BufferSize = 128;
			ubyte[] InBuffer = cast(ubyte[])(malloc(BufferSize)[0 .. BufferSize]);
			AcceptState* AS = new AcceptState(); // Requires GC Memory?
			AS.State = State;
			AS.Socket = Sock;
			AS.InBuffer = InBuffer;
			QueuedOperation!(AcceptCallbackDelegate)* Op = CreateOp(cast(void*)AS, InBuffer, Callback);			
			OVERLAPPED* Overlap = CreateOverlap(Op, cast(HANDLE)_Handle, &OnAccept);			
			if(AcceptEx(cast(SOCKET)_Handle, Sock, InBuffer.ptr, 0, BufferSize / 2, BufferSize / 2, null, Overlap) == 0) {				
				int LastErr = WSAGetLastError();
				if(LastErr != ERROR_IO_PENDING) {
					OnSocketError("Unable to start accepting a connection", LastErr, false);
					return;
				}
			}			
		} else static assert(0);
	}		

	private void OnAccept(void* State, size_t ErrorCode, size_t Unused) {		
		QueuedOperation!AcceptCallbackDelegate* Op = cast(QueuedOperation!AcceptCallbackDelegate*)State;
		scope(exit)
			NativeReference.RemoveReference(Op);		
		static if(Controller == AsyncSocketHandler.IOCP) {
			AcceptState* AS = cast(AcceptState*)Op.State;
			void* OrigState = AS.State;
			socket_t Socket = AS.Socket;
			Address Local =  CreateEmptyAddress(), Remote = CreateEmptyAddress();

			try {								
				int LocalLength, RemoteLength;
				sockaddr* lpLocal = Local.name(), lpRemote = Remote.name();								
				GetAcceptExSockaddrs(AS.InBuffer.ptr, 0, AS.InBuffer.length / 2, AS.InBuffer.length / 2, &lpLocal, &LocalLength, &lpRemote, &RemoteLength);							
				if(LocalLength > Local.nameLen() || RemoteLength > Remote.nameLen())
					throw new SocketException("Unable to get local or remote address; name too long.");								
				memcpy(Local.name(), lpLocal, LocalLength);
				memcpy(Remote.name(), lpRemote, RemoteLength);				
			} finally {
				free(AS.InBuffer.ptr);			
			}						
			if(ErrorCode == 0) {
				AsyncSocket NewSock = new AsyncSocket(this, Socket);	
				NewSock._LocalAddr = Local;
				NewSock._RemoteAddr = Remote;
				if(Op.Callback)	
					Op.Callback(State, NewSock);
			}
			// Bad things will happen if we constantly queue more operations from a completion thread.
			taskPool.put(task(&Accept, OrigState, Op.Callback));			
		} else static assert(0);		
	}

	private Address CreateEmptyAddress() {
		switch(_Family) {
			case AddressFamily.INET:
				return new InternetAddress(0);
			case AddressFamily.INET6:
				return new Internet6Address(0);
			default:
				return new UnknownAddress();
		}	
	}

	private void OnSend(void* State, size_t ErrorCode, size_t BytesSent) {
		QueuedOperation!SocketWriteCallbackDelegate* Op = cast(QueuedOperation!SocketWriteCallbackDelegate*)State;
		scope(exit)
			NativeReference.RemoveReference(Op);
		static if(Controller == AsyncSocketHandler.IOCP) {
			SendReceiveState* SS = cast(SendReceiveState*)Op.State;
			void* UserState = SS.State;
			LPWSABUF Buffer = SS.Buffer;
			ubyte[] OrigData = cast(ubyte[])Buffer.buf[0 .. Buffer.len];
			if(OrigData.length != 0 && BytesSent == 0)
				throw new SocketException("Attempted to send more bytes than possible. This is an internal error as it should have been split automatically.");			
			free(SS.Buffer);			
			if(ErrorCode != 0) {
				OnSocketError("Error sending data to endpoint", ErrorCode, false);
				return;
			}
			bool OperationComplete = OrigData.length == BytesSent;
			if(OperationComplete && Op.Callback)
				Op.Callback(UserState, BytesSent);
			else if(!OperationComplete) // We didn't finish; queue the remaining bytes.
				Send(OrigData[BytesSent .. $], State, Op.Callback);
		} else static assert(0);
	}

	private void OnReceive(void* State, size_t ErrorCode, size_t BytesRead) {
		QueuedOperation!SocketReadCallbackDelegate* Op = cast(QueuedOperation!SocketReadCallbackDelegate*)State;
		scope(exit)
			NativeReference.RemoveReference(Op);
		static if(Controller == AsyncSocketHandler.IOCP) {
			SendReceiveState* SS = cast(SendReceiveState*)Op.State;
			void* UserState = SS.State;
			LPWSABUF Buffer = SS.Buffer;
			ubyte[] ReceivedData = cast(ubyte[])Buffer.buf[0 .. BytesRead];
			free(SS.Buffer);			
			if(ErrorCode != 0) {
				OnSocketError("Error receiving data from endpoint", ErrorCode, false);
				return;
			}
			Op.Callback(UserState, ReceivedData);
		}
	}
}