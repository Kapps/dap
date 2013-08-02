module ShardTools.IDisposable;
import ShardTools.ExceptionTools;

// TODO: Not sure if this should exist. Consider phasing out.

mixin(MakeException("ObjectDisposedException", "The object attempted to be accessed was already disposed."));

/// An interface used to handle disposing of an asset, including tracking of whether it is disposed.
interface IDisposable {
	
	/// Disposes of this object, provided it has not already been disposed.
	public final void Dispose() {
		if(!IsDisposed)
			return;
		OnDispose();		
	}
	
	/// Gets a value whether this object is currently disposed.
	@property nothrow bool IsDisposed() const;			
	
	/// Occurs when this object has Dispose called when it was not already disposed.
	/// It is possible for this to get called in a destructor, and thus it should not reference any subobjects.
	protected void OnDispose();	
}