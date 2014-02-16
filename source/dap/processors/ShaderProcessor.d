module dap.processors.ShaderProcessor;
import dap.ContentProcessor;
import ShardTools.ImmediateAction;
import ShardTools.ExceptionTools;
import dap.GlContext;
import std.conv;
import std.array;
import ShardIO.StreamInput;
import std.traits;

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
	import std.stdio;
	protected override AsyncAction performProcess(Untyped input, OutputSource output) {
		int shader, program;
		string source = input.get!string;
		createProgram(source, shader, program);
		StreamInput stream = new StreamInput(FlushMode.AfterSize(16 * 1024));
		IOAction action = new IOAction(stream, output).Start();
		int uniformCount, attributeCount, blockCount, blockNameLength, attribNameLength;
		GL.GetProgramiv(program, GL_ACTIVE_UNIFORMS, &uniformCount);
		GL.GetProgramiv(program, GL_ACTIVE_ATTRIBUTES, &attributeCount);
		GL.GetProgramiv(program, GL_ACTIVE_UNIFORM_BLOCKS, &blockCount);
		GL.GetProgramiv(program, GL_ACTIVE_UNIFORM_BLOCK_MAX_NAME_LENGTH, &blockNameLength);
		GL.GetProgramiv(program, GL_ACTIVE_ATTRIBUTE_MAX_LENGTH, &attribNameLength);
		stream.Write(cast(byte)attributeCount);
		foreach(i; 0..uniformCount) {
			auto attrib = getAttribute(i, program, blockNameLength, true);
			writeAttribute(stream, attrib);
		}
		stream.Write(cast(byte)uniformCount);
		foreach(i; 0..attributeCount) {
			auto attrib = getAttribute(i, program, attribNameLength, false);
			writeAttribute(stream, attrib);
		}
		stream.WritePrefixed(source);
		stream.Flush();
		return ImmediateAction.success();
	}

	private void writeAttribute(StreamInput stream, ShaderAttribute attrib) {
		stream.WritePrefixed(attrib.name);
		stream.WritePrefixed(attrib.type);
		stream.Write(cast(byte)attrib.modifiers);
	}

	private void createProgram(string source, out int shaderHandle, out int programHandle) {
		if(type == ShaderType.unknown)
			throw new InvalidOperationException("A type must be set for the shader.");
		auto context = ensureContextCreated();
		if(context == GlContext.init)
			throw new GlException("No valid OpenGL context exists to retrieve shader data.");
		uint glType = getGlType();
		if(glType == 0)
			throw new GlException("An invalid shader type was set.");
		uint handle = GL.CreateShader(glType);
		uint program = GL.CreateProgram();
		const char* sourcePtr = source.ptr;
		int sourceLength = cast(int)source.length;
		GL.ShaderSource(handle, 1, &sourcePtr, &sourceLength);
		GL.CompileShader(handle);
		int compileSuccess;
		GL.GetShaderiv(handle, GL_COMPILE_STATUS, &compileSuccess);
		if(compileSuccess != GL_TRUE) {
			int infoLength;
			GL.GetShaderiv(handle, GL_INFO_LOG_LENGTH, &infoLength);
			char[] infoLog = new char[infoLength];
			GL.GetShaderInfoLog(handle, infoLength, &infoLength, infoLog.ptr);
			throw new GlException("Failed to compile the shader:\r\n\t" ~ infoLog.text.replace("\n", "\n\t"));
		}
		GL.AttachShader(program, handle);
		// We intentionally allow glLinkProgram to fail because it expects inputs from other shaders.
		glLinkProgram(program);

		shaderHandle = handle;
		programHandle = program;
	}

	private ShaderAttribute getAttribute(uint index, uint program, int maxNameLength, bool uniform) {
		int length = maxNameLength;
		int size;
		char[] name = new char[length];
		uint attribType;
		if(uniform)
			GL.GetActiveUniform(program, index, maxNameLength, &length, &size, &attribType, name.ptr);
		else
			GL.GetActiveAttrib(program, index, maxNameLength, &length, &size, &attribType, name.ptr);
		name = name[0..length];
		return ShaderAttribute(cast(immutable)name, type.text, uniform ? ShaderModifiers.uniform_ : ShaderModifiers.attribute_);
	}

	private uint getGlType() {
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

	static struct ShaderAttribute {
		const string name;
		const string type;
		const ShaderModifiers modifiers;
		
		this(string name, string type, ShaderModifiers modifiers) {
			this.name = name;
			this.type = type;
			this.modifiers = modifiers;
		}
	}

	private enum ShaderModifiers : byte {
		none_ = 0,
		const_ = 1,
		uniform_ = 2,
		in_ = 4,
		out_ = 8,
		inout_ = in_ | out_,
		attribute_ = in_,
		varying_ = inout_
	}
}