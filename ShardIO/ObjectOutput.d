module ShardIO.ObjectOutput;
public import ShardTools.Event;
public import ShardIO.OutputSource;
import ShardTools.Buffer;

/+/// Provides an ObjectOutput to parse an object written by MessagePack.
public T ParseMessagePackedObject(T)(ubyte[] data) {
	// return NotEnoughBytes to make next Data have more bytes avail.
	// Provide a max number of bytes stored, and if too many, abort the parse.
	return T.init;
}+/

/// Represents an OutputSource that parses input data to create an object, then operates on the completed objects.
/// Params:
///		T = The type of the object to create.
abstract class ObjectOutput(T) : OutputSource {	

public:

	alias Event!(void, T) ObjectCreatedEvent;

	/// Initializes a new instance of the ObjectOutput object.
	this() {
		_ObjectCreated = new ObjectCreatedEvent();
	}

	/// Gets an event called whenever an object is finished being created.
	@property ObjectCreatedEvent ObjectCreated() {
		return _ObjectCreated;
	}

protected:	

	/// Notifies the ObjectOutut that an instance has been fully created.
	/// Params:
	/// 	Obj = The object that was created.
	void NotifyObjectBuild(T Obj) {
		ObjectCreated.Execute(Obj);
	}

private:
	ObjectCreatedEvent _ObjectCreated;
}