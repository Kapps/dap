module ShardTools.Disposable;
public import ShardTools.IDisposable;

/// An abstract class providing a basic implementation of the IDisposable interface.
abstract class Disposable : IDisposable {
	
	/// Gets a value whether this object is currently disposed.
	nothrow bool IsDisposed() const {
		return _IsDisposed;	
	}
	
	/// Occurs when this object has Dispose called when it was not already disposed.
	protected void OnDispose() {
		_IsDisposed = true;	
	}
	
	~this() {
		IDisposable.Dispose();	
	}
	
	private bool _IsDisposed = false;
}
