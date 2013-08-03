module ShardIO.Protocols.MemcachedClient;
public import ShardIO.Protocols.MemcachedConnection;
import std.variant;
import std.typecons;

/// Represents a callback that can be used to determine what connection to use from a given hash.
alias MemcachedConnection delegate(ulong hash, MemcachedClient client) LocatorAlgorithm;

/// Provides an extremely basic hash algorithm that uses a modulus to determine the hash.
/// The default TypeInfo getHash method is used to get an initial key, then a modulus
/// is performed to distribute the generated hash amongst the servers.
ubyte[] modulusHashAlgorithm(Variant key, MemcachedClient client) {
	throw new NotImplementedError("modulusHashAlgorithm");
}

class MemcachedClient {
	this(LocatorAlgorithm locatorAlgorithm) {
		// Constructor code
	}

	void addConnection(MemcachedConnection connection) {

	}

	void removeConnection(MemcachedConnection connection) {

	}

private:
	private LocatorAlgorithm locatorAlgorithm;
}

