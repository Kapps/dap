module ShardTools.SoftReference;
import std.container;

/// Provides a reference to a value that will be cleared when memory runs low.
/// BUGS:
///		At the moment, this requires hijacking onMemoryError to clear soft references.
@disable class SoftReference(T) {

public:
	/// Initializes a new instance of the SoftReference object.
	this() {
		
	}
	
private:
//	static __gshared RedBlackTree!(Object) AllReferences;

}