module ShardIO.SelectNotifier;
private import std.algorithm;
private import ShardIO.Internals;
private import ShardTools.LinkedList;
private import ShardTools.List;
private import ShardTools.ConcurrentStack;
private import core.thread;
private import std.socket;

version(Windows) {
	private import std.c.windows.winsock;
} else version(Posix) {
	private import std.c.linux.socket;
}

struct SelectOperation {	
	socket_t Handle;
	void* State;
	AsyncIOCallback Callback;
}

private enum NotifierOperation {
	Read = 1,
	Write = 2
}

/// Provides notification for when a file descriptor finishes an operation.
class SelectNotifier  {

public:
	/// Initializes a new instance of the SelectNotifier object.
	this(NotifierOperation Operation) {		
		this.Sockets = new typeof(Sockets)();
		this.ToAdd = new typeof(ToAdd)();
		this.Operation = Operation;
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

private:		

	alias SelectOperation SocketWrapper;	

	LinkedList!SocketWrapper Sockets;
	LinkedList!SocketWrapper ToAdd;
		
	NotifierOperation Operation;

	static SelectNotifier ReadNotifier;
	static SelectNotifier WriteNotifier;

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
}