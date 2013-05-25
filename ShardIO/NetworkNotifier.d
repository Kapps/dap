module ShardIO.NetworkNotifier;
private import std.algorithm;
private import ShardIO.Internals;
private import ShardTools.LinkedList;
private import ShardTools.List;
private import ShardTools.ConcurrentStack;
private import core.thread;
private import std.socket;
import ShardIO.AsyncSocket;
import core.sync.mutex;
import core.atomic;
import ShardTools.Untyped;
import core.stdc.stdlib;

version(Windows) {
	private import std.c.windows.winsock;
} else version(Posix) {
	private import core.sys.posix.sys.socket;
}

// NetworkNotifier keeps track of all tracked sockets and whether writes / reads are ready.
// Then something requests to be notified when one of these are ready.
// Since it knows state, it can immediately call when ready.
// Otherwise, when the derived class notifies it's ready it will either update state or invoke the callback (but not both).
// A callback will be invoked if it exists, otherwise the state will be updated signifying that it's ready.

enum SocketStatus : ubyte {
	None = 0,
	ReadReady = 1,
	WriteReady = 2,
	Disconnected = 4
}

alias void delegate(Untyped) NetworkNotificationCallback;

private struct NotificationSubscriber {
	NetworkNotificationCallback Callback;
	Untyped Tag;
}

struct SocketState {
	NotificationSubscriber ReadSubscriber;
	NotificationSubscriber WriteSubscriber;
	NotificationSubscriber DisconnectSubscriber;
	bool SpinLockActive;
	SocketStatus Status;
}

/// Provides the base class for a notification mechanism for sockets, signifying when a state change occurs.
/// This class does not use the garbage collector, but subscribers may.
abstract class NetworkNotifier {
	
	/// Informs the NetworkNotifier that the given socket has been created and should be watched.
	void AddSocket(AsyncSocket Socket) {
		SocketState* State = cast(SocketState*)malloc(SocketState.sizeof);
		Socket.InternalState = State;
	}
	
	/// Informs the NetworkNotifier that the given socket has been destroyed, and should no longer be watched.
	/// This method must be called for any socket that has been added with AddSocket, otherwise memory leaks will occur.
	void RemoveSocket(AsyncSocket Socket) {
		SocketState* State = cast(SocketState*)Socket.InternalState;
		free(State);
	}
	
	/// Indicates whether the NetworkNotifier is currently watching the given socket.
	bool IsSocketAttached(AsyncSocket Socket) {
		return Socket.InternalState !is null;
	}
		
	/// Informs the NetworkNotifier to invoke Callback when Socket has data waiting to be read (or an incoming connection if a listen socket),
	/// has a write ready (or a connection has completed), or has been disconnected, passing in Tag for any state information.
	/// Note that it is possible for Callback to be invoked before this method ends if the requested operation is already ready.
	/// Status must be one of Disconnected, ReadReady, or WriteReady, and may not be a combination of two or more values.
	void NotifyOnReady(AsyncSocket Socket, SocketStatus Operation, NetworkNotificationCallback Callback, Untyped Tag) {
		assert(Operation == SocketStatus.ReadReady || Operation == SocketStatus.WriteReady || Operation == SocketStatus.Disconnected);
		SocketState* State = cast(SocketState*)Socket.InternalState;
		bool InvokeImmediate = false;
		NotificationSubscriber* Subscriber =
				(Operation == SocketStatus.ReadReady) ? &State.ReadSubscriber :
				(Operation == SocketStatus.WriteReady) ? &State.WriteSubscriber :
				(Operation == SocketStatus.Disconnected) ? &State.DisconnectSubscriber :
				null;
		{ // Scope Exit block. nothrow.
			mixin(AcquireLockMixin("State"));
			if((State.Status & Operation) != 0) {
				// We already have a read or write ready, so immediately signal. Leave spinlock first though.
				assert(*Subscriber == NotificationSubscriber.init);
				InvokeImmediate = true;
			} else {
				// Otherwise, no read or write is ready, so set the subscriber.
				NotificationSubscriber sub;
				sub.Callback = Callback;
				sub.Tag = Tag;
				*Subscriber = sub;				
			}
			// And since we've handled the operation, clear the ready flag.
			State.Status &= ~Operation;
		}
		if(InvokeImmediate)
			Callback(Tag);
	}
	
	private static string AcquireLockMixin(string StateName) {
		return r"
			while(!cas(cast(shared)&" ~ StateName ~ ".SpinLockActive, false, true)) { }
			scope(exit)
				" ~ StateName ~ ".SpinLockActive = false;
		";
	}
}
/+
/// Provides a network notifier using the linux epoll system.
class EpollNotifier {

}

