module dap.Asset;
public import dap.HierarchyNode;
public import dap.AssetContainer;
import ShardTools.ExceptionTools;
import std.range;

/// Represents a single (unparsed) asset to be built.
class Asset : HierarchyNode {

	/// Creates a new Asset with the given name, under the given parent.
	this(string name, HierarchyNode parent) {
		super(name, parent);
	}
	
	/// Creates an InputSource that can be used to read the data of this asset.
	final InputSource getInputSource() {
		trace("Generating input source.");
		return root.createInputSource(this);
	}
	
	/// Creates an OutputSource that can be used to write the generated data for this asset.
	final OutputSource getOutputSource() {
		return root.createOutputSource(this);
	}
}

