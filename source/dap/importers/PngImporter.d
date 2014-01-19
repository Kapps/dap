module dap.importers.PngImporter;
import dap.bindings.libpng;
import dap.ContentImporter;
import dap.TextureContent;
import ShardIO.InputSource;
import ShardTools.AsyncAction;
import ShardTools.AsyncRange;
import ShardIO.AsyncFile;
import ShardIO.StreamOutput;
import ShardTools.ExceptionTools;
import ShardTools.SignaledTask;
import std.exception;
import dap.BuildContext;
import core.thread;
import core.stdc.stdlib;
import core.sync.mutex;
import core.memory;
import ShardTools.Untyped;
import std.string;
import std.conv;
import std.stdio;
import ShardTools.Queue;
import ShardTools.Buffer;
import ShardTools.BufferPool;
import core.stdc.string;
import ShardTools.ImmediateAction;

class PngImporter : ContentImporter {

	private enum HEADER_SIZE = 8;
	private enum MAX_BUFFER_SIZE = 256 * 1024;
	// If we fail to load libpng don't prevent the entire program from being used.
	// Instead just fail to build any png files.
	private __gshared bool libraryLoadFailed = false;
	private __gshared Exception libraryLoadFailException;

	shared static this() {
		try 
			DerelictPng.load();
		catch (Exception ex) {
			libraryLoadFailed = true;
			libraryLoadFailException = ex;
		}
		ContentImporter.register(new PngImporter());
	}

	override bool canProcess(string extension, TypeInfo requestedType) {
		return extension == "png" && requestedType == typeid(TextureContent);
	}

	override AsyncAction performProcess(ImportContext context) {
		if(libraryLoadFailed)
			return ImmediateAction.failure(Untyped(libraryLoadFailException));
		auto readContext = createReadContext(context);
		auto pngp = png_create_read_struct(toStringz(PNG_LIBPNG_VER_STRING), readContext, &errorCallback, &errorCallback);
		readContext.pngp = pngp;
		if(!pngp) {
			writeln("failed to create pngp.");
			throw new Exception("Failed to create PNG read struct.");
		}
		auto infop = png_create_info_struct(readContext.pngp);
		readContext.infop = infop;
		if(!infop) {
			png_destroy_read_struct(&pngp, null, null);
			throw new Exception("Failed to create PNG info struct.");
		}
		png_set_progressive_read_fn(pngp, readContext, &infoCallback, &rowCallback, &endCallback);
		return readContext.importTask;
	}

	private ReadContext* createReadContext(ImportContext context) {
		auto readContext = new ReadContext();
		auto streamOutput = new StreamOutput(Untyped(readContext), &streamedOutputReceived);
		readContext.importer = this;
		readContext.mutex = new Mutex();
		readContext.importTask = new SignaledTask().Start();
		readContext.importContext = context;
		readContext.streamAction = new IOAction(context.input, streamOutput);
		readContext.streamAction.Start();
		readContext.streamAction.NotifyOnComplete(Untyped(readContext), &onStreamComplete);
		readContext.producedBuffers = new Queue!(Color[])();
		return readContext;
	}

	private void onStreamComplete(Untyped state, AsyncAction action, CompletionType status) {
		// We clean up when the stream action is complete, as that's what we feed libpng data with.
		auto context = state.get!(ReadContext*)();
		synchronized(context.mutex) {
			// Since the stream action completes after, it finishing means the importTask should be finished.
			// If not, there was an error so abort.
			writeln("Stream is complete. Import task status is ", context.importTask.Status, ".");
			if(context.importTask.Status == CompletionType.Incomplete)
				context.importTask.Abort(action.CompletionData);
			// Also make sure to delete the structs since they're not GC collected.
			if(context.pngp && context.infop)
				png_destroy_read_struct(&context.pngp, &context.infop, null);
		}
	}

	private void produceData(Untyped state, ProducerCompletionCallback callback) {
		ReadContext* context = state.get!(ReadContext*);
		auto pngp = context.pngp;
		auto infop = context.infop;
		synchronized(context.mutex) {
			Color[] elements;
			if(context.producedBuffers.TryDequeue(elements)) {
				// When we are requested to produce data, check if we already have some buffered.
				// If so, just invoke callback with one of the buffers.
				// Each buffer contains a single row.
				// May be worth checking if combining multiple buffers together is worthwhile.
				writeln("Using existing buffer.");
				callback(ProducerStatus.more, elements);
			} else {
				// Otherwise consume when we produce the next buffer.
				writeln("Waiting for new buffer.");
				context.producerCallback = callback;
				context.canConsume = true;
				writeln(context.canConsume);
			}

			// Finally if we have less than half the amount of bytes buffered as we want, get more data.
			if(context.waitingForConsume && context.producedBuffers.Count * context.rowSize < MAX_BUFFER_SIZE) {
				writeln("Consumed enough to stop waiting.");
				StreamOutput stream = cast(StreamOutput)context.streamAction.Output;
				stream.notifyDataReady();
			}
		}
	}