/// Provides notification for when a file descriptor finishes an operation through a polling and/or wait mechanism.
/// This is the base class for more complex poll / wait mechanisms, such as select, epoll, or kqueue.
abstract class PollingNotifier  {

	/// Initializes a new instance of the SelectNotifier object.
	this() {		
		this.ToAdd = new typeof(ToAdd)();
		(new Thread(&RunSelectLoop)).start();
	}

	/// Notifies Callback when the given socket has data ready to be received or when the send buffer is no longer full.
	/// NotifyOnRead will notify when listen is called and a connection is pending, data is available, or the connection has been closed/reset/terminated.
	/// NotifyOnWrite will notify when a non-blocking connect has succeeded or when data may be sent to this socket.
	/// While it is valid to have the same socket passed in to both NotifyOnRead and NotifyOnWrite,
	/// the results are undefined when passing it in to the same method twice prior to a notification.
	/// Params:
	/// 	Socket = The socket to wait for a state change on.
	/// 	State = The State to pass in to Callback.
	/// 	Callback = The callback to invoke when ready.
	static void NotifyOnRead(socket_t Socket, void* State, AsyncIOCallback Callback) {
		mixin(NotifiyCommonMixin("ReadNotifier", "NotifierOperation.Read"));			
	}	

	/// Ditto
	static void NotifyOnWrite(socket_t Socket, void* State, AsyncIOCallback Callback) {
		mixin(NotifiyCommonMixin("WriteNotifier", "NotifierOperation.Write"));
	}	

	private static string NotifiyCommonMixin(string Backing, string Operation) {
		return "if(" ~ Backing ~ " is null) {
			synchronized(typeid(typeof(this))) {
				if(" ~ Backing ~ " is null)
					" ~ Backing ~ " = new SelectNotifier(" ~ Operation ~ ");
			}
		}
		SelectOperation Op;
		Op.Handle = Socket;
		Op.State = State;
		Op.Callback = Callback;
		synchronized(" ~ Backing ~ ".ToAdd)
			" ~ Backing ~ ".ToAdd.Add(Op);";
	}
		
protected:
	void RegisterSocket(AsyncSocket Socket) {
		
		
	}

private:		

	ConcurrentStack!(PollingSocket*) ToAdd;

	void RunSelectLoop() {
		while(true) {			
			synchronized(ToAdd)
				foreach(Wrapper; ToAdd)
					Sockets.Add(Wrapper);
			// We want to sleep only if no sockets were selected and returned set.
			bool AnySelected = false;			
			// We only do LoopSize sockets per select (per loop), due to select limitations.
			enum size_t LoopSize = FD_SETSIZE;
			size_t NumLoops = Sockets.Count % LoopSize;
			if(LoopSize * NumLoops != Sockets.Count)
				NumLoops++;						

			// We use a LinkedList, but we need to skip LoopNumber * LoopSize elements. So to do this, we just store the current node and go with that.
			auto CurrentNode = Sockets.Head;
			// Keep a copy for when checking sockets.		
			auto OriginalNode = CurrentNode; 		
			for(size_t LoopNumber = 0; LoopNumber < NumLoops; LoopNumber++) {
				bool IsDone = false;
				int MaxSocketNumber = 0;
				fd_set set;			
				FD_ZERO(&set);		
				for(size_t SocketNumber = 0; SocketNumber < LoopSize; SocketNumber++) {
					socket_t sock = CurrentNode.Value.Handle;
					FD_SET(sock, &set);
					CurrentNode = CurrentNode.Next;
					MaxSocketNumber = max(MaxSocketNumber, cast(int)sock);
					if(CurrentNode is null) {
						IsDone = true;
						break;
					}
				}
				 
				std.c.windows.winsock.timeval t;				
				t.tv_sec = 0;
				t.tv_usec = 0;
				size_t NumSelected;
				if(Operation == NotifierOperation.Read)
					NumSelected = select(MaxSocketNumber + 1, &set, null, null, &t);
				else if(Operation == NotifierOperation.Write)
					NumSelected = select(MaxSocketNumber + 1, null, &set, null, &t);
				else assert(0);
					
				size_t NumOperated = 0;
				if(NumSelected > 0) {
					for(auto Node = OriginalNode; Node !is CurrentNode; Node = Node.Next) {						
						if(FD_ISSET(Node.Value.Handle, &set) != 0) {
							Sockets.Remove(Node);
							Node.Value.Callback(Node.Value.State, 0, 0);
							NumOperated++;
							AnySelected = true;
							if(NumOperated == NumSelected)
								break;
						}					
					}
				}
					
				FD_ZERO(&set);					
			}			
			
			if(!AnySelected)
				Thread.sleep(dur!"msecs"(1));							
		}
	}
}+/