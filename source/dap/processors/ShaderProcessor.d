module dap.processors.ShaderProcessor;
import dap.ContentProcessor;
import ShardTools.ImmediateAction;
import ShardTools.ExceptionTools;
import dap.GlContext;
import std.conv;

enum ShaderType {
	unknown = 0,
	vertex = 1,
	fragment = 2,
	geometry = 4
}

class ShaderProcessor : ContentProcessor {

	mixin(makeProcessorMixin("Shader Processor", ["glsl", "hlsl", "shader", "vsh", "fsh", "glslf", "glslv", "vert", "frag" ]));

	this(Asset asset) {
		super(asset);
	}

	/// Gets or sets the type of this shader.
	@property ShaderType type() const @safe pure nothrow {
		return _type;
	}

	/// ditto
	@property void type(ShaderType type) {
		_type = type;
	}

	@Ignore(true) @property override TypeInfo inputType() {
		return typeid(string);
	}

	protected override AsyncAction performProcess(Untyped input, OutputSource output) {
		string source = input.get!string;
		if(type == ShaderType.unknown)
			return ImmediateAction.failure(new InvalidOperationException("A type must be set for the shader."));
		auto context = ensureContextCreated();
		if(context == GlContext.init)
			return ImmediateAction.failure(new GlException("No valid OpenGL context exists to retrieve shader data."));
		uint glType = getGlType();
		if(glType == 0)
			return ImmediateAction.failure(new GlException("An invalid shader type was set."));
		int handle = enforceSuccess(glCreateShader(glType), "creating the shader");
		int program = enforceSuccess(glCreateProgram(), "creating the program");
		const char* sourcePtr = source.ptr;
		int sourceLength = cast(int)source.length;
		glShaderSource(handle, 1, &sourcePtr, &sourceLength);
		enforceSuccess("setting shader source");
		int compileSuccess;
		glGetShaderiv(handle, GL_COMPILE_STATUS, &compileSuccess);
		enforceSuccess("getting compile status");
		if(compileSuccess != GL_TRUE) {
			int infoLength;
			glGetShaderiv(handle, GL_INFO_LOG_LENGTH, &infoLength);
			enforceSuccess("getting shader info log length");
			infoLength++;
			char[] infoLog = new char[infoLength];
			glGetShaderInfoLog(handle, infoLength, &infoLength, infoLog.ptr);
			enforceSuccess("getting shader info log");
			return ImmediateAction.failure(new GlException("Failed to compile the shader:\r\n\t" ~ infoLog.to!string));
		}
		return ImmediateAction.failure(new Exception("Not yet implemented."));
	}

	uint getGlType() {
		switch(type) {
			case ShaderType.fragment:
				return GL_FRAGMENT_SHADER;
			case ShaderType.vertex:
				return GL_VERTEX_SHADER;
			case ShaderType.geometry:
				return GL_GEOMETRY_SHADER;
			default:
				return 0;
		}
	}

private:
	ShaderType _type = ShaderType.unknown;
}

private int enforceSuccess(int result, string action) {
	if(result != 0) {
		auto error = glGetError();
		if(error != GL_NO_ERROR)
			throw new GlException("GL call for " ~ action ~ " failed with error code " ~ error.text ~ ".");
	}
	return result;
}

private void enforceSuccess(string action) {
	enforceSuccess(-1, action);
}
