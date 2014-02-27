/// Provides access to creating OpenGL contexts with minimal dependencies and without an underlying window.
module dap.GlContext;
import ShardTools.ExceptionTools;
import std.conv;
public import derelict.opengl3.gl3;
import core.stdc.stdlib;
import derelict.opengl3.cgl;
import std.string;
import std.array;
import std.algorithm;
import std.traits;
import derelict.util.exception;

mixin(MakeException("GlException", "An OpenGL error occurred."));

version(OSX) {
	import derelict.opengl3.cgl;
	enum int kCGLPFAOpenGLProfile = 99;
	enum int kCGLOGLPVersion_3_2_Core = 0x3200;
	alias CGLContextObj GlContext;
} else version(Windows) {
	import derelict.opengl3.wgl;
	import core.sys.windows.windows;
	struct GlContext {
		void* hDC;
		void* context;
	}
} else version(linux) {
	import derelict.opengl3.glx;
	import dap.bindings.x11;
	struct GlContext {
		Display* display;
		Window root;
		GLXContext context;
	}
} else {
	static assert(0, "GlContext not yet supported on this platform.");
}

shared static this() {
	try {
		DerelictGL3.load();
		/*forceCreateContext();
		DerelictGL3.reload();*/
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
	} else version(Windows) {
		if(!wglMakeCurrent(context.hDC, context.context))
			throw new GlException("Failed to set the active context.");
	} else version(linux) {
		if(!glXMakeCurrent(context.display, context.root, context.context)) {
			throw new GlException("Failed to set the active context.");
		}
	} else {
		static assert(0, "Setting the active GL context is not implemented on this platform.");
	}
	// We have to reload Derelict after a context is created; do it the first time we create a context.
	reloadDerelictIfNeeded();
	_activeContext = context;
}

/// Creates a new OpenGL context, setting it as the currently active context for this thread.
/// An exception is thrown if an error occurs creating the context and the active context is not changed.
GlContext createContext() {
	_isContextCreated = true;
	if(!_derelictLoaded)
		return GlContext.init;
	forceCreateContext();
	return activeContext;
}

private void reloadDerelictIfNeeded() {
	synchronized {
		if(!_derelictReloaded) {
			try {
				DerelictGL3.reload();
				_derelictReloaded = true;
			} catch (Throwable t) {
				_derelictLoaded = false;
				throw new GlException("Failed to reload Derelict for OpenGL 3 extensions.");
			}
		}
	}
}

