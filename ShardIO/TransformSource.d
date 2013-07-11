module ShardIO.TransformSource;
public import ShardIO.IOAction;
/+

/// Wraps either an InputSource or OutputSource and applies zero or more DataTransformers to the data being sent to them.
class TransformSource(T) : T if(is(T : InputSource) || is(T : OutputSource))  {

public:
	/// Initializes a new instance of the TransformSource object.
	this() {
		
	}
	
private:
}+/