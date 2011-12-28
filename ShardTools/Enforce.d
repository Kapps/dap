module ShardTools.Enforce;
import ShardTools.ExceptionTools;
import std.conv;
mixin(MakeException("AssertEqualFailedException"));
mixin(MakeException("AssertNotEqualFailedException"));

void EnforceEqual(T, T2)(in T first, in T2 second, string FileName = __FILE__, int LineNum = __LINE__) {
	if(first != second)
		throw new AssertEqualFailedException("Expected " ~ to!string(first) ~ " to equal " ~ to!string(second) ~ " in " ~ FileName ~ "(" ~ to!string(LineNum) ~ ".");
}

void EnforceUnequal(T, T2)(in T first, in T2 second, string FileName = __FILE__, int LineNum = __LINE__) {
	if(first == second)
		throw new AssertNotEqualFailedException("Expected " ~ to!string(first) ~ " to equal " ~ to!string(second) ~ " in " ~ FileName ~ "(" ~ to!string(LineNum) ~ ".");
}