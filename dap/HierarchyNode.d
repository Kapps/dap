module dap.HierarchyNode;

/// Provides the base node in the Asset hierarchy.
class HierarchyNode {

	/// Creates a new HierarchyNode with the given identifier and parent.
	this(string identifier, HierarchyNode parent) {
		this._identifier = identifier;
		this._parent = parent;
	}

	/// Gets an identifier used to represent this node.
	/// For example, an asset may return the name of the asset, while an AssetDirectory could return the name of the directory.
	@property final string identifier() const {
		return _identifier;
	}
	
	/// Gets the parent that owns this node.
	@property final HierarchyNode parent() {
		return _parent;
	}
	
	/// Returns all of this node's children.
	@property abstract HierarchyNode[] children();
	
	/// Returns the fully qualified name of this node, with identifiers being separated by a dot.
	final @property string qualifiedName() const pure {
		// TODO: This could be easily optimized if need be. First calculate length, then allocate.
		string result = this.identifier;
		for(HierarchyNode node = this.parent; node !is null; node = node.parent) {
			result = node.identifier ~ '.' ~ result;
		}
		return result;
	}
	
	private string _identifier;
	private HierarchyNode _parent;
}