version(OSX) {
	import std.stdio;
	private void forceCreateContext() {
		auto obj = createFormat();
		scope(exit)
			CGLDestroyPixelFormat(obj);
		CGLError err = CGLCreateContext(obj, null, &_activeContext);
		if(err != 0)
			throw new GlException("Failed to create the graphics context. Error code " ~ err.text ~ ".");
		activeContext = _activeContext;
	}

	private CGLPixelFormatObj createFormat() {
		CGLPixelFormatAttribute[] format = [
			cast(CGLPixelFormatAttribute)kCGLPFAOpenGLProfile, cast(CGLPixelFormatAttribute)kCGLOGLPVersion_3_2_Core, 
			CGLPixelFormatAttribute.kCGLPFAColorSize, cast(CGLPixelFormatAttribute)24,
			CGLPixelFormatAttribute.kCGLPFAAlphaSize, cast(CGLPixelFormatAttribute)8,
			CGLPixelFormatAttribute.kCGLPFAAccelerated,
			CGLPixelFormatAttribute.kCGLPFADoubleBuffer,
			CGLPixelFormatAttribute.kCGLPFASampleBuffers, cast(CGLPixelFormatAttribute)1,
			CGLPixelFormatAttribute.kCGLPFASamples, cast(CGLPixelFormatAttribute)4,
			cast(CGLPixelFormatAttribute)0];
		int npix;	
		CGLPixelFormatObj obj;
		CGLError err = CGLChoosePixelFormat(format.ptr, &obj, &npix);
		if(err != 0)
			throw new GlException("Failed to decide pixel format. Error code " ~ err.text ~ ".");
		return obj;
	}
} else version(Windows) {
	private void forceCreateContext() {
		auto hWnd = createHiddenWindow();
		// String literals have an implicit null terminator.
		// But wstring does not seem to implicitly convert to wchar* unlike string -> char*.
		auto hDC = GetDC(hWnd);
		PIXELFORMATDESCRIPTOR pfd = {
			PIXELFORMATDESCRIPTOR.sizeof,
			1,
			PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER,
			PFD_TYPE_RGBA,
			32,
			0, 0, 0, 0, 0, 0,
			0,
			0,
			0,
			0, 0, 0, 0,
			24,
			8,
			0,
			PFD_MAIN_PLANE,
			0,
			0, 0, 0
		};
		uint format = ChoosePixelFormat(hDC, &pfd);
		if(format == 0)
			throw new GlException("Unable to find a valid format to create.");
		if(!SetPixelFormat(hDC, format, &pfd))
			throw new GlException("Failed to set pixel format.");
		void* ctx = wglCreateContext(hDC);
		if(ctx is null)
			throw new GlException("Failed to create OpenGL context.");
		GlContext context = { hDC, ctx };
		activeContext = context;
	}

	private HWND createHiddenWindow() {
		enum CLASS_NAME = "dap OpenGL Host";
		WNDCLASS wc;
		auto hInst = GetModuleHandleA(null);
		with(wc) {
			style = CS_OWNDC;
			lpfnWndProc = &hiddenWindowProc;
			lpszClassName = CLASS_NAME;
			hInstance = hInst;
		}
		if(!RegisterClassA(&wc))
			throw new GlException("Unable to register the OpenGL host class.");
		auto result = CreateWindowA(CLASS_NAME, CLASS_NAME, WS_DISABLED, 0, 0, 1, 1, null, null, hInst, null);
		if(!result)
			throw new GlException("Failed to create the OpenGL host window.");
		// TODO: Is it necessary to handle the message pump here?
		// So far seems to be working fine without it.
		return result;
	}

	private static extern(Windows) LRESULT hiddenWindowProc(HWND hWnd, UINT uMsg, WPARAM wParam, LPARAM lParam) nothrow {
		switch(uMsg) {
			case WM_CREATE:
				// TODO: Should we do something here?
				break;
			default:
				break;
		}
		return DefWindowProcA(hWnd, uMsg, wParam, lParam);
	}
} else version(linux) {
	private void forceCreateContext() {
		Display* display = XOpenDisplay(null);
		if(display is null)
			throw new GlException("Unable to open the display to create an OpenGL context.");
		Window root = DefaultRootWindow(display);
		GLint[] attribs = [ GLX_RGBA, GLX_DEPTH_SIZE, 24, GLX_NONE ];
		XVisualInfo* vi = glXChooseVisual(display, 0, attribs.ptr);
		if(vi is null)
			throw new GlException("Unable to select visual info for creating an OpenGL context.");
		GLXContext ctx = glXCreateContext(display, vi, null, cast(int)GL_TRUE);
		if(ctx is null)
			throw new GlException("Failed to create OpenGL context.");
		GlContext context = { display, root, ctx };
		activeContext = context;
	}
} else {
	static assert(0, "Creating a GL Context is not yet supported on this platform.");
}

/// Provides a static struct with opDispatch for easier handling of OpenGL calls.
/// Calls can optionally be logged by using --version=debugGL and all results will be checked with glGetError.
/// Any errors will result in an exception being thrown, with the message containing the call and the arguments.
/// A call that attempts to invoke an extension that is not loaded will be detected and an exception thrown.
static struct GL {
	/// Implements opDispatch to implement checked GL calls.
	static auto opDispatch(string method, string file = __FILE__, int line = __LINE__, T...)(T args) {
		auto dg = mixin("gl" ~ method);
		if(!dg)
			throw new GlException("Attempted to invoke extension 'gl" ~ method ~ "' which was not loaded.");
		static if(is(ReturnType!dg == void)) {
			dg(args);
			enforceSuccess!(file, line)(method, args);
		} else {
			auto result = dg(args);
			enforceSuccess!(file, line)(method, args);
			return result;
		}
	}

	private static void enforceSuccess(string file = __FILE__, int line = __LINE__, T...)(string action, T args) {
		auto error = glGetError();
		if(error != GL_NO_ERROR) {
			string msg = "GL call for " ~ action ~ " failed with error code " ~ error.text ~ ". Args: [";
			foreach(arg; args)
				msg ~= arg.text.replace("\"", "\\\"");
			msg ~= "]";
			throw new GlException(msg, file, line);
		}
	}
}

/// Ensures an active context is created for this thread, returning the context.
/// If the context fails to be created or has failed previously, init is returned.
GlContext ensureContextCreated() {
	if(_isContextCreated)
		return _activeContext;
	try createContext();
	catch(GlException) {
		_activeContext = GlContext.init;
	}
	return _activeContext;
}

private __gshared bool _derelictLoaded;
private __gshared bool _derelictReloaded;
// TODO: Needs to actually handle multi-threading properly.
// Create a single context and switch the active context to it inside a lock for each thread?
// Maybe an acquireContext and releaseContext method.
private GlContext _activeContext;
private bool _isContextCreated;