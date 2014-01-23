module dap.bindings.cgl;

version(OSX) {
	enum int kCGLPFAOpenGLProfile = 99;
	enum int kCGLOGLPVersion_3_2_Core = 0x3200;
	
	alias int CGLPixelFormatAttribute;
	alias uint CGLError;
	alias void* CGLPixelFormatObj;
	alias void* CGLContextObj;
	
	extern(C) CGLError CGLCreateContext(CGLPixelFormatObj pix, CGLContextObj share, CGLContextObj *ctx);
	extern(C) CGLError CGLChoosePixelFormat(CGLPixelFormatAttribute *attribs, CGLPixelFormatObj *pix, int *npix);
	extern(C) CGLError CGLDestroyPixelFormat(CGLPixelFormatObj pix);
	extern(C) CGLContextObj CGLGetCurrentContext();
	extern(C) CGLError CGLSetCurrentContext(CGLContextObj obj);
	extern(C) void CGLGetVersion(int *major, int *minor);
} 