/// Extremely minimal static bindings for X11.
/// Includes only functions required to create a windowless OpenGL context.
/// Most structs are not defined and instead are replaced with void* where possible.
/// This module depends on libx11-dev for linking. In the future this may be updated to use Derelict instead and load at runtime.
module dap.bindings.x11;

import dap.bindings.utils;

version(linux) {
	// TODO: Should XID be ulong?
	public import derelict.util.xtypes;
	extern(C) void* XOpenDisplay(void*);
	extern(C) Window XDefaultRootWindow(void*);
	alias XDefaultRootWindow DefaultRootWindow;
}
