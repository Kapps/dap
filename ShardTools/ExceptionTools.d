module ShardTools.ExceptionTools;
import std.exception;

string MakeException(string ExceptionName, string ExceptionDetails) {
	//const char[] MakeException = 
	return
		"class " ~ ExceptionName ~ " : Exception {
			public:				
				this(string ExceptionDetails = \"" ~ ExceptionDetails ~ "\", string File = __FILE__, size_t Line = __LINE__) {
					super(ExceptionDetails);
				}
		}";
}

string MakeException(string ExceptionName) {
	//const char[] MakeException = 
	return
		"class " ~ ExceptionName ~ " : Exception {
			public:				
				this(string ExceptionDetails, string File = __FILE__, size_t Line = __LINE__) {
					super(ExceptionDetails);
				}
		}";
}