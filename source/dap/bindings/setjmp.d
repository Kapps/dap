/// Provides direct header files for setjmp as they are required for libraries such as libpng or libjpeg.
module dap.bindings.setjmp;

version(OSX) {
	version(X86_64)
		enum _JBLEN = 37;
	else version(X86)
		enum _JBLEN = 18;
	else 
		static assert(0);
} else
	static assert(0);

alias int[_JBLEN] jmp_buf;
// Note that these aren't pointers in C, but in D stack arrays are passed by value.
extern(C) int setjmp(jmp_buf*);
extern(C) void longjmp(jmp_buf*, int);