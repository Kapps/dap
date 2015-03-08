module dap.AssetStore;
public import dap.HierarchyNode;
public import dap.Asset;
public import dap.AssetContainer;
public import dap.BuildContext;
public import vibe.core.stream;
import dap.StreamOps;
import std.parallelism;
import msgpack;
import ShardTools.Buffer;
import ShardTools.BufferPool;
import ShardTools.LinkedList;
import ShardTools.StreamReader;
import core.time;
import std.string;
import ShardTools.ExceptionTools;
import std.exception;
import std.conv;
import std.typecons;
import std.algorithm;
import vibe.stream.memory;

// No clue why this is necessary...
// Without it DMD complains "undefined identifier Asset, did you mean class Asset?"
alias Asset = dap.Asset.Asset;

/// Provides the implementation of any storage operations, such as loading data for an asset.
abstract class AssetStore : HierarchyNode {

	// TODO: We'll need to change the default method for serializing and deserializing to not ruin the entire setting store if a change is made to the structure.
	
	/// Creates a new AssetStore with the given name and build context.
	this(string identifier, BuildContext context) {
		super(identifier);
		this._context = context;
		assert(context && identifier);
		trace("Creating AssetStore named " ~ identifier);
		context.registerStore(this);
	}
	
	/// Returns an InputStream used to asynchronously read raw data for the given asset.
	abstract InputStream createInputStream(Asset asset);

	/// Returns an OutputStream used to asynchronously write the generated data for the asset.
	abstract OutputStream createOutputStream(Asset asset);
	
	/// Saves any changes to this AssetStore back to the underlying storage container.
	final void save() {
		trace("Started save outside synchronized block.");
		synchronized(this) {
			trace("Starting to perform save.");
			performSave();	
			trace("Performed save.");
		}
	}

	/// Loads the settings from the backing store into this AssetStore.
	/// The store must be newly created and thus empty, otherwise undefined behaviour will occur.
	final void load() {
		// TODO: Enforce that no changes have been made / this store is empty.
		trace("Preparing to load store data.");
		synchronized(this) {
			trace("Starting to perform load.");
			performLoad();
			trace("Performed load.");
		}
	}

	/// Returns all of the assets contained in this store.
	final auto allAssets() {
		// TODO: This is an awful implementation; use a range instead.
		Asset[] results;
		appendAssets(this, results);
		return results;
	}

	private void appendAssets(HierarchyNode node, ref Asset[] nodes) {
		foreach(child; node.children.allNodes) {
			if(child == node)
				continue;
			if(auto asset = cast(Asset)child)
				nodes ~= asset;
			else
				appendAssets(child, nodes);
		}
	}

	/// Registers the asset with the given qualified name in this AssetStore.
	/// All containers that do not exist along the path will be created.
	/// This is simply a shortcut to create a container for all non-existing 
	/// containers on the path and then create and register the final asset.
	final Asset registerAsset(string qualifiedName, string extension) {
		string[] split = HierarchyNode.splitQualifiedName(qualifiedName);
		HierarchyNode current = this;
		foreach(contName; split[0..$-1]) {
			HierarchyNode next = current.children[contName];
			if(next is null) {
				next = new AssetContainer(contName);
				current.children.add(next);
			}
			current = next;
		}
		string assetName = split[$-1];
		auto asset = new Asset(assetName, extension);
		current.children.add(asset);
		return asset;
	}
	
	/// Gets the BuildContext being used for this AssetStore.
	@property final BuildContext context() {
		return _context;
	}
	
	/// Implement to handle logic required to save the nodes and their settings.
	protected abstract void performSave();

	/// Implement to handle logic required to load files saved through a call to performSave.
	/// It is up to the caller to decide how no data to load should be handled.
	/// For most AssetStore implementations, it should merely create a new default set of settings.
	protected abstract void performLoad();
	
	/// Serializes all node settings to the given OutputStream in a way that can be read by deserializeNodes. 
	/// Assumes that the store is locked, and does not clear the current nodes.
	protected void serializeNodes(OutputStream output) {
		// TODO: Refactor serializing and deserializing nodes into a different class.
		// That way we can support more than just assets and containers too.
		// Won't be too difficult, just no need for it yet.
		trace("Using default serializeNodes method, sending output to " ~ output.text ~ ".");
		TaskPool serializePool = new TaskPool();
		NodeList nodes = new NodeList();
		// First, write the header which indicates what nodes we have.
		trace("Writing header.");
		writeHeader(output, this, nodes);
		trace("Done writing header.");
		// Then each of the nodes we wrote in our header we need to serialize the settings for.
		foreach(node; nodes) {
			serializePool.put(task(&performSerializeSettings, output, node));	
		}
		trace("Waiting for serialize pool to finish.");
		serializePool.finish(true);
		trace("All data written; serializeNodes is done.");
	}
	
	/// Deserializes all nodes from the given InputStream into this AssetStore.
	/// Assumes that the store is locked, and does not clear the current nodes.
	protected void deserializeNodes(InputStream input) {
		trace("Using default deserializeNodes method; starting read.");
		deserializeNode(input, this);
		// Next up, read settings:
		TaskPool deserializePool = new TaskPool();
		while(!input.empty) {
			ubyte[] settings = input.readPrefixed!ubyte;
			deserializePool.put(task(&deserializeSettings, settings));
		}
		trace("All tasks queued, waiting for TaskPool to finish.");
		deserializePool.finish(true);
		trace("All data read; deserializeNodes is done.");
	}

	private void deserializeSettings(ubyte[] data) {
		// Segfaults with scoped. TODO: Fix.
		//StreamReader reader = scoped!StreamReader(data, false);
		StreamReader reader = new StreamReader(data, false);
		string qualifiedName = cast(string)reader.ReadPrefixed!char;
		trace("Deserializing settings for " ~ qualifiedName ~ ".");
		HierarchyNode node = context.getNode(qualifiedName);
		enforce(node);
		size_t bytesRead = node.settings.deserialize(reader.RemainingData);
		reader.Advance(bytesRead);
		trace("Read " ~ bytesRead.text ~ " bytes for this nodes settings.");
		if(reader.Available > 0)
			warn("Node settings still had " ~ reader.Available.text ~ " bytes available. This is possibly an ignored setting.");
	}
	
	private void deserializeNode(InputStream reader, HierarchyNode parent) {
		NodeType type = cast(NodeType)read!byte(reader);
		string nodeIdentifier = cast(string)reader.readPrefixed!char();
		trace("Deserializing " ~ type.text ~ " named " ~ nodeIdentifier ~ " with parent of " ~ parent.text ~ ".");
		HierarchyNode node;
		synchronized(parent) {
			switch(type) {
				case NodeType.Store:
					if(icmp(nodeIdentifier, this.name) != 0)
						throw new Exception("The AssetStore being deserialized was not this store.");
					node = this;
					break;
				case NodeType.Asset:
					string processorName = cast(string)reader.readPrefixed!char();
					string extension = cast(string)reader.readPrefixed!char();
					auto asset = new Asset(nodeIdentifier, extension);
					parent.children.add(asset);
					asset.processorName = processorName;
					node = asset;
					break;
				case NodeType.Container:
					node = new AssetContainer(nodeIdentifier);
					parent.children.add(node);
					break;
				default:
					assert(0);
			}
		}
		uint numChildren = reader.readVal!uint();
		for(uint i = 0; i < numChildren; i++) {
			deserializeNode(reader, node);	
		}
	}
	
	private void writeHeader(OutputStream output, HierarchyNode node, NodeList nodes) {
		trace("Writing header for " ~ node.text ~ ".");
		NodeType type;
		if(cast(Asset)node)
			type = NodeType.Asset;
		else if(cast(AssetStore)node)
			type = NodeType.Store;
		else if(cast(AssetContainer)node)
			type = NodeType.Container;
		else
			throw new Error("Unknown node type. The default serialize method supports only assets and containers.");
		output.writeVal(cast(ubyte)type);
		output.writePrefixed(node.name);
		if(auto asset = cast(Asset)node) {
			output.writePrefixed(asset.processorName);
			output.writePrefixed(asset.extension);
		}
		output.writeVal(cast(uint)node.children.length);
		nodes.Add(node);
		//tasks.Add(task(&performSerializeSettings, input, node));
		foreach(HierarchyNode child; node.children) {
			writeHeader(output, child, nodes);
		}
	}
	
	private void performSerializeSettings(OutputStream output, HierarchyNode node) {
		trace("Serializing settings for " ~ node.text ~ ".");
		Buffer buff = BufferPool.Global.Acquire(4096);
		buff.WritePrefixed(node.qualifiedName);
		auto settings = node.settings;
		settings.serialize(buff);
		synchronized(output)
			output.writePrefixed(buff.Data);
		trace("Done serializing settings for " ~ node.text ~ " (" ~ buff.Count.text ~ " bytes).");
		BufferPool.Global.Release(buff);
	}
	
	private enum NodeType : byte {
		Container = 1,
		Asset = 2,
		Store = 3
	}
	
	/+ TODO: This will be used for if renaming or moving assets is allowed, so we can update references as well.
	 /// Gets all references to the given asset.
	 abstract AssetReference[] referencesToAsset(Asset asset);+/
	
	private BuildContext _context;
	private alias LinkedList!(HierarchyNode) NodeList;
}

