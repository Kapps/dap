module ShardIO.IDistributedServerNode;

interface IDistributedServerNode {
	/// Gets the name of this node.
	/// Generally a name is used for determining a hash, and thus a client to use.
	/// As such, different nodes with the same name will be assumed to be the same server.
	/// It is expected that the name of a node will never change once it's constructed.
	@property string name() const;

	/// Gets the weight of this node.
	/// A node with a higher weight is more likely to be selected for requests.
	/// A common default value is 1, but the actual value used will not matter so long as it's positive.
	/// A negative value has undefined results.
	@property float weight() const;
}

