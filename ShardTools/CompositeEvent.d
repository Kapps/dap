module ShardTools.CompositeEvent;

public import ShardTools.Event;

/// Represents an Event that is the combination of zero or more subevents, and is called when any of those subevents are called.
@disable class CompositeEvent(RetValue, Params...) {

public:

	alias Event!(RetValue, Params) EventType;

	/// Initializes a new instance of the CompositeEvent object.
	this() {
		
	}

	/// Adds the given event to the event collection.	
	void AddEvent(EventType Ev) {

	}

	/// Removes the given event from the event collection.
	void RemoveEvent(EventType Ev) {

	}
	
private:
	EventType[] _Events;
}