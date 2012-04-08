module ShardTools.LinkedList;
private import std.functional;


/// A basic doubly linked list.
/// Params:
/// 	T = The type of the elements within the list.
final class LinkedList(T) {

public:
	/// Initializes a new instance of the LinkedList object.
	this() {
			
	}

	/// Gets the first node within the list.
	@property LinkedListNode Head() {
		return _Head;
	}

	/// Gets the last node within the list.
	@property LinkedListNode Tail() {
		return _Tail;
	}

	/// Gets the number of elements this collection contains.
	@property size_t Count() const {
		return _Count;
	}

	int opApply(int delegate(ref T, LinkedListNode Node) dg) {
		int Result = 0;
		for(LinkedListNode Node = _Head; Node !is null; Node = Node.Next) {
			if((Result = dg(Node._Value, Node)) != 0)
				break;
		}
		return Result;
	}

	int opApply(int delegate(ref T) dg) {
		int Result = 0;
		for(LinkedListNode Node = _Head; Node !is null; Node = Node.Next) {
			if((Result = dg(Node._Value)) != 0)
				break;
		}
		return Result;
	}

	/// Appends the given value to the back of the list.
	void Add(T Value) {
		LinkedListNode Node = new LinkedListNode();
		Node._Previous = _Tail;
		if(_Tail)
			_Tail._Next = Node;		
		_Tail = Node;
		if(!_Head)
			_Head = Node;
		Node._Value = Value;
		_Count++;
	}

	/// Removes the given element from the list.
	bool Remove(T Value) {
		LinkedListNode Node = GetNode(Value);
		if(Node is null)
			return false;
		Remove(Node);
		return true;
	}

	/+
	/// Removes the head node and returns the value it stores, or DefaultValue if no elements exist.
	T PopHead(lazy T Default = T.init) {
		if(_Head) {
			_Head = _Head._Next;
			if(_Head)
				_Head._Previous = null;
		}
	}+/

	/// Removes the given node from the list.
	void Remove(LinkedListNode Node) {
		assert(GetNode(Node._Value) !is null, "Node was not part of this linked list.");
		if(Node._Previous)
			Node._Previous._Next = Node._Next;
		if(Node._Next)
			Node._Next._Previous = Node._Previous;
		if(Node is _Head)
			_Head = _Head._Next;
		if(Node is _Tail)
			_Tail = _Tail._Previous;
		_Count--;
	}

	/// Gets the node that contains the given value, or null if no node contained the given value.
	LinkedListNode GetNode(T Value) {
		for(LinkedListNode Node = this._Head; Node !is null; Node = Node.Next) {
			if(Node._Value == Value)
				return Node;
		}		
		return null;
	}

	static class LinkedListNode {
		/// Gets the node prior to this node.
		@property LinkedListNode Previous() {
			return _Previous;
		}

		/// Gets the node following this node.
		@property LinkedListNode Next() {
			return _Next;
		}

		/// Gets the object contained by this node.
		@property T Value() {
			return _Value;
		}

		package T _Value;
		package LinkedListNode _Previous;
		package LinkedListNode _Next;
	}

	unittest {
		LinkedList!int List = new LinkedList!int();
		assert(List.Count == 0);
		List.Add(2);
		assert(List.Count == 1);
		assert(List.Head == List.Tail);
		assert(List.Head.Value == 2);
		assert(List.GetNode(2) == List.Head);
		assert(List.Remove(2));
		assert(List.Count == 0);
		List.Add(3);
		List.Add(4);
		assert(List.Count == 2);
		assert(List.Head != List.Tail);
		assert(List.Head.Value == 3);
		assert(List.Tail.Value == 4);
	}
	
private:
	LinkedListNode _Head;
	LinkedListNode _Tail;
	size_t _Count;
}