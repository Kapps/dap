module dap.Asset;
public import dap.HierarchyNode;
public import dap.AssetContainer;
import ShardTools.ExceptionTools;
import std.range;
import dap.ContentProcessor;
import std.datetime;

import vibe.core.stream;

/// Represents a single (unparsed) asset to be built.
class Asset : HierarchyNode {

	/// Creates a new Asset with the given name, under the given parent.
	/// The processorName is set to the default processor that can handle this file type.
	this(string name, string extension) {
		super(name);
		this._extension = extension;
		if(_extension.length > 0 && _extension[0] == '.')
			_extension = _extension[1..$];
		this.processorName = ContentProcessor.getDefaultProcessorForExtension(extension);
	}
	
	/// Creates an InputSource that can be used to read the data of this asset.
	final InputStream getInputStream() {
		return root.createInputStream(this);
	}
	
	/// Creates an OutputSource that can be used to write the generated data for this asset.
	final OutputStream getOutputStream() {
		return root.createOutputStream(this);
	}

	/// Creates an instance of the ContentProcessor used for building this asset.
	/// All settings for the processor are loaded from this asset's setting store.
	final ContentProcessor createProcessor() {
		return ContentProcessor.create(processorName, this);
	}

	/// Indicates the last time that this asset was built.
	@property final SysTime lastBuild() const {
		return _lastBuild;
	}

	/+/// Marks this asset as dirty, indicating that it should be rebuilt.
	final void markDirty() {

	}+/
	
	/// Gets or sets the name of the ContentProcessor that process this asset.
	/// Once a processor name is set, default values are assigned.
	@property final string processorName() const @safe pure nothrow {
		return _processorName;
	}

	/// ditto
	@property final void processorName(string val) {
		_processorName = val;
		auto processor = createProcessor();
		processor.assignDefaultValues(this);
		processor.saveSettings();
	}

	/// Gets the file extension of the input data for this asset.
	/// This does not include the leading dot.
	@property final string extension() const @safe pure nothrow {
		return _extension;
	}

private:
	string _processorName;
	string _extension;
	SysTime _lastBuild;
}

