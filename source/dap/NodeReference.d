module dap.NodeReference;
public import dap.HierarchyNode;
import std.traits;
import std.conv;

/// Provides a reference to a different hierarchy node, such as an asset or container.
/// References between multiple AssetStores are allowed.
struct NodeReference {

	/// Creates a NodeReference to the specified node.
	this(HierarchyNode node) {
		this(node.qualifiedName);
	}
	
	/// Creates a NodeReference to the node with the specified fully qualified name.
	this(string fullyQualifiedName) {
		assert(fullyQualifiedName);
		this._referenced = fullyQualifiedName;	
	}
	
	/// Gets the qualified name of the node being referenced.
	@property final string referenced() const {
		return _referenced;
	}
	
	/// Resolves the referenced node on the given BuildContext, returning the result.
	/// Returns null if the referenced node was not found.
	HierarchyNode evaluateReference(BuildContext context) {
		string[] split = HierarchyNode.splitQualifiedName(this._referenced);
		if(split.length == 0)
			return null;
		HierarchyNode current = context.getStore(split[0]);
		for(size_t i = 1; i < split.length; i++) {
			string nextKey = split[i];
			current = current.children[nextKey];
			if(current is null)
				return null;
		}
		return current;
	}
	
	string _referenced;
}

