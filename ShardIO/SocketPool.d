module ShardIO.SocketPool;
private import std.parallelism;
private import std.stdio;
private import core.sync.mutex;
private import std.socket;

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

public:
	/// Initializes a new instance of the SocketPool object.	
	this(AddressFamily Family, SocketType Type, ProtocolType Protocol, size_t Increment = 32) {
		this._Family = Family;
		this._Type = Type;
		this._Protocol = Protocol;
		this._Increment = Increment;
		AcquireLock = new Mutex();
		PerformGenerate();
	}	
	
	/// Gets the number of sockets to generate when running low.
	@property size_t Increment() const {
		return _Increment;
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
		synchronized(AcquireLock) {			
			if(Sockets.length == 0 || IsGenerating) {				
				return CreateSocket();
			}
		}
		synchronized(this, AcquireLock) {			
			socket_t Result = Sockets[$-1];
			Sockets = Sockets[0..$-1];					
			if(Sockets.length < Increment / 10)
				PerformGenerate();
			return Result;
		}
	}

	/// Gets or creates a SocketPool that creates sockets with the given parameters.		
	static SocketPool GetPool(AddressFamily Family, SocketType Type, ProtocolType Protocol) {
		synchronized {
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
	socket_t[] Sockets;
	size_t _Increment;
	bool IsGenerating;
	Mutex AcquireLock;
	static StoredPool[] Pools;

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
		synchronized {
			debug writeln("-Queued generating-");
			if(IsGenerating)
				return;
			IsGenerating = true;
			taskPool.put(task(&GenerateSockets));
		}
	}

	void GenerateSockets() {
		debug writeln("---Started Generating---");
		synchronized {			
			reserve(Sockets, Sockets.length + Increment);
			for(size_t i = 0; i < Increment; i++) {
				socket_t sock = CreateSocket();
				Sockets ~= sock;
			}
			IsGenerating = false;
		}
		debug writeln("---Done Generating---");
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