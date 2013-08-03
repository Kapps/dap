module ShardIO.ConnectionPool;
import ShardTools.LinkedList;
import ShardTools.ConcurrentStack;

// TODO: Instead of using PgSqlConnection and the like, it should be PgSqlClient.
// The client actually has a ConnectionPool internally.
// The client is also responsible for doing things like sending commands, parsing Queries, etc.
// Commands should be non-prepared by default, and thus capable of being sent on any connection.
// They should then be able to be made prepared.

/// Provides a pool of connections that can be dynamically resized.
class ConnectionPool(T) {
	this() {
		// Constructor code
	}

	/// Acquires a connection from the pool.
	/// Once the connection is finished with, it should be placed back into the pool using release.
	T acquire() {
		// TODO: Should this return a LocalConnection that uses opDispatch?
		// Would be interesting, but could have issues with commands and the like.
	}

	/// Releases the given connection, allowing another client to use it.
	void release(T connection) {

	}

private:
	ConcurrentStack!(T) _availableConnections;
}

