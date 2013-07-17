module ShardIO.Protocols.DistributedConnectionLocator;
import ShardIO.Protocols.IDistributedConnection;

/// Provides the base class for a client that can connect to one of many servers
/// depending on an application-specific key being passed in.
abstract class DistributedServerClient {

	this() {
		InitializeAll
	}

protected:

private:
	Event!(void, IDistributedConnection) _nodeAdded;
	Event!(void, IDistributedConnection) _nodeRemoved;
}