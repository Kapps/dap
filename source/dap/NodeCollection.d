module dap.NodeCollection;
import dap.HierarchyNode;
import std.string;
import ShardTools.ExceptionTools;

/// Provides a collection of HierarchyNodes. This class is not thread-safe.
class NodeCollection {
	
	/// Creates a new NodeCollection for the given HierarchyNode.
	this(HierarchyNode owner) {
		this._owner = owner;
	}
	
	/// Returns the number of nodes contained in this collection.
	@property public size_t length() const {
		return _nodes.length;
	}
	
	/// Gets the node that owns this collection.
	@property public HierarchyNode owner() {
		return _owner;	
	}
	
	/// Returns all of the nodes contained in this collection.
	@property public HierarchyNode[] allNodes() {
		return _nodes.values;
	}
	
	/// Gets the HierarchyNode with the given name that is contained by this collection.
	public HierarchyNode opIndex(string name) {
		auto identifier = fixedKey(name);
		HierarchyNode* result = name in _nodes;
		if(result)
			return *result;
		return null;
	}
	
	/// Implements the foreach operator on this collection.
	public int opApply(int delegate(HierarchyNode) dg) {
		int curr = 0;
		foreach(key, value; _nodes) {
			curr = dg(value);	
			if(curr != 0)
				break;
		}
		return curr;
	}
	
	/// Adds the specified node to this collection.
	public void add(HierarchyNode node) {
		if(node.parent !is null)
			throw new InvalidOperationException("A node with a parent set may not be added to a new collection.");
		node.parent = this.owner;
		string identifier = fixedKey(node.identifier);
		assert(identifier !in _nodes);
		_nodes[identifier] = node;
	}
	
	/// Removes the specified node from this collection.
	public void remove(HierarchyNode node) {
		if(node.parent !is this)
			throw new InvalidOperationException("Unable to remove a node from this collection when it does not exist.");
		string identifier = fixedKey(node.identifier);
		auto removed = _nodes.remove(identifier);
		if(!removed)
			throw new KeyNotFoundException("This node did not contain the specified child.");
	}
	
	private string fixedKey(string input) pure {
		// Would be nice to prevent allocations every time we need to look up a key...
		return input.toLower().strip();
	}
	
	private HierarchyNode[string] _nodes;
	private HierarchyNode _owner;
}

