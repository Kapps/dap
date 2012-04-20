module ShardTools.ExceptionTools;
import std.exception;

mixin(MakeException("InvalidOperationException", "The performed operation was considered invalid for the present state."));
mixin(MakeException("NotSupportedException", "The operation being performed was not supported."));

string MakeException(string ExceptionName, string ExceptionDetails) {
	//const char[] MakeException = 
	return
		"public class " ~ ExceptionName ~ " : Exception {
			public:				
				this(string ExceptionDetails = \"" ~ ExceptionDetails ~ "\", string File = __FILE__, size_t Line = __LINE__) {
					super(ExceptionDetails);
				}
		}";
}

string MakeException(string ExceptionName) {
	//const char[] MakeException = 
	return
		"public class " ~ ExceptionName ~ " : Exception {
			public:				
				this(string ExceptionDetails, string File = __FILE__, size_t Line = __LINE__) {
					super(ExceptionDetails);
				}
		}";
}