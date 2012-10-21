module dap.AssetContainer;
public import dap.Asset;
public import dap.HierarchyNode;
import std.range;

/// Represents a container that can hold asset data.
/// The most common implementation is simply a file-system folder.
abstract class AssetContainer : HierarchyNode {

	this(string name, AssetContainer parent) {	
		super(name, parent);
	}
	
	/// Returns any assets that this container stores.
	@property Asset[] assets() {
		mixin(getFilteredChildrenMixin("Asset"));
	}
	
	/// Returns all child containers contained by this container.
	@property AssetContainer containers() {
		mixin(getFilteredChildrenMixin("AssetContainer"));
	}
	
	private static string getFilteredChildrenMixin(string type) {
		return "HierarchyNode[] children = this.children;
		" ~ type ~ "[] result = new " ~ type ~ "[children.length];
		size_t index = 0;
		foreach(HierarchyNode node; children) {
			auto casted = cast(" ~ type ~ ")node;
			if(casted !is null) {
				result[index++] = casted;
			}
		}
		return result[0..index];";
	}
	
	private string _name;
	private AssetContainer _parent;
}