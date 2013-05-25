module ShardIO.AsyncSocket;
private import core.stdc.errno;
private import ShardIO.NetworkNotifier;
private import ShardTools.ConcurrentStack;
private import core.atomic;
private import std.typecons;
private import ShardTools.LinkedList;
private import ShardTools.ArrayOps;
import std.exception;
private import ShardTools.Event;
private import std.stdio;
private import std.parallelism;
private import ShardTools.NativeReference;
private import ShardIO.AsyncFile;
private import ShardIO.SocketPool;
private import std.exception;
import ShardTools.ExceptionTools;
public import std.socket;
import std.c.stdlib;
import std.c.string;
import ShardIO.Internals;


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
version(Posix) {
	import std.c.linux.socket;
	import core.sys.posix.unistd;
	import std.traits;
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

/// Represents an asynchronous socket capable of accepting connections or connecting to a remote endpoint, then sending or receiving data.
/// This socket does not perform any internal buffering of packets too large to be sent without being split.
/// Some operations may not be asynchronous, and will be clearly marked as blocking in the documentation.
/// Note that callbacks are not guaranteed to execute. If an error occurs (such as the connection is closed), the socket will be disconnected instead.
/// In this situation, Disconnected will be called.
/// Note that a bound AsyncSocket is not eligible for garbage collection until it is closed.
class AsyncSocket {
	
	// TODO: Switch to using a SpinLock; generally there should be no lock contention (and if there is, it will be short lived), but parallelism may be important.
	
public:
	
	alias void delegate(void* State, AsyncSocket NewSocket) AcceptCallbackDelegate;
	alias void delegate(void* State, Address RemoteEndPoint) ConnectCallbackDelegate;	
	alias void delegate(void* State, size_t BytesSent) SocketWriteCallbackDelegate;
	alias void delegate(void* State, ubyte[] DataRead) SocketReadCallbackDelegate;	
	alias void delegate(void* State, string Reason, int PlatformCode) SocketCloseNotificationCallback;
	
	/// Indicates the controller being used for handling files.
	version(Windows) {
		enum AsyncSocketHandler Controller = AsyncSocketHandler.IOCP;
		alias SOCKET AsyncSocketHandle;
	} else version(linux) {
		alias NetworkNotifier ControllerNotifier;
		enum AsyncSocketHandler Controller = AsyncSocketHandler.EPoll;
		alias int AsyncSocketHandle;
	} else version(OSX) {
		alias NetworkNotifier ControllerNotifier;
		enum AsyncSocketHandler Controller = AsyncSocketHandler.KQueue;
		alias int AsyncSocketHandle;
	}	
	
	static if(Controller == AsyncSocketHandler.IOCP) {
		private alias WSAGetLastError _lasterr;
		private alias closesocket _close;
	} else {
		private alias errno _lasterr;
		private alias close _close;
		private enum int SOCKET_ERROR = -1;
	}
	
	enum bool UsesNetworkNotifier = (Controller == AsyncSocketHandler.EPoll || Controller == AsyncSocketHandler.KQueue || Controller == AsyncSocketHandler.Select);
	
	/// Creates a new AsyncSocket capable of connecting to a remote endpoint or receiving an arbitrary number of connections.
	/// Params:
	/// 	Family = The address family; usually either INET (IPv4) or INET6 (IPv6).
	/// 	Type = The type of the socket. For TCP, this is Stream.
	/// 	Protocol = The protocol the socket uses; this is usually TCP or UDP.
	this(AddressFamily Family, SocketType Type, ProtocolType Protocol) {		
		AsyncSocketHandle sock = SocketPool.GetPool(Family, Type, Protocol).Acquire();
		this(Family, Type, Protocol, SocketState.Disconnected, sock);				
	}
	
	private this(AsyncSocket Parent, AsyncSocketHandle Handle) {
		this(Parent._Family, Parent._Type, Parent._Protocol, SocketState.Connected, Handle);	
		// If we're being created with a parent socket, this socket is already be open; prevent gc taking it.
		NativeReference.AddReference(cast(void*)this);			
	}
	
	private this(AddressFamily Family, SocketType Type, ProtocolType Protocol, SocketState State, AsyncSocketHandle Handle) {
		this._Family = Family;
		this._Type = Type;
		this._Protocol = Protocol;
		this.Pool = SocketPool.GetPool(Family, Type, Protocol);		
		_State = State;		
		SetHandle(Handle);
		this.DisconnectNotifiers = new typeof(DisconnectNotifiers)();
		version(Windows)
			IOCP.RegisterHandle(cast(HANDLE)_Handle);		
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
	
	/// Gets the handle of the socket being used.
	@property AsyncSocketHandle Handle() {		
		return _Handle;
	}
	
	/// Adds or removes a callback to be invoked upon the first disconnect of this socket.
	/// A socket is disconnected either when Disconnect is called, or when an error occurs.
	/// Because errors leave sockets in an undefined state, it is assumed to be disconnected after all errors.
	/// If the error did not leave it disconnected, it will be automatically disconnected.
	void RegisterNotifyDisconnected(void* State, SocketCloseNotificationCallback Callback) {
		synchronized(this) {
			EnforceDisposed();
			foreach(ref Sub; DisconnectNotifiers)
				if(Sub.Callback == Callback)
					return;
			auto sub = new DisconnectSubscriber();
			sub.Callback = Callback;
			sub.State = State;
			this.DisconnectNotifiers.Add(sub);
		}
	}
	
	/// Ditto
	void RemoveNotifyDisconnected(SocketCloseNotificationCallback Callback) {
		synchronized(this) {
			if(!DisconnectNotifiers)
				return;
			foreach(ref Sub, Node; DisconnectNotifiers) {
				if(Sub.Callback == Callback) {
					DisconnectNotifiers.Remove(Node);
					break;
				}
			}
		}
	}
	
	/// Receives the next data sent by the socket in to the given buffer.
	/// Note that with certain protocols (such as TCP), the data being received may be split. 
	/// As such, the caller will likely want to put in their own message length system to determine when a message is finished.
	/// The messages may also be combined, leading to the same result as above.
	/// Note that Buffer is considered owned by this socket until Callback is invoked, and as such should not be altered nor deleted by the user.
	/// Params:
	/// 	Buffer = A buffer to read the resulting data in to. At most Buffer.length bytes are read, but less may be read.
	/// 	State = A user-defined object to pass in to Callback. Can be null.
	/// 	Callback = The callback to invoke with State and the resulting read data (a slice of Buffer with the length being the number of bytes read). Must not be null. It is not safe to queue many more operations from this callback.
	void Receive(ubyte[] Buffer, void* State, SocketReadCallbackDelegate Callback) {				
		synchronized(this) {
			// TODO: Raise a condition or something instead of throwing.
			EnforceDisposed();
			if(this.State != SocketState.Connected)
				throw new SocketException("Unable to receive data on a socket that is not connected.");			
		}
		enforce(Callback !is null, "Callback must not be null.");
		if(!cas(cast(shared)&ReceivePending, false, true))
			throw new InvalidOperationException("A receive operation was already pending on this socket. This likely indicates a race condition on a Receive call.");
		scope(failure)
			enforce(cas(cast(shared)&ReceivePending, true, false));
		static if(Controller == AsyncSocketHandler.IOCP) {
			WSABUF* Buf = cast(WSABUF*)malloc(WSABUF.sizeof);
			Buf.buf = cast(char*)Buffer.ptr;
			Buf.len = Buffer.length;
			OVERLAPPED* lpOverlap = CreateOverlapOp(_Handle, &OnReceive, Callback, State, Buf);			
			DWORD Flags = 0;			
			if(WSARecv(cast(SOCKET)_Handle, Buf, 1, null, &Flags, lpOverlap, null) != 0) {
				int LastErr = WSAGetLastError();
				if(LastErr != ERROR_IO_PENDING) {
					CancelOverlap(lpOverlap);
					OnSocketError("Unable to prepare to receive data", LastErr, false);
				}
			}
			
		} else static if(UsesNetworkNotifier) {
			auto Op = CreateOperation(Callback, State, Buffer);
			// TODO. This shall be annoying.
		} else static assert(0);
	}
	
	/// Sends the given data asynchronously. It is possible for the data to be split if the send buffer is full, or even for zero bytes to be sent.
	/// This method returns the number of bytes sent; the rest must be handled by the caller.
	/// It is safe to assume that once Callback is invoked, the send buffer is no longer full.
	/// It is the responsibility of the caller to ensure that split messages are delivered in order. The results of concurrent sends with the Ready callback are undefined.
	/// Note that Data is transfered ownership to the socket until Callback is invoked.
	/// Params:
	/// 	Data = The data to send. This data is now taken over by the socket, and the application may not modify nor delete it.
	/// 	State = A user-defined object to pass in to Callback. Can be null.
	/// 	Callback = The callback to invoke with State when the operation is complete. Can be null. It is not safe to queue many more operations from this callback.
	/// Returns:
	/// 	The actual number of bytes sent, or -1 in case of error.
	size_t Send(ubyte[] Data, void* State, SocketWriteCallbackDelegate Callback) {								
		synchronized(this) {
			EnforceDisposed();		
			if(this.State != SocketState.Connected)
				return -1;
			//enforce(this.State == SocketState.Connected, "Unable to send to a not-connected socket.");		
		}
		static if(Controller == AsyncSocketHandler.IOCP) {
			// TODO: IMPORTANT: Attempt to detect if sending too large a buffer, and then split it if so. Use SO_MAX_MSG_SIZE.
			// Not sure if this is neccessary... probably not.
			WSABUF* buf = cast(WSABUF*)malloc(WSABUF.sizeof);
			buf.buf = cast(char*)Data.ptr;
			buf.len = Data.length;
			auto lpOverlap = CreateOverlapOp(_Handle, &OnSend, Callback, buf, State);			
			uint BytesSent;
			int Result = WSASend(cast(SOCKET)_Handle, buf, 1, &BytesSent, 0, lpOverlap, null);
			if(Result != 0) {
				int LastErr = WSAGetLastError();
				if(LastErr != ERROR_IO_PENDING) {
					CancelOverlap(lpOverlap);
					free(buf);					
					OnSocketError("Failed to send data over socket", LastErr, false);
					return -1;
				}
			}
			return Data.length;
		} else static if(UsesNetworkNotifier) {
			throw new NotImplementedError("Send (Select)");
			
		} else 
			static assert(0);		
	}
	
	/// Begins listening for connections to this socket, invoking Callback upon receiving one.
	/// This operation is not asynchronous, and instead blocks.
	void Listen(int Backlog = 128) {				
		EnforceDisposed();
		if(!cas(cast(shared)&_State, cast(shared)SocketState.Bound, cast(shared)SocketState.Listening))
			throw new SocketException("The socket must have Bind called upon it in order to start listening.");
		if(listen(_Handle, Backlog) != 0)
			HandleSocketException();		
	}
	
	/// Binds this socket to the given address.
	/// This operation is not asynchronous, and instead blocks.
	/// Params:
	/// 	Addr = The address to bind to.
	void Bind(Address Addr) {				
		EnforceDisposed();
		if(!cas(cast(shared)&_State, cast(shared)SocketState.Disconnected, cast(shared)SocketState.Bound))
			throw new SocketException("The socket must not have been bound yet in order to call Bind.");
		if(bind(Handle, Addr.name(), Addr.nameLen()) != 0)
			HandleSocketException();
		_LocalAddr = Addr;			
		NativeReference.AddReference(cast(void*)this); // Don't want this garbage collected if bound.		
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
		auto Op = CreateOperation(Callback,  State, Addr);
		static if(Controller == AsyncSocketHandler.IOCP) {
			auto Overlap = WrapOverlap(_Handle, &OnConnect, Op);
			EnsureConnectExPtr();			
			if(ConnectEx(cast(SOCKET)_Handle, Addr.name(), cast(int)Addr.nameLen(), null, 0, null, Overlap) == 0) {
				int LastErr = WSAGetLastError();
				if(LastErr != ERROR_IO_PENDING) {
					CancelOperation(Op);
					OnSocketError("Unable to connect to the server", LastErr, false);					
				}
			}					
		} else static if(UsesNetworkNotifier) {
			throw new NotImplementedError("Connect");
		}
	}	
	
	/// Sets the given socket option to the given value.
	/// Params:
	/// 	Option = The option to set.
	/// 	Value = The value to set the option to.
	/// 	Level = The level to set the option at.
	void SetSocketOption(SocketOptionLevel Level, SocketOption Option, void[] Value) {
		EnforceDisposed();
		if(setsockopt(_Handle, cast(int)Level, cast(int)Option, Value.ptr, cast(uint)Value.length) != 0)
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
		if(getsockopt(_Handle, cast(int)Level, cast(int)Option, Output.ptr, &Length) != 0)
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
		Accept(State, Callback);	
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
		bool Result = !getsockopt(_Handle, SOL_SOCKET, SO_TYPE, cast(char*)&type, &typesize);
		if(!Result)
			_State = SocketState.Disconnected;
		else if(_State == SocketState.Disconnected)
			_State = SocketState.Connected;
		return Result;		
	}
	
	~this() {
		if(_Handle != AsyncSocketHandle.init) {
			shutdown(_Handle, 2);
			_close(Handle);
		}
	}
	
protected:
	void SetHandle(AsyncSocketHandle Handle) {
		EnforceDisposed();
		if(Handle == SOCKET_ERROR) {
			int LastErr = _lasterr();
			throw new SocketOSException("Failed to create the socket", LastErr);
		}
		this._Handle = Handle;
		// TODO: OSX fix from std.socket.
		static if (is(typeof(SO_NOSIGPIPE))) {
			SetSocketOption(SocketOptionLevel.SOCKET, cast(SocketOption)SO_NOSIGPIPE, 1);
		}
		static if(UsesNetworkNotifier) {
			Notifier.AddSocket(this);
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
	bool ReceivePending;
	LinkedList!(DisconnectSubscriber*) DisconnectNotifiers;
	package void* InternalState; /// Used by the NetworkNotifier to track this socket.
	static __gshared NetworkNotifier Notifier;
	
	void OnSocketError(string Message, int ErrorCode, bool Throw) {	
		//Disconnect(Message, ErrorCode, null, null, false);
		//debug static __gshared size_t NumErrors = 0;
		//debug writefln("Got socket error number %s, with error code of %s and message of \'%s\'.", atomicOp!("+=", size_t, int)(NumErrors, 1), ErrorCode, Message);
		NotifyDisconnect(Message, ErrorCode);
		if(Throw)
			throw new SocketOSException(Message, ErrorCode);
	}
	
	void HandleSocketException(int ErrorCode = int.max) {		
		if(ErrorCode == -1)
			ErrorCode = _lasterr;
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
			OVERLAPPED* lpOverlap = CreateOverlapOp(_Handle, &OnDisconnect, Callback, State, cast(ubyte[])Message.dup);			
			EnsureDisconnectExPtr();
			if(DisconnectEx(cast(SOCKET)_Handle, lpOverlap, 0, 0) == 0) {
				int Result = WSAGetLastError();
				if(Result != ERROR_IO_PENDING)
					CancelOverlap(lpOverlap);					
				if(Result != ERROR_IO_PENDING && Callback) {					
					if(Callback)
						Callback(State, Message, ErrorCode);
					NotifyDisconnect(Message, ErrorCode);					
					Callback(State, Message, ErrorCode);						
				}
			}					
		} else static if(UsesNetworkNotifier) {
			throw new NotImplementedError("Disconnect");
		}		
	}
	
	void EnforceDisposed() {			
		if(IsDisposed)
			throw new SocketException("Attempted to access a disposed socket.");				
	}
	
	void NotifyDisconnect(string Reason, int Code) {	
		if(!cas(cast(shared)&IsDisposed, cast(shared)false, cast(shared)true))
			return;							
		// TODO: Consider what happens when doing things like a send/receive operation that checks disposed originally, passes, then this occurs.
		_State = SocketState.Disconnected;		
		NativeReference.RemoveReference(cast(void*)this);								
		foreach(sub; DisconnectNotifiers)
			sub.Callback(sub.State, Reason, Code);				
		static if(UsesNetworkNotifier) {
			Notifier.RemoveSocket(this);
		}
		this.DisconnectNotifiers = null;
		shutdown(_Handle, 2);
		Pool.Release(_Handle);			
		_Handle = AsyncSocketHandle.init;					
	}
	
	void OnDisconnect(void* State, int ErrorCode, size_t Unused) {		
		if(IsDisposed)
			return;					
		auto Op = UnwrapOperation!(SocketCloseNotificationCallback, "Callback", void*, "State", ubyte[], "Data")(State);		
		string Reason = cast(string)Op.Data;			
		// It's okay if there's an error.
		if(Op.Callback)
			Op.Callback(State, Reason, ErrorCode);				
		NotifyDisconnect(Reason, ErrorCode);								
	}
	
	void OnConnect(void* State, int ErrorCode, size_t Unused) {		
		_State = SocketState.Connected;						
		auto Op = UnwrapOperation!(ConnectCallbackDelegate, "Callback", void*, "State", Address, "EndPoint")(State);		
		if(ErrorCode != 0) {
			OnSocketError("Unable to connect to remote endpoint", ErrorCode, false);
			return;
		}
		if(Op.Callback)
			Op.Callback(Op.State, Op.EndPoint);		
	}
	
	
	void Accept(void* State, AcceptCallbackDelegate Callback) {		
		AsyncSocketHandle Sock = Pool.Acquire();		
		static if(Controller == AsyncSocketHandler.IOCP) {	
			enum int BufferSize = 128;
			ubyte[] InBuffer = cast(ubyte[])(malloc(BufferSize)[0 .. BufferSize]);
			//auto Overlap = CreateOperation(_Handle, &OnAccept, Callback, State, Sock, InBuffer);
			auto Overlap = CreateOverlapOp(_Handle, &OnAccept, Callback, State, Sock, InBuffer);
			if(AcceptEx(cast(SOCKET)_Handle, Sock, InBuffer.ptr, 0, BufferSize / 2, BufferSize / 2, null, Overlap) == 0) {				
				int LastErr = WSAGetLastError();
				if(LastErr != ERROR_IO_PENDING) {					
					CancelOverlap(Overlap);	
					free(InBuffer.ptr);									
					OnSocketError("Unable to start accepting a connection", LastErr, false);
					return;
				}
			}			
		} else static if(UsesNetworkNotifier) {
			throw new NotImplementedError("Accept");
		}
	}		
	
	private void OnAccept(void* State, int ErrorCode, size_t Unused) {				
		// When using Windows / IOCP, we don't use the standard C socket API.
		// Instead, we use Win32 calls so we can better handle IOCP operations.
		auto Op = UnwrapOperation!(AcceptCallbackDelegate, "Callback", void*, "State", AsyncSocketHandle, "Socket", ubyte[], "InBuffer")(State);
		static if(Controller == AsyncSocketHandler.IOCP) {						
			Address Local =  CreateEmptyAddress(), Remote = CreateEmptyAddress();
			try {								
				int LocalLength, RemoteLength;
				sockaddr* lpLocal = Local.name(), lpRemote = Remote.name();								
				GetAcceptExSockaddrs(Op.InBuffer.ptr, 0, cast(uint)Op.InBuffer.length / 2, cast(uint)Op.InBuffer.length / 2, &lpLocal, &LocalLength, &lpRemote, &RemoteLength);							
				if(LocalLength > Local.nameLen() || RemoteLength > Remote.nameLen())
					throw new SocketException("Unable to get local or remote address; name too long.");								
				memcpy(Local.name(), lpLocal, LocalLength);
				memcpy(Remote.name(), lpRemote, RemoteLength);				
			} finally {
				free(Op.InBuffer.ptr);			
			}						
			if(ErrorCode == 0) {
				AsyncSocket NewSock = new AsyncSocket(this, Op.Socket);				
				NewSock._LocalAddr = Local;
				NewSock._RemoteAddr = Remote;
				if(Op.Callback)	
					Op.Callback(Op.State, NewSock);
			}
			// Not supposed to constantly queue more IOCP operations on the thread that received the event.
			taskPool.put(task(&Accept, Op.State, Op.Callback));			
		} else static if(Controller == AsyncSocketHandler.Select || Controller == AsyncSocketHandler.EPoll || Controller == AsyncSocketHandler.KQueue) {
			Address Remote = CreateEmptyAddress(), Local = CreateEmptyAddress();
			sockaddr* RemoteAddr = Remote.name(), LocalAddr = Local.name();
			socklen_t RemoteLength, LocalLength;
			AsyncSocketHandle SockDesc = accept(_Handle, RemoteAddr, &RemoteLength);
			if(SockDesc != -1) {
				if(RemoteLength > Remote.nameLen())
					throw new SocketException("Remote address name length too long.");
				if(getsockname(SockDesc, LocalAddr, &LocalLength) != 0)
					throw new SocketOSException("Unable to get local address");
				if(LocalLength > Local.nameLen())
					throw new SocketException("Unable to get local address; name too long.");
				memcpy(Local.name(), LocalAddr, LocalLength);
				memcpy(Remote.name(), RemoteAddr, RemoteLength);
				AsyncSocket Sock = new AsyncSocket(this, SockDesc);
				Sock._RemoteAddr = Remote;				
				Sock._LocalAddr = Local;
				if(Op.Callback)
					Op.Callback(Op.State, Sock);
			} else if(errno != EAGAIN) {
				// TODO: Consider EWOULDBLOCK as well. Should be same though. Not defined at the moment; requires research into making sure it's the same everywhere.
				throw new SocketOSException("Unable to accept a new socket");
			}
			Accept(Op.State, Op.Callback);
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
	
	private void OnSend(void* State, int ErrorCode, size_t BytesSent) {				
		static if(Controller == AsyncSocketHandler.IOCP) {			
			auto Op = UnwrapOperation!(SocketWriteCallbackDelegate, "Callback", WSABUF*, "Buffer", void*, "State")(State);
			ubyte[] OrigData = cast(ubyte[])Op.Buffer.buf[0 .. Op.Buffer.len];
			if(OrigData.length != 0 && BytesSent == 0)
				throw new SocketException("Attempted to send more bytes than possible. This is an internal error as it should have been split automatically.");			
			free(Op.Buffer);			
		} else static if(UsesNetworkNotifier) {
			auto Op = UnwrapOperation!(SocketWriteCallbackDelegate, "Callback", ubyte[], "Buffer", void*, "State")(State);			
			ubyte[] OrigData = Op.Buffer;
		} else static assert(0);		
		if(ErrorCode != 0) {
			OnSocketError("Error sending data to endpoint", ErrorCode, false);
			return;
		}
		bool OperationComplete = OrigData.length == BytesSent;
		if(OperationComplete && Op.Callback)
			Op.Callback(Op.State, BytesSent);
		else if(!OperationComplete) { 
			// We didn't finish; queue the remaining bytes, but in a different thread.
			// Note that this doesn't mess up ordering because we're not invoking Callback yet, indicating the buffer isn't ready for another write.
			// Though the caller could ignore that...
			taskPool.put(task(&Send, OrigData[BytesSent .. $], Op.State, Op.Callback));						
		}
	}
	
	private void OnReceive(void* State, int ErrorCode, size_t BytesRead) {				
		if(!cas(cast(shared)&ReceivePending, true, false))
			throw new Error("Expected a receive to be pending on a receive callback.");
		static if(Controller == AsyncSocketHandler.IOCP)
			alias WSABUF* BufferType;
		else
			alias ubyte[] BufferType;
		auto Op = UnwrapOperation!(SocketReadCallbackDelegate, "Callback", void*, "State", BufferType, "Buffer")(State);		
		static if(Controller == AsyncSocketHandler.IOCP) {
			// For IOCP, we need to free the WSABUF* instance.
			scope(exit)
				free(Op.Buffer);
		}
		if(ErrorCode != 0) {				
			OnSocketError("Error receiving data from endpoint", ErrorCode, false);
			return;
		}
		// TODO: Not sure if this should be here.
		if(BytesRead == 0) {				
			OnSocketError("The connection has been closed.", -1, false);
			return;
		}
		static if(Controller == AsyncSocketHandler.IOCP) {			
			ubyte[] ReceivedData = cast(ubyte[])Op.Buffer.buf[0 .. BytesRead];
		} else static if(UsesNetworkNotifier) {
			ptrdiff_t Read = recv(_Handle, Op.Buffer.ptr, Op.Buffer.length, 0);
			if(Read == -1) {
				OnSocketError("Error receiving data from endpoint.", errno, false);
				return;
			}
			BytesRead = Read;
			ubyte[] ReceivedData = Op.Buffer[0 .. BytesRead];
		} else static assert(0);
		assert(Op.Callback);
		Op.Callback(Op.State, ReceivedData);
	}
	
	// IOCP and Windows specific methods.
	version(Windows) {
		// Some functions have to be loaded at runtime for windows sockets or IOCP.
		// We do that here.
		private static void EnsureFunctionLoaded(T)(T* Func, ref ubyte[16] Guid) {
			if(*Func !is null)
				return;
			synchronized(typeid(AsyncSocket)){
				if(*Func !is null)
					return;
				enum int SIO_GET_EXTENSION_FUNCTON_POINTER = -939524090; 
				SOCKET FakeSock = socket(cast(int)AddressFamily.INET, cast(int)SocketType.STREAM, cast(int)ProtocolType.TCP);			
				uint ReturnedSize;
				int Result = WSAIoctl(FakeSock, SIO_GET_EXTENSION_FUNCTON_POINTER, Guid.ptr, Guid.length, Func, Func.sizeof, &ReturnedSize, null, null);
				if(Result != 0)
					throw new SocketOSException("Unable to acquire function pointer for socket operation.");
				if(*Func is null)
					throw new SocketException("Unable to acquire function pointer for socket operation; returned value was null.");
			}
		}
		
		private static void EnsureConnectExPtr() {		
			ubyte[16] GuidBytes = [185, 7, 162, 37, 243, 221, 96, 70, 142, 233, 118, 229, 140, 116, 6, 62];
			EnsureFunctionLoaded(&ConnectEx, GuidBytes);	
		}
		private static void EnsureDisconnectExPtr() {
			ubyte[16] GuidBytes = [17, 46, 218, 127, 48, 134, 111, 67, 160, 49, 245, 54, 166, 238, 193, 87];
			EnsureFunctionLoaded(&DisconnectEx, GuidBytes);
		}				
	}
}