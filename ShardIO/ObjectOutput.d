module ShardIO.ObjectOutput;
public import ShardTools.Event;
public import ShardIO.OutputSource;


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