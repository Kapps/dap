module dap.ContentProcessor;

class ContentProcessor {
	this() {
		// Constructor code
	}
	
	private __gshared static string[] _processorNames;
	// TODO: Set this to true when a DLL is loaded or unloaded.
	private __gshared static bool _recreateProcessorNames = true;
}

