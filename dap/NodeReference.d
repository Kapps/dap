module dap.NodeReference;
public import dap.HierarchyNode;
import std.traits;
import std.conv;

/// Provides a reference to a different hierarchy node, such as an asset or container.
class NodeReference {

	/// Creates a NodeReference from referencedBy to referenced.
	this(T1, T2)(T1 referenced, T2 referencedBy) {
		mixin(getConstructorConversionMixin("referenced", "T1"));
		mixin(getConstructorConversionMixin("referencedBy", "T2"));
	}
	
	private static string getConstructorConversionMixin(string identifier, string type) {
		return "static if(isSomeString!" ~ type ~ ") {
			_" ~ identifier ~ " = to!string(" ~ identifier ~ ");
		} else static if(is(" ~ type ~ " : HierarchyNode)) {
			_" ~ identifier ~ " = " ~ type ~ ".qualifiedName;
		} else static assert(0, \"" ~ type ~ " must be a string for the qualified name of the asset, or the asset itself.\");";
	}
	
	string _referenced;
	string _referencedBy;
}

