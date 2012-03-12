module ShardTools.Event;
private import ShardTools.List;

/// Represents an event with no parameters besides the mandatory sender, and no return value.
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
	static if(!is(RetValue == void)) {
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