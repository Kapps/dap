module dap.BuildLogger;
public import dap.HierarchyNode;
import ShardTools.Event;

enum MessageSeverity {
	Trace = 1,
	Info = 2,
	Warning = 4,
	Error = 8,
	Critical = 16
}

struct LoggedMessage {
	MessageSeverity severity;
	string details;
	HierarchyNode node;
}

alias Event!(void, LoggedMessage) BuildMessageEvent;

/// Provides a logging mechanism for messages received during a build.
class BuildLogger {	

	this() {
		_messageLogged = new BuildMessageEvent();
	}

	/// Gets an event that's called when a message is received and logged.
	@property BuildMessageEvent messageLogged() {
		return _messageLogged;
	}

	/// Gets or sets the minimum severity that a message must have before it's actually logged.
	@property MessageSeverity minSeverity() {
		return _minSeverity;
	}

	/// ditto
	@property void minSeverity(MessageSeverity severity) {
		this._minSeverity = severity;
	}
	
	/// Logs the given message with the specified severity and details.
	/// If node is not null, the message is associated with the specified HierarchyNode. This is optional however.
	void logMessage(MessageSeverity severity, string details, HierarchyNode node = null) {
		if(cast(int)severity < cast(int)minSeverity)
			return;
		LoggedMessage message;
		message.severity = severity;
		message.details = details;
		message.node = node;
		performLog(message);
		messageLogged.Execute(message);
	}

	/// A shortcut to log a message with the Trace severity.
	final void trace(string details, HierarchyNode node = null) {
		logMessage(MessageSeverity.Trace, details, node);
	}

	/// A shortcut to log a message with the Info severity.
	final void info(string details, HierarchyNode node = null) {
		logMessage(MessageSeverity.Info, details, node);
	}

	/// A shortcut to log a message with the Warning severity.
	final void warn(string details, HierarchyNode node = null) {
		logMessage(MessageSeverity.Warning, details, node);
	}

	/// A shortcut to log a message with the Error severity.
	final void error(string details, HierarchyNode node = null) {
		logMessage(MessageSeverity.Error, details, node);
	}
	
	/// Handles the actual logging of the specified message.
	protected abstract void performLog(LoggedMessage message);
	
	BuildMessageEvent _messageLogged;
	MessageSeverity _minSeverity = MessageSeverity.Warning;
}

