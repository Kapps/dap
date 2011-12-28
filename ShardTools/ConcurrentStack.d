module ShardTools.ConcurrentStack;
private import core.atomic;

/// A stack with only thread-safe, atomic, operations.
@disable shared class ConcurrentStack(T)  {

public:
	/// Initializes a new instance of the ConcurrentStack object.
	this() {
		
	}
	
	private shared struct Node {
		T Value;
		Node* Next;			

		this(T Value) { 
			this.Value = cast(shared)Value;
		}
	}		

	/// Pushes the given value to the top of the stack.
	/// Params:
	/// 	Value = The value to push.
	void Push(T Value) {
		auto NewNode = new Node(Value);
		shared(Node)* OldNode;
		do {
			OldNode = Root;
			NewNode.Next = OldNode;
		} while(!cas(cast(shared(Node)**)&Root, cast(shared(Node)*)OldNode, cast(shared(Node)*)NewNode));
	}

	/// Pops the given value from the top of the stack.
	/// Returns a pointer to the resulting value, or null if the stack is empty.
	shared(T)* Pop() {
		typeof(return) Result;
		shared(Node)* OldNode;
		do {
			OldNode = Root;
			if(!OldNode)
				return null;
			Result = &OldNode.Value;
		} while(!cas(&Root, OldNode, OldNode.Next));
		return Result;
	}

	unittest {
		ConcurrentStack!int Stack = new ConcurrentStack!int();
		Stack.Push(3);
		assert(*Stack.Pop == 3);
	}
	
private:
	shared(Node)* Root;	
}