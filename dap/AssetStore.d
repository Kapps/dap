module dap.AssetStore;
public import dap.HierarchyNode;
public import dap.Asset;
public import dap.AssetContainer;
public import dap.BuildContext;
public import ShardIO.IOAction;
import ShardIO.StreamInput;
import std.parallelism;
import ShardTools.MessagePack;
import ShardTools.Buffer;
import ShardTools.BufferPool;
import ShardTools.LinkedList;
import ShardTools.StreamReader;
import ShardIO.MemoryOutput;
import ShardIO.MemoryOutput;
import core.time;
import std.string;
import ShardTools.ExceptionTools;
import std.exception;
import std.conv;

/// Provides the implementation of any storage operations, such as loading data for an asset.
abstract class AssetStore : HierarchyNode {
	
	/// Creates a new AssetStore with the given name and build context.
	this(string identifier, BuildContext context) {
		super(identifier, null);
		this._context = context;
		assert(context && identifier);
		trace("Creating AssetStore named " ~ identifier);
		context.registerStore(this);
	}
	
	/// Returns an InputSource used to read data for the given asset.
	abstract InputSource createInputSource(Asset asset);
	/// Returns an OutputSource used to write the generated data for the asset.
	abstract OutputSource createOutputSource(Asset asset);
	
	/// Saves any changes to this AssetStore back to the underlying storage container.
	final void save() {
		trace("Started save outside synchronized block.");
		synchronized(this) {
			trace("Starting to perform save.");
			performSave();	
			trace("Performed save.");
		}
	}
	
	/// Registers the given child container as parent of this AssetStore.
	final AssetContainer registerContainer(HierarchyNode parent, string name) {
		if(!isValidName(name))
			throw new InvalidFormatException("The container name was not valid.");
		enforce(parent !is null);
		trace("Registering container named " ~ name ~ " under " ~ parent.qualifiedName ~ ".");
		auto result = createContainer(parent, name);
		trace("Registered container named " ~ result.qualifiedName ~ ".");
		return result;
	}
	
	/// Registers the given asset as parent of this AssetStore.
	final Asset registerAsset(HierarchyNode parent, string name) {
		if(!isValidName(name))
			throw new InvalidFormatException("The asset name was not valid.");
		enforce(parent !is null);
		trace("Registering asset named " ~ name ~ " under " ~ parent.qualifiedName ~ ".");
		auto result = createAsset(parent, name);
		trace("Registered asset named " ~ result.qualifiedName ~ ".");
		return result;
	}
	
	/// Creates an AssetContainer with the specified parent and name.
	/// The parent is guaranteed to be created by either createAsset or createContainer, or be this instance of AssetStore.
	/// The parent should contain the resulting AssetContainer at the end of this method.
	protected AssetContainer createContainer(HierarchyNode parent, string name) {
		return new AssetContainer(name, parent);	
	}
	
	/// Creates a new AssetContainer with the specified parent and name.
	/// The parent is guaranteed to be created by either createAsset or createContainer, or be this instance of AssetStore.
	/// The parent should contain the resulting Asset at the end of this method.
	protected Asset createAsset(HierarchyNode parent, string name) {
		return new Asset(name, parent);
	}
	
	/// Indicates if the given node name is valid.
	protected bool isValidName(string nodeName) {
		return nodeName.indexOf(nodeSeparator) < 0;
	}
	
	/// Gets the BuildContext being used for this AssetStore.
	@property final BuildContext context() {
		return _context;
	}
	
	/// Implement to handle logic required to save the nodes and their settings to a file.
	protected abstract void performSave();
	
	/// Serializes all node settings to the given OutputSource, in a way that can be read by deserializeNodes. 
	/// Assumes that the store is locked.
	protected void serializeNodes(OutputSource output) {
		// TODO: Refactor serializing and deserializing nodes into a different class.
		// That way we can support more than just assets and containers too.
		// Won't be too difficult, just no need for it yet.
		trace("Using default serializeNodes method, sending output to " ~ output.text ~ ".");
		StreamInput input = new StreamInput(FlushMode.AfterSize(4096));
		TaskPool serializePool = new TaskPool();
		IOAction action = new IOAction(input, output);
		trace("Starting IOAction.");
		action.Start();
		trace("Started IOAction.");
		NodeList nodes = new NodeList();
		// First, write the header which indicates what nodes we have.
		trace("Writing header.");
		writeHeader(input, this, nodes);
		trace("Done writing header.");
		// Then each of the nodes we wrote in our header we need to serialize the settings for.
		foreach(node; nodes) {
			serializePool.put(task(&performSerializeSettings, input, node));	
		}
		trace("Waiting for serialize pool to finish.");
		serializePool.finish(true);
		trace("Serialize pool finished; completing input.");
		input.Complete();
		trace("Input is complete; waiting for IOAction to complete.");
		// When that's done, just wait for IO to finish and we're set.
		action.WaitForCompletion(dur!"seconds"(30));
		trace("IOAction is complete, serializeNodes is done.");
	}
	
	/// Deserializes all nodes from the given InputSource, returning the nodes at the time of serializeNodes.
	/// Assumes that the store is locked, and does not clear the current nodes.
	protected void deserializeNodes(InputSource input) {
		// TODO: This is a dumb approach.
		// Use a StreamOutput instead, so we can read at the same time as write, and not have to keep everything in memory.
		// Just gotta implement StreamOutput first though.
		trace("Using default deserializeNodes method, reading input from " ~ input.text ~ ".");
		MemoryOutput output = new MemoryOutput();
		IOAction action = new IOAction(input, output);
		trace("Starting IOAction for deserializeNodes.");
		action.Start();
		trace("IOAction has begun. Waiting for all memory to be read.");
		action.WaitForCompletion(dur!"seconds"(30));
		trace("The IOAction has completed, all data is in memory. Starting to deserialize the " ~ output.Data.length.text ~ "bytes.");
		StreamReader reader = new StreamReader(output.Data, true);
		deserializeNode(reader, this);
		TaskPool deserializePool = new TaskPool();
		while(reader.Available > 0) {
			string node = cast(string)reader.ReadPrefixed!char;
			ubyte[] settings = reader.ReadPrefixed!ubyte;
		}
	}
	
	private void readSettings(StreamReader reader) {
		TaskPool settingPool = new TaskPool();
		while(reader.Available > 0) {
			ubyte[] data = reader.ReadPrefixed!ubyte;	
			settingPool.put(task(&deserializeSettings, data));
		}
	}
	
	private void deserializeSettings(ubyte[] data) {
		StreamReader reader = new StreamReader(data, false);
		string qualifiedName = cast(string)reader.ReadPrefixed!char;
		HierarchyNode node = context.getNode(qualifiedName);
	}
	
	private void deserializeNode(StreamReader reader, HierarchyNode parent) {
		NodeType type = cast(NodeType)reader.Read!byte();
		string nodeIdentifier = cast(string)reader.ReadPrefixed!char();
		trace("Deserializing " ~ type ~ " named " ~ nodeIdentifier ~ " with parent of " ~ parent.text ~ ".");
		HierarchyNode node;
		synchronized(parent) {
			switch(type) {
				case NodeType.Store:
					if(icmp(nodeIdentifier, this.identifier) != 0)
						throw new Exception("The AssetStore being deserialized was not this store.");
					node = this;
					break;
				case NodeType.Asset:
					node = createAsset(parent, nodeIdentifier);
					break;
				case NodeType.Container:
					node = createContainer(parent, nodeIdentifier);
					break;
				default:
					throw new Error("Unknown NodeType");
			}
		}
		uint numChildren = reader.Read!uint();
		trace("Node has " ~ numChildren.text ~ " children.");
		for(uint i = 0; i < numChildren; i++) {
			deserializeNode(reader, node);	
		}
	}
	
	private void writeHeader(StreamInput input, HierarchyNode node, NodeList nodes) {
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
		input.Write(cast(ubyte)type);
		input.WritePrefixed(node.identifier);
		input.Write(cast(int)node.children.length);
		nodes.Add(node);
		//tasks.Add(task(&performSerializeSettings, input, node));
		foreach(HierarchyNode child; node.children) {
			writeHeader(input, child, nodes);
		}
	}
	
	private void performSerializeSettings(StreamInput input, HierarchyNode node) {
		trace("Serializing settings for " ~ node.text ~ ".");
		Buffer buff = BufferPool.Global.Acquire(4096);
		buff.WritePrefixed(node.qualifiedName);
		auto settings = node.settings;
		settings.serialize(buff);
		input.WritePrefixed(buff.Data);
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

