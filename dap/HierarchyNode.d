module dap.HierarchyNode;
public import dap.AssetStore;
import std.range;
import std.algorithm;
import dap.NodeSettings;
import dap.NodeCollection;
import std.exception;
import std.conv;

/// Represents a character that indicates a separation of a HierarchyNode for a qualified name.
enum char nodeSeparator = ':';

/// Provides the base node in the Asset hierarchy.
/// This class, and any derived classes, are $(B, NOT) thread-safe.
class HierarchyNode {
	
	/// Creates a new HierarchyNode with the given identifier, parent.
	this(string identifier, HierarchyNode parent) {
		enforce(identifier, "Identifier can not be null.");
		//enforce(parent, "Parent can not be null.");
		this._identifier = identifier;
		this._parent = parent;
		this._settings = new NodeSettings(this);
		this._children = new NodeCollection(this);
	}
	
	/// Returns the child nodes that this node contains.
	@property NodeCollection children() {
		return _children;	
	}
	
	/// Gets an identifier used to represent this node.
	/// For example, an asset may return the name of the asset, while an AssetDirectory could return the name of the directory.
	@property final string identifier() const {
		return _identifier;
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
	@property static string[] splitQualifiedName(string qualifiedName) {
		return splitter(qualifiedName, nodeSeparator).array;
	}
	
	/// Returns the fully qualified name of this node, with identifiers being separated by $(D, nodeSeparator).
	/// If parent is null, returns identifier.
	final @property string qualifiedName() {
		// TODO: This could be easily optimized if need be. First calculate length, then allocate.
		// Or just cache it.
		string result = this.identifier;
		for(HierarchyNode node = this.parent; node !is null; node = node.parent) {
			result = node.identifier ~ nodeSeparator ~ result;
		}
		return result;
	}

	/// A shortcut to log a message with the Trace severity.
	final void trace(string details) {
		root.context.logger.logMessage(MessageSeverity.Trace, details, this);
	}

	/// A shortcut to log a message with the Info severity.
	final void info(string details) {
		root.context.logger.logMessage(MessageSeverity.Info, details, this);
	}
	
	/// A shortcut to log a message with the Warning severity.
	final void warn(string details) {
		root.context.logger.logMessage(MessageSeverity.Warning, details, this);
	}

	/// Returns a string representation of this node containing the qualified name and type.
	override string toString() {
		return this.qualifiedName ~ "[" ~ typeid(this).text ~ "]";
	}
	
	private string _identifier;
	private HierarchyNode _parent;
	private NodeSettings _settings;
	private NodeCollection _children;
}
