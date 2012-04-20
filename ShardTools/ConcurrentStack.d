module ShardTools.ConcurrentStack;
private import core.atomic;

/// Provides a thread-safe and lock-free implementation of a Stack.
/// BUGS:
///		Manual memory management of stored values is not allowed because this implementation suffers from the ABA problem.
class ConcurrentStack(T)  {

public:

	// TODO: Check to make sure ABA problem is fine with garbage collection.

	/// Initializes a new instance of the ConcurrentStack object.
	this() {
		
	}
	
	private struct Node {
		T Value;
		Node* Next;			

		this(T Value) { 
			this.Value = Value;
		}
	}		

	/// Pushes the given value to the top of the stack.
	/// This operation is O(1), thread-safe, and lock-free.
	/// Params:
	/// 	Value = The value to push.
	void Push(T Value) {		
		Node* NewNode = new Node(Value);
		Node* OldNode;
		do {
			OldNode = Root;
			NewNode.Next = OldNode;
		} while(!cas(cast(shared)&Root, cast(shared)OldNode, cast(shared)NewNode));
	}

	/// Pops the given value from the top of the stack.
	/// Returns the resulting value, or DefaultValue if the stack is empty.
	/// This operation is O(1) (if DefaultValue is O(1) or the Stack has elements), thread-safe, and lock-free.
	T Pop(lazy T DefaultValue = T.init) {		
		T Result;
		if(!TryPop(Result))
			return DefaultValue();
		return Result;
	}

	/// Attempts to Pop a value from the top of the stack, returning whether or not there was an element to pop.
	/// This operation is O(1), thread-safe, and lock-free.
	bool TryPop(out T Value) {
		Node* OldNode;
		T Result;
		do {
			OldNode = Root;
			if(!OldNode)
				return false;
			Result = OldNode.Value;
		} while(!cas(cast(shared)&Root, cast(shared)OldNode, cast(shared)OldNode.Next));
		Value = Result;
		return true;
	}

	/// Repeatedly pops values until the stack is empty, calling dg on them.
	int opApply(int delegate(T) dg) {
		int Result;
		T Value;
		while(TryPop(Value)) {
			if((Result = dg(Value)) != 0)
				break;
		}
		return Result;
	}

	unittest {
		ConcurrentStack!int Stack = new ConcurrentStack!int();
		Stack.Push(3);
		assert(Stack.Pop == 3);
	}
	
private:
	Node* Root;	
}