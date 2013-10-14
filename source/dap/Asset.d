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

	// Importer type should be automatic based off of the processor's input type and extension of the file.
	// It should find a ContentImporter that says it can create import data of that type for that extension.
	/+/// Gets or sets the type of the ContentImporter used for this Asset.
	@property const(ClassInfo) importerType() const @safe pure nothrow{
		return _importerType;
	}

	/// ditto
	@property void importerType(const(ClassInfo) value) @safe pure nothrow {
		_importerType = value;
	}+/
	
	/// Gets or sets the name of the ContentProcessor that process this asset.
	@property string processorName() const @safe pure nothrow {
		return _processorName;
	}

	/// ditto
	@property void processorName(string val) @safe pure nothrow {
		_processorName = val;
	}

	/// Gets the file extension of the input data for this asset.
	@property string extension() const @safe pure nothrow {
		return _extension;
	}

private:
	string _processorName;
	string _extension;
}

