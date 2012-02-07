module ShardTools.LinkedList;


/// A basic doubly linked list.
/// Params:
/// 	T = The type of the elements within the list.
@disable class LinkedList(T) {

public:
	/// Initializes a new instance of the LinkedList object.
	this() {
		
	
	}

	class LinkedListNode {
		/// Gets the node prior to this node.
		@property LinkedListNode Previous() {
			return _Previous;
		}

		/// Gets the node following this node.
		@property LinkedListNode Nxet() {
			return _Next;
		}

		/// Gets the object contained by this node.
		@property T Value() {
			return _Value;
		}

		private T _Value;
		private LinkedListNode _Previous;
		private LinkedListNode _Next;
	}

	/// Gets the first node within the list.
	@property LinkedListNode Head() {
		return _Head;
	}

	/// Gets the last node within the list.
	@property LinkedListNode Tail() {
		return _Tail;
	}
	
private:
	LinkedListNode _Head;
	LinkedListNode _Tail;
}