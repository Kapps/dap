/// Provides Derelict dynamic bindings to the bare needed subset of the libpng library.
/// License: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>
/// Authors: Ognjen Ivkovic
/// Copyright: © 2013 Ognjen Ivkovic
module dap.bindings.libpng;
import dap.bindings.utils;

private {
	import derelict.util.loader;
	import derelict.util.system;
	
	static if( Derelict_OS_Windows ) {
		static if( size_t.sizeof == 4 )
			enum libNames = "libpng.dll, libpng32.dll";
		else static if( size_t.sizeof == 8 )
			enum libNames = "libpng.dll, libpng64.dll";
		else
			static assert(0);
	}
	else static if( Derelict_OS_Mac )
		enum libNames = "libpng.dylib";
	else static if( Derelict_OS_Posix )
		enum libNames = "libpng.so";
	else
		static assert(0);
}

enum syms = [
	Sym("uint", "png_access_version_number", ""),
	Sym("int", "png_sig_cmp", "const(byte*), size_t, size_t")
];



/+pragma(msg, getLoaderMixin!(libNames, "Png")(syms));
mixin(getLoaderMixin!(libNames, "Png")(syms));+/

alias png_struct = void*;

