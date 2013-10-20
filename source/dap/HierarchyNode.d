module dap.HierarchyNode;
public import dap.AssetStore;
import std.range;
import std.algorithm;
import dap.NodeSettings;
import dap.NodeCollection;
import std.exception;
import std.conv;
import std.regex;
import std.path;

/// Represents a character that indicates a separation of a HierarchyNode for a qualified name.
enum char nodeSeparator = ':';

/// Provides the base node in the Asset hierarchy.
/// This class, and any derived classes, are $(B NOT) thread-safe unless otherwise specified.
class HierarchyNode {
	
	/// Creates a new HierarchyNode with the given identifier, parent.
	this(string name, HierarchyNode parent) {
		enforce(name, "Name can not be null.");
		//enforce(parent, "Parent can not be null.");
		this._name = name;
		this._settings = new NodeSettings(this);
		this._children = new NodeCollection(this);
		if(parent)
			parent.children.add(this);
	}
	
	/// Returns the child nodes that this node contains.
	@property NodeCollection children() {
		return _children;	
	}
	
	/// Gets an identifier used to represent this node.
	/// For example, an asset may return the name of the asset, while an AssetDirectory could return the name of the directory.
	@property final string name() const {
		return _name;
	}
	
	/// Gets the parent that owns this node.
	@property final HierarchyNode parent() {
		return _parent;
	}
	
	@property package void parent(HierarchyNode node) {
		this._parent = node;
	}
	
	/// Gets the root node for this HierarchyNode, which is the AssetStore being used.
	@property final AssetStore root() {
		if(parent is null)
			return cast(AssetStore)this;
		return parent.root;
	}
	
	/// Gets the settings that apply to this node.
	@property final NodeSettings settings() {
		return _settings;	
	}
	
	/// Splits a qualified name into it's individual parts, with the first element being the AssetStore.
	static string[] splitQualifiedName(string qualifiedName) {
		return splitter(qualifiedName, nodeSeparator).array;
	}

	unittest {
		assert(splitQualifiedName("Textures:TestTexture") == ["Textures", "TestTexture"]);
		assert(splitQualifiedName("Textures") == ["Textures"]);
	}

	/// Converts the given relative path into the fully qualified name of a HierarchyNode.
	static string nameFromPath(string relativePath) {
		// TODO: A regex for this seems a bit overkill.
		// But no other split method allows us to split on multiple characters.
		string noext = stripExtension(relativePath);
		auto split = std.regex.splitter(noext, regex(`[/\\]`));
		return join(split, nodeSeparator.to!string);
	}

	unittest {
		assert(nameFromPath("Textures/TestTexture.png") == "Textures:TestTexture");
		assert(nameFromPath("Textures\\TestTexture.png") == "Textures:TestTexture");
	}
	
	/// Returns the fully qualified name of this node, with identifiers being separated by $(D, nodeSeparator).
	/// If parent is null, returns identifier.
	final @property string qualifiedName() {
		// TODO: This could be easily optimized if need be. First calculate length, then allocate.
		// Or just cache it.
		string result = this.name;
		for(HierarchyNode node = this.parent; node !is null; node = node.parent) {
			result = node.name ~ nodeSeparator ~ result;
		}
		return result;
	}

	/// A shortcut to log a message with the Trace severity.
	final void trace(string details) {
		root.context.logger.trace(details, this);
	}

	/// A shortcut to log a message with the Info severity.
	final void info(string details) {
		root.context.logger.info(details, this);
	}
	
	/// A shortcut to log a message with the Warning severity.
	final void warn(string details) {
		root.context.logger.warn(details, this);
	}

	/// Returns a string representation of this node containing the qualified name and type.
	override string toString() {
		return this.qualifiedName ~ "[" ~ typeid(this).text ~ "]";
	}
	
	private string _name;
	private HierarchyNode _parent;
	private NodeSettings _settings;
	private NodeCollection _children;
}
