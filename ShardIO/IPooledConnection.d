module ShardIO.Protocols.IPooledConnection;
import ShardTools.Event;

/// Provides an interface for a connection that connects to one of many servers.
interface IPooledConnection {
	/// Gets the name of this connection.
	/// As well as being a way to identify the server, this is often used for determining what server to send a request to. 
	/// Having multiple connections sharing the same name is not allowed.
	/// This value is often the Address or Uri of the server.
	@property string name();

	void open();

	@property Event!(void) disconnected();
}