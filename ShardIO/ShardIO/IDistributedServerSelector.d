module ShardIO.IDistributedServerSelector;
import ShardIO.IDistributedServerNode;
import ShardIO.DistributedServerClient;
import ShardTools.LinkedList;
import ShardTools.HashUtils;
// TODO: Make this not need a Server, make it not server based, and make it part of ShardTools ideally.
/+
/// Provides an interface that can be used to select a server from a set of servers given a key.
/// It is generally desired for the same key to map to the same server as consistently as possible.
/// The most basic selector, a ModulusSelector, is the fastest choice available but will not remain consistent if a node is added or removed.
/// A common choice for when nodes will be added or removed is the KemataSelector, which will attempt to stay mostly consistent.
interface IDistributedServerSelector {
	/// Returns an alive node within the client's node list for the given key.
	IDistributedServerNode getNodeForKey(string key);

	/// Gets the client that this selector applies to.
	@property DistributedServerClient client();
}

class ModulusSelector : IDistributedServerSelector {

	this(DistributedServerClient client) {
		this._client = client;
	}

	@property DistributedServerClient client() {
		return _client;
	}

	IDistributedServerNode getNodeForKey(string key) {
		hash_t hash = fnvHash(key);
	}

private:

	IDistributedClient _client;
	ModNode[] nodes;
	int total = 0;

	struct ModNode {
		size_t startIndex;
		IDistributedServerNode node;
	}
}+/