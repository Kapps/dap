module dap.Asset;
public import dap.HierarchyNode;

/// Represents a single (unparsed) asset to be built.
class Asset : HierarchyNode {
	this() {
		// Constructor code
	}
	
	/// Creates an InputSource that can be used to read the data of this asset.
	final InputSource getDataSource() {
		
	}
	
	private AssetStore _store;
}

