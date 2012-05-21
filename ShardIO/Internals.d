module ShardIO.Internals;

private import std.typecons;
private import ShardTools.NativeReference;
private import std.socket;
version(Windows) {
	private import core.sys.windows.windows;
}

package:

alias void delegate(void*, size_t, size_t) AsyncIOCallback;

/// Creates a structure that stores information for asynchronous operations.
/// Information contains a garbage collector reference internally until UnwrapOperation or CancelOperation are called.
/// Not calling UnwrapOoperation will result in memory leaks.
/// The return type is dependent on the controller used. For example, IOCP returns an OVERLAPPED[Extended]* to be passed in to IOCP calls.
Tuple!T* CreateOperation(T...)(T Params) {
	/+HANDLE Handle;
	static if(is(T[0] == socket_t))
		Handle = cast(void*)Params[0];
	else
		Handle = Params[0];
	AsyncIOCallbackDelegate InternalCallback = Params[1];		
	auto State = new Tuple!(T[2..$])(Params[2..$]);		
	NativeReference.AddReference(cast(void*)State);		
	OVERLAPPED* lpOverlap = CreateOverlap(cast(void*)State, cast(HANDLE)Handle, InternalCallback);
	return lpOverlap;+/
	auto State = new Tuple!T(Params);
	NativeReference.AddReference(cast(void*)State);
	return State;
}

/// Unwraps an operation created with CreateOperation, returning state info.
/// Even though CreateOperation does not take a named tuple, giving the tuple argument names is allowed and will work.
Tuple!(T)* UnwrapOperation(T...)(void* QueuedOp) {		
	Tuple!(T)* Params = cast(Tuple!(T)*)QueuedOp;
	NativeReference.RemoveReference(Params);				
	return Params;
}

/// Removes any garbage collected references that are created internally by CreateOperation.
void CancelOperation(void* QueuedOp) {
	NativeReference.RemoveReference(QueuedOp);	
}