module ShardIO.Protocols.IDistributedConnection;

/// Provides an interface for a connection that connects to one of many servers.
interface IDistributedConnection {
	/// Gets the name of this connection.
	/// As well as being a way to identify the server, this is often used for determining what server to send a request to. 
	/// Having multiple connections sharing the same name is not allowed.
	@property string name();
}