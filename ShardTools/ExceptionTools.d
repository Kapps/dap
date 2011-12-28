module ShardTools.ExceptionTools;
import std.exception;

string MakeException(string ExceptionName, string ExceptionDetails) {
	//const char[] MakeException = 
	return
		"class " ~ ExceptionName ~ " : Exception {
			public:
				this() {
					super(\"" ~ ExceptionDetails ~ "\");
				}
			
				this(string ExceptionDetails) {
					super(ExceptionDetails);
				}
		}";
}

string MakeException(string ExceptionName) {
	//const char[] MakeException = 
	return
		"class " ~ ExceptionName ~ " : Exception {
			public:				
				this(string ExceptionDetails) {
					super(ExceptionDetails);
				}
		}";
}