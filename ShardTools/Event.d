module ShardTools.Event;
private import core.memory;
private import ShardTools.BufferPool;
private import ShardTools.Buffer;
private import std.traits;
private import ShardTools.List;

/// Represents an event with zero or more parameters, and optionally a return value.
/// This class is thread safe.
alias Event!(void) ActionEvent;

/// Represents a collection of delegates to be invoked dynamically.
class Event(RetValue, Params...) {		

	alias RetValue delegate(Params) CallbackType;

	/// Initializes a new instance of the Event class.
	this() {
		Callbacks = new typeof(Callbacks)();
	}
	
	/**
	 * Executes the specified callback.
	 * Params: 
	 *	sender = The object invoking this callback.
	 *	Params = The parameters for the callback.
	*/
	/+static if(!is(RetValue == void)) {
		//TD: Remove lock. Use a concurrent singly linkde list instead.
		// Just duplicating inside a lock is slower...
		RetValue[] Execute(Params Parameters) {
			synchronized(this) {
				if(!HasSubscribers)
					return null;
				CallbackType[] Pointers = this.Callbacks.Elements;
				RetValue[] Result = new RetValue[Pointers.length];
				for(size_t i = 0; i < Pointers.length; i++)
					Result[i] = Pointers[i](Parameters);
				return Result;
			}
		}
	} else {
		void Execute(Params Parameters) {
			synchronized(this) {
				if(!HasSubscribers)
					return;
				foreach(dg; this.Callbacks)
					dg(Parameters);
			}
		}
	}+/

	Select!(is(RetValue == void), void, RetValue[]) Execute(Params Parameters) {		
		// Fun! Turns out, doing this is actually creating a huge amount of garbage.
		// So... we are going to use a whole lot of manual memory management and hacks.
		// This could all be solved by a thread-safe singly linked list... but that's more complicated and may not solve the issue really.
		CallbackType[] Pointers;
		Buffer PointerBuffer = BufferPool.Global.Acquire(this.Callbacks.Count * CallbackType.sizeof);
		//GC.disable(); // Because our buffers are not scanned for pointers, we disable the garbage collector until we do the callback...
		scope(exit) { 
			BufferPool.Global.Release(PointerBuffer);
			//GC.enable();
		}
		synchronized(this) {			
			foreach(ref CallbackType Callback; this.Callbacks)
				PointerBuffer.Write(Callback);
			Pointers = cast(CallbackType[])PointerBuffer.Data;
		}			
		static if(!is(RetValue == void)) {
			if(Pointers.length == 0)
				return null;
			RetValue[] Result = new RetValue[Pointers.length];
			//for(size_t i = 0; i < Pointers.length; i++)
			foreach(i, ref Callback; Pointers)
				Result[i] = Callback(Parameters);
			return Result;					
		} else {
			if(Pointers.length == 0)
				return;
			foreach(ref CallbackType Pointer; Pointers)
				Pointer(Parameters);
		}		
	}
			
	/**
	 * Adds the specified callback to the collection.
	 * Params: Callback = The callback to add.
	*/
	void Add(CallbackType Callback) {
		synchronized(this) {
			Callbacks.Add(Callback);
		}
		/*Pointers.length = Pointers.length + 1;
		Pointers[NextSlot] = RetValue delegate(Object, Params);
		NextSlot++;	*/
	}	

	/// Returns a value indicating whether this Event has any subscribers.
	@property bool HasSubscribers() const {
		synchronized(this) {
			return Callbacks.Count != 0;
		}
	}

	/**
	 * Removes the specified callback from this collection.
	 * Returns: Whether the callback was removed.
	*/
	bool Remove(CallbackType Callback) {
		synchronized(this) {
			return Callbacks.Remove(Callback);
		}
	}

	static if(is(RetValue == void)) {
		RetValue opCall(Params Parameters) {
			Execute(Parameters);
		}
	} else {
		void opCall(Params Parameters) {
			Execute(Parameters);
		}
	}

	void opOpAssign(string Operator)(CallbackType Callback) if(Operator == "~" || Operator == "+") {
		Add(Callback);
	}

	bool opOpAssign(string Operator)(CallbackType Callback) if(Operator == "-") {
		return Remove(Callback);
	}

	/+void opAddAssign(RetValue delegate(Object, Params) Callback) {
		Add(Callback);
	}

	bool opSubtractAssign(RetValue delegate(Object, Params) Callback) {
		return Remove(Callback);
	}+/

private:
	List!(CallbackType) Callbacks;
	//RetValue delegate(Object, Params)[]  Pointers;
	//int NextSlot = 0;
}