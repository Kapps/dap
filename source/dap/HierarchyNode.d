module dap.HierarchyNode;
public import dap.AssetStore;
import ShardTools.ExceptionTools;
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
	
	/// Creates a new HierarchyNode with the given identifier.
	/// If the identifier is not a valid node name, an exception is thrown.
	this(string name) {
		if(!isValidName(name))
			throw new InvalidFormatException("The name of this node was not valid.");
		this._name = name;
		this._settings = new NodeSettings(this);
		this._children = new NodeCollection(this);
	}
	
	/// Returns the child nodes that this node contains.
	@property final NodeCollection children() @safe pure nothrow {
		return _children;	
	}
	
	/// Gets an identifier used to represent this node.
	/// For example, an asset may return the name of the asset, while an AssetDirectory could return the name of the directory.
	@property final string name() const @safe pure nothrow {
		return _name;
	}
	
	/// Gets the parent that owns this node.
	@property final HierarchyNode parent() @safe pure nothrow {
		return _parent;
	}
	
	@property package void parent(HierarchyNode node) @safe pure nothrow {
		assert(parent is null);
		assert(node !is null);
		this._parent = node;
	}
	
	/// Gets the root node for this HierarchyNode, which is the AssetStore being used.
	/// If this node has no root AssetStore, null is returned.
	@property final AssetStore root() @safe pure nothrow {
		if(parent is null)
			return cast(AssetStore)this;
		return parent.root;
	}
	
	/// Gets the settings that apply to this node.
	@property final NodeSettings settings() @safe pure nothrow {
		return _settings;	
	}

	/// Indicates if the given unqualified node name is valid.
	static bool isValidName(string nodeName) @safe pure {
		return nodeName.length > 0 && std.string.indexOf(nodeName, nodeSeparator) < 0 && nodeName.length < 256;
	}

	unittest {
		assert(isValidName("abc"));
		assert(!isValidName(""));
		assert(isValidName("ab00f"));
		assert(!isValidName(null));
		assert(!isValidName("ab" ~ nodeSeparator ~ "cdef"));
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
		enforce(root);
		root.context.logger.trace(details, this);
	}

	/// A shortcut to log a message with the Info severity.
	final void info(string details) {
		enforce(root);
		root.context.logger.info(details, this);
	}
	
	/// A shortcut to log a message with the Warning severity.
	final void warn(string details) {
		enforce(root);
		root.context.logger.warn(details, this);
	}

	/// Returns a string representation of this node containing the qualified name and type.
	override string toString() {
		string type = typeid(this).text;
		size_t index = type.retro.countUntil('.');
		if(index > 0)
			type = type[$ - index .. $];
		return this.qualifiedName ~ " (" ~ type ~ ")";
	}
	
	private string _name;
	private HierarchyNode _parent;
	private NodeSettings _settings;
	private NodeCollection _children;
}
