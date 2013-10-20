module dap.ConsoleLogger;
public import dap.BuildLogger;
import std.stdio;
import std.conv;

/// Provides a basic implementation of BuildLogger that simply logs to the standard output stream.
class ConsoleLogger : BuildLogger {
	protected override void performLog(LoggedMessage message) {
		string result;
		if(message.node !is null)
			result ~= '[' ~ message.node.name ~ "] - ";
		result ~= message.severity.to!string ~ ": " ~ message.details;
		writeln(result);
	}
}