	private DataRequestFlags streamedOutputReceived(Untyped state, scope StreamReader reader) {
		ReadContext* context = state.get!(ReadContext*);
		auto pngp = context.pngp;
		auto infop = context.infop;
		synchronized(context.mutex) {
			// libpng uses setjmp to take us back to this statement when an error occurs.
			// But we'd need to be above it on the stack, so we have to do this before each read.
			int jmpCode = setjmp(png_jmpbuf(pngp));
			if(jmpCode) {
				// TODO: This would cause this task to be aborted from callbacks, then return Complete.
				// Which would potentially trigger another Complete. Make sure there's no bugs there.
				context.streamAction.Abort(Untyped(new Exception("An error occurred while reading the png.")));
				return DataRequestFlags.Complete;
			}
			// The actual data we just pass directly to libpng.
			// It will invoke errorCallback / infoCallback / endCallback / rowCallback during this call.
			// If any of them fail, it will jump back to our setjmp above.
			auto streamBytes = reader.ReadArray!ubyte(reader.Available);
			writeln("Processing ", streamBytes.length, " bytes.");
			png_process_data(pngp, infop, streamBytes.ptr, streamBytes.length);
			if(context.readComplete) // End info called means we're done.
				return DataRequestFlags.Complete;
			if(context.producedBuffers.Count * context.rowSize >= MAX_BUFFER_SIZE) {
				writeln("Too much buffered, waiting.");
				return DataRequestFlags.Waiting | DataRequestFlags.Continue;
			}
			return DataRequestFlags.Continue;
		}
	}
}

private struct ReadContext {
	// House-keeping:
	PngImporter importer;
	Mutex mutex;
	SignaledTask importTask;
	ImportContext importContext;
	png_structp pngp;
	png_infop infop;
	IOAction streamAction;
	bool readComplete;
	// For producing data:
	ProducerCompletionCallback producerCallback;
	bool canConsume;
	Queue!(Color[]) producedBuffers; // Each buffer is guaranteed to be rowSize bytes (aka rowSize / Color.sizeof elements).
	bool waitingForConsume; // If we're reading too much faster than we can consume, stop reading until ready.
	// Then just some misc info for performing the read.
	bool signatureVerified;
	int numPasses;
	size_t rowSize;
	uint width;
	uint height;
}

// C callback functions below:

extern(C) private void errorCallback(png_structp pngp, const char* msg) {
	writeln("errorCallback");
	ReadContext* readContext = cast(ReadContext*)png_get_error_ptr(pngp);
	Asset asset = readContext.importContext.asset;
	BuildContext buildContext = readContext.importContext.buildContext;
	buildContext.logger.error("An error occurred while attempting to read the raw png file: " ~ msg.text, asset);
}

extern(C) private void infoCallback(png_structp pngp, png_infop infop) {
	ReadContext* readContext = cast(ReadContext*)png_get_progressive_ptr(pngp);
	// TODO: Actually handle colors properly. Make sure gray in particular works as 4 bytes.
	// And don't set a filler if it's already in RGBA.
	png_set_filler(pngp, 0xFF, PNG_FILLER_AFTER);
	png_read_update_info(pngp, infop);
	readContext.width = png_get_image_width(pngp, infop);
	readContext.height = png_get_image_height(pngp, infop);
	readContext.rowSize = png_get_rowbytes(pngp, infop);
	readContext.numPasses = png_set_interlace_handling(pngp);
	std.stdio.writeln("Image size was ", readContext.width, "x", readContext.height, ".");
	std.stdio.writefln("Number of passes is %d and row size is %d.", readContext.numPasses, readContext.rowSize);
	auto content = new TextureContent(readContext.width, readContext.height, Untyped(readContext), &readContext.importer.produceData);
	readContext.importTask.SignalComplete(Untyped(content));
}

extern(C) private void rowCallback(png_structp pngp, void* row, uint rowNum, int pass) {
	// TODO: Find a way to do this with minimal or no copying.
	// Should be possible, just more difficult.
	ReadContext* readContext = cast(ReadContext*)png_get_progressive_ptr(pngp);
	auto infop = readContext.infop;
	size_t bytes = readContext.rowSize;
	std.stdio.writeln("Got row callback with row ", rowNum, ", and pass ", pass, ". Bytes was ", bytes, ".");
	Color[] elements = cast(Color[])row[0..bytes];
	synchronized(readContext.mutex) {
		if(readContext.canConsume) {
			// We're waiting for data to be produced, so we can immediately invoke the callback with this data.
			writeln("Consuming immediately.");
			readContext.canConsume = false; // Must be before callback, as that can be what sets it to true.
			readContext.producerCallback(ProducerStatus.more, elements);
		} else {
			// Otherwise we have to buffer this row.
			writeln("Enqueueing");
			readContext.producedBuffers.Enqueue(elements);
		}
	}
}

extern(C) private void endCallback(png_structp pngp, png_infop infop) {
	writeln("endCallback");
	ReadContext* readContext = cast(ReadContext*)png_get_progressive_ptr(pngp);
	std.stdio.writeln("Got to end callback!");
	readContext.readComplete = true;
}