module ShardIO.DistributedServerClient;
public import ShardIO.IDistributedServerNode;
import ShardTools.Initializers;
import ShardTools.LinkedList;
import core.sync.mutex;
public import ShardIO.IDistributedServerSelector;
import std.algorithm;
import ShardTools.Event;

/// Provides the base class for a client that can connect to one of many servers
/// depending on an application-specific key being passed in.
abstract class DistributedServerClient {

public:
	/// Creates a new DistributedServerClient using the KetamaSelector.
	this() {
		constructNew(_nodeAdded, _nodeRemoved, connectionLock);
		//this._serverSelector = new KetamaSelector(this);
	}

	/// Adds or removes a server node from the client.
	void addNode(IDistributedServerNode node) {
		synchronized(connectionLock) {
			_nodes ~= node;
			_nodeAdded.Execute(node);
		}
	}

	/// ditto
	void removeNode(IDistributedServerNode node) {
		synchronized(connectionLock) {
			_nodes = _nodes.remove(_nodes.countUntil(node));
			_nodeRemoved.Execute(node);
		}
	}

protected:
	Mutex connectionLock;

private:
	//IDistributedServerSelector _serverSelector;
	IDistributedServerNode[] _nodes;
	Event!(void, IDistributedServerNode) _nodeAdded;
	Event!(void, IDistributedServerNode) _nodeRemoved;
}