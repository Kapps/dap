module dap.AssetContainer;
public import dap.Asset;
public import dap.HierarchyNode;
import std.range;
import std.algorithm;

/// Represents a container that can hold asset data.
/// The most common implementation is simply a file-system folder.
class AssetContainer : HierarchyNode {

	this(string name) {	
		super(name);
	}
	
	/// Returns any assets that this container stores.
	/// The result is a lazy range that operates on allNodes.
	@property final auto assets() {
		return children.allNodes.map!(c => cast(Asset)c).filter!(c => c !is null);
	}
	
	/// Returns all child containers contained by this container.
	/// The result is a lazy range that operates on allNodes.
	@property final auto containers() {
		return children.allNodes.map!(c => cast(AssetContainer)c).filter!(c => c !is null);
	}
}