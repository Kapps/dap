/// Provides Derelict dynamic bindings to the bare needed subset of the libpng library.
/// License: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>
/// Authors: Ognjen Ivkovic
/// Copyright: © 2013 Ognjen Ivkovic
module dap.bindings.libpng;
import dap.bindings.utils;
public import dap.bindings.setjmp;
import std.stdio;

private {
	import derelict.util.loader;
	import derelict.util.system;
	
	static if( Derelict_OS_Windows ) 
		enum libNames = "libpng.dll, libpng15.dll, libpng3.dll, libpng15-15.dll";
	else static if( Derelict_OS_Mac )
		enum libNames = "libpng.dylib";
	else static if( Derelict_OS_Posix )
		enum libNames = "libpng.12.so, libpng.so, libpng3.so";
	else
		static assert(0);
}

enum syms = [
	Sym("uint", "png_access_version_number", ""),
	Sym("int", "png_sig_cmp", "const(ubyte*), size_t, size_t"),
	Sym("void", "png_set_sig_bytes", "png_structp, int"),
	Sym("void*", "png_get_progressive_ptr", "png_structp"),
	Sym("void*", "png_get_error_ptr", "png_structp"),
	Sym("uint", "png_get_image_width", "png_structp, png_infop"),
	Sym("uint", "png_get_image_height", "png_structp, png_infop"),
	Sym("png_structp", "png_create_read_struct", "immutable char*, void*, png_error_ptr, png_error_ptr"),
	Sym("png_infop", "png_create_info_struct", "png_structp"),
	Sym("void", "png_destroy_read_struct", "png_structpp, png_infopp, png_infopp"),
	//Sym("jmp_buf*", "png_set_longjmp_fn", "png_structrp, jump_ptr, size_t"),
	Sym("void", "png_set_progressive_read_fn", "png_structp, void*, png_progressive_info_ptr, png_progressive_row_ptr, png_progressive_end_ptr"),
	Sym("void", "png_process_data", "png_structrp, png_inforp, void*, size_t"),
	Sym("void", "png_read_info", "png_structp, png_infop"),
	Sym("void", "png_set_read_fn", "png_structp, void*, png_rw_ptr"),
	Sym("void*", "png_get_io_ptr", "png_structrp"),
	Sym("int", "png_set_interlace_handling", "png_structp"),
	Sym("void", "png_read_update_info", "png_structp, png_infop"),
	Sym("uint", "png_get_rowbytes", "png_structp, png_infop"),
	Sym("ubyte", "png_get_color_type", "png_structp, png_infop"),
	Sym("void", "png_set_filler", "png_structp, uint, int"),
	Sym("void", "png_read_row", "png_structp, void*, void*")
	//Sym("")
];

jmp_buf* png_jmpbuf(png_structrp pngrp) {
	//return png_set_longjmp_fn(pngrp, &longjmp, jmp_buf.sizeof);
	return null;
}

//pragma(msg, getLoaderMixin!(libNames, "Png")(syms));
mixin(getLoaderMixin!(libNames, "Png")(syms));

enum string PNG_LIBPNG_VER_STRING = "1.2.44";
enum int PNG_FILLER_AFTER = 1;


alias void* png_structp;
alias png_structp* png_structpp;
alias png_structp png_structrp;
alias void* png_infop;
alias png_infop* png_infopp;
alias png_infop png_inforp;
alias extern(C) void function(png_structp, const char*) png_error_ptr;
alias extern(C) void function(png_structp, png_infop) png_progressive_info_ptr;
alias extern(C) void function(png_structp, void*, uint, int) png_progressive_row_ptr;
alias extern(C) void function(png_structp, png_infop) png_progressive_end_ptr;
alias extern(C) void function(png_structp, void*, size_t) png_rw_ptr;
alias extern(C) void function(jmp_buf*, int) jump_ptr;