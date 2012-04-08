module ShardIO.SocketPool;
private import std.algorithm;
private import std.datetime;
private import ShardTools.ConcurrentStack;
private import std.parallelism;
private import std.stdio;
private import core.sync.mutex;
private import std.socket;

private alias core.time.Duration Duration;

version(Windows) {
	import std.c.windows.winsock;
	enum size_t WSA_FLAG_OVERLAPPED = 1;
	extern(Windows) {
		SOCKET WSASocketA(int, int, int, void*, size_t, size_t);
	}
}

/// Provides a pool of created sockets of a given AddressFamily, Protocol, and SocketType.
/// There are default singleton instances for the basic types, created on demand.
class SocketPool  {

private enum ExpectedIncrementDuration = dur!"seconds"(30);

public:

	/// Initializes a new instance of the SocketPool object.	
	this(AddressFamily Family, SocketType Type, ProtocolType Protocol, size_t DefaultIncrement = 8) {
		this._Family = Family;
		this._Type = Type;
		this._Protocol = Protocol;
		this._Increment = DefaultIncrement;
		this.Sockets = new typeof(Sockets)();
		this.LastGeneration = Clock.currTime();
		this.DefaultIncrement = DefaultIncrement;
		AcquireLock = new Mutex();
		PerformGenerate();
	}	

	/// Gets the AddressFamily the sockets will be created with.
	@property AddressFamily Family() const {
		return _Family;
	}

	/// Gets the SocketType that the sockets will be created with.
	@property SocketType Type() const {
		return _Type;
	}

	/// Gets the ProtocolType that the sockets will be created with.
	@property ProtocolType Protocol() const {
		return _Protocol;
	}

	/// Acquires an initialized socket from the pool.
	/// If no sockets are available, a new one will be created while more are being generated.
	socket_t Acquire() {		
		//return CreateSocket();
		socket_t sock;
		if(!Sockets.TryPop(sock)) {
			PerformGenerate();
			sock = CreateSocket();
		}
		return sock;
	}

	/// Releases the given socket, freeing resources associated with it.
	/// The socket is expected to have been shut down already, if needed.
	void Release(socket_t sock) {
		version(Windows) {
			closesocket(cast(SOCKET)sock);
		} else {
			closesocket(sock);
		}
	}

	/// Gets or creates a SocketPool that creates sockets with the given parameters.		
	static SocketPool GetPool(AddressFamily Family, SocketType Type, ProtocolType Protocol) {
		synchronized(typeid(SocketPool)) {
			foreach(StoredPool Pool; Pools) {
				if(Pool.Family == Family && Pool.Type == Type && Pool.Protocol == Protocol)
					return Pool.Pool;
			}
			SocketPool Pool = new SocketPool(Family, Type, Protocol);
			StoredPool Stored = new StoredPool();
			Stored.Pool = Pool;
			Stored.Family = Family;
			Stored.Type = Type;
			Stored.Protocol = Protocol;
			Pools ~= Stored;
			return Pool;
		}
	}
	
private:
	ConcurrentStack!socket_t Sockets;
	size_t _Increment;
	bool IsGenerating;
	Mutex AcquireLock;
	SysTime LastGeneration;
	bool FirstGenerate = true;
	size_t DefaultIncrement;

	static __gshared StoredPool[] Pools;	 

	AddressFamily _Family;
	SocketType _Type;
	ProtocolType _Protocol;

	static class StoredPool {
		AddressFamily Family;
		SocketType Type;
		ProtocolType Protocol;
		SocketPool Pool;
	}

	private void PerformGenerate() {
		synchronized(this) {			
			if(IsGenerating)
				return;
			IsGenerating = true;
			taskPool.put(task(&GenerateSockets));
		}
	}

	void GenerateSockets() {					
			static __gshared size_t TotalCreates = 0;
			Duration SinceLast = Clock.currTime() - LastGeneration;
			if(SinceLast > ExpectedIncrementDuration)
				_Increment -= DefaultIncrement;
			else
				_Increment += DefaultIncrement;
			_Increment = max(min(_Increment, 4096), 16);
			TotalCreates += _Increment;
			writefln("Creating %s new sockets. Total is now %s.", _Increment, TotalCreates);
			for(size_t i = 0; i < _Increment; i++) {
				socket_t sock = CreateSocket();
				Sockets.Push(sock);
			}
		synchronized(this) {
			IsGenerating = false;
		}		
	}

	socket_t CreateSocket() {
		socket_t sock;
		version(Windows) {
			sock = cast(socket_t)WSASocketA(cast(int)_Family, cast(int)_Type, cast(int)_Protocol, null, 0, WSA_FLAG_OVERLAPPED);
		} else {
			sock = cast(socket_t)socket(cast(int)_Family, cast(int)_Type, cast(int)_Protocol);
		}
		if(sock == socket_t.init)
			throw new SocketOSException("Unable to create a socket to pool.", sock);
		return sock;
	}
}