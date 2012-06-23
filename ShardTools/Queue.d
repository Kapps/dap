module ShardTools.Queue;


/// Provides a queue that allocates with the garbage collector.
/// This class is a temporary placeholder until Phobos gets real collections.
class Queue(T)  {

public:
	/// Initializes a new instance of the Queue object.
	this() {
		
	}

	size_t length() {
		return Elements.length;
	}

	void push(T Element) {
		Elements ~= Element;
	}

	T pop(lazy T DefaultValue = T.init) {
		if(Elements.length == 0)
			return DefaultValue();
		T Result = Elements[0];
		Elements = Elements[1..$].dup;
		return Result;
	}

	T peek(lazy T DefaultValue = T.init) {
		if(Elements.length == 0)
			return DefaultValue();
		return Elements[0];
	}
	
private:
	T[] Elements;
}