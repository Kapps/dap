/// Provides access to creating OpenGL contexts with minimal dependencies and without an underlying window.
module dap.GlContext;
import ShardTools.ExceptionTools;
import std.conv;
public import derelict.opengl3.gl3;
import core.stdc.stdlib;
import std.stdio;

mixin(MakeException("GlException", "An OpenGL error occurred."));

version(OSX) {
	import dap.bindings.cgl;
	alias CGLContextObj GlContext;
} else {
	static assert(0, "GlContext not yet supported on this platform.");
}

shared static this() {
	try {
		DerelictGL3.load();
		_derelictLoaded = true;
	} catch {
		_derelictLoaded = false;
	}
}

/// Indicates whether a context has attempted to be created for this thread.
@property bool isContextCreated() nothrow {
	return _isContextCreated;
}

/// Gets the context that is currently active, or GlContext.init for no active context.
/// This value is thread-local.
@property GlContext activeContext() nothrow {
	return _activeContext;
}

/// Indicates if the OpenGL library was successfully loaded.
@property bool libraryLoaded() nothrow {
	return _derelictLoaded;
}

/// Assigns the given context as the currently active context.
/// An exception is thrown upon failure.
@property void activeContext(GlContext context) {
	version(OSX) {
		auto err = CGLSetCurrentContext(context);
		if(err != 0)
			throw new GlException("Failed to set the active context. Error code " ~ err.text ~ ".");
		_activeContext = context;
	}
	_activeContext = context;
}

/// Creates a new OpenGL context, setting it as the currently active context for this thread.
/// An exception is thrown if an error occurs creating the context and the active context is not changed.
GlContext createContext() {
	version(OSX) {
		_isContextCreated = true;
		//if(!_derelictLoaded)
		//	return GlContext.init;
		int major, minor;
		writeln("Addresses: ", [cast(void*)&CGLGetVersion, cast(void*)&CGLCreateContext, cast(void*)&CGLChoosePixelFormat, cast(void*)&CGLDestroyPixelFormat, cast(void*)&CGLGetCurrentContext, cast(void*)&CGLSetCurrentContext]);
		writeln("Get Version address: ", &CGLGetVersion);
		CGLGetVersion(&major, &minor);
		writefln("Version is %d.%d.");
		CGLError err;
		auto obj = createFormat();
		scope(exit)
			CGLDestroyPixelFormat(obj);
		err = CGLCreateContext(obj, null, &_activeContext);
		if(err != 0)
			throw new GlException("Failed to create the graphics context. Error code " ~ err.text ~ ".");
		activeContext = _activeContext;
	} else {
		static assert(0, "Creating a GL Context is not yet supported on this platform.");
	}
	return activeContext;
}

private CGLPixelFormatObj createFormat() {
	writeln("a");
	CGLPixelFormatAttribute[] format = [kCGLPFAOpenGLProfile, kCGLOGLPVersion_3_2_Core, 0];
	writeln("b");
	int npix;	
	CGLPixelFormatObj obj;
	writeln("Address is ", &CGLChoosePixelFormat);
	CGLError err = CGLChoosePixelFormat(format.ptr, &obj, &npix);
	writeln("after");
	return obj;
	//if(err != 0)
	//	throw new GlException("Failed to decide pixel format. Error code " ~ err.text ~ ".");
}

/// Ensures an active context is created for this thread, returning the context.
/// If the context fails to be created or has failed previously, init is returned.
GlContext ensureContextCreated() {
	if(_isContextCreated)
		return _activeContext;
	try createContext();
	catch(GlException) { }
	return _activeContext;
}

__gshared bool _derelictLoaded;
private GlContext _activeContext;
private bool _isContextCreated;