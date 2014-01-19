module dap.importers.TextImporter;
import dap.ContentImporter;
import ShardIO.MemoryOutput;
import ShardIO.IOAction;
import ShardTools.ImmediateAction;
import ShardTools.Untyped;
import ShardTools.SignaledTask;

/// An importer that returns any asset as a TextContent instance or string without any processing.
class TextImporter : ContentImporter {
	static this() {
		ContentImporter.register(new TextImporter());
	}

	override bool canProcess(string extension, TypeInfo requestedType) {
		return requestedType == typeid(string) || requestedType == typeid(TextContent);
	}

	override AsyncAction performProcess(ImportContext context) {
		if(context.requestedType == typeid(TextContent))
			return ImmediateAction.success(Untyped(TextContent(context.input)));
		else if(context.requestedType == typeid(string)) {
			auto result = new SignaledTask().Start();
			MemoryOutput output = new MemoryOutput();
			IOAction action = new IOAction(context.input, output);
			action.Start();
			action.NotifyOnComplete(Untyped.init, (state, action, status) {
				if(status == CompletionType.Successful)
					result.SignalComplete(Untyped(cast(string)output.Data));
				else
					result.Abort(action.CompletionData);
			});
			return result;
		} else
			assert(0);
	}
}

/// Provides the output of a TextImporter, allowing streaming access from a text file.
struct TextContent {
	this(InputSource input) {
		this._input = input;
	}

	/// An InputSource containing the raw input for the text file.
	@property InputSource input() {
		return _input;
	}

	private InputSource _input;
}
