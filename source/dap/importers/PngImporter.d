module dap.importers.PngImporter;
import dap.bindings.libpng;
import dap.ContentImporter;
import dap.TextureContent;
import ShardTools.AsyncAction;
import ShardTools.AsyncRange;
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
import ShardTools.Buffer;
import ShardTools.BufferPool;
import core.stdc.string;
import ShardTools.ImmediateAction;
import core.atomic;
import vibe.core.stream;
import dap.StreamOps;
import std.algorithm;
import std.container;

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
	
	override Untyped performProcess(ImportContext context) {
		if(libraryLoadFailed)
			throw libraryLoadFailException;
		auto readContext = createReadContext(context);
		scope(exit)
			png_destroy_read_struct(&readContext.pngp, &readContext.infop, null);
		// Horrible hack. We don't care about libpngs insistence of versions; everything used is from libpng 1.2.
		// So, we'll go ahead and try from 1.2.0 to 1.9.0 until we get a version that works.
		// Incredibly stupid that libpng essentially prevents dynamic linking if you want to redistribute your binaries.
		immutable(char*)[] attemptedVersions = [ "1.2.0", "1.4.0", "1.5.0", "1.6.0", "1.7.0", "1.8.0", "1.9.0" ];
		png_structp pngp;
		foreach(ver; attemptedVersions) {
			pngp = png_create_read_struct(ver, readContext, &errorCallback, &warnCallback);
			if(pngp || !readContext.hadVersionMismatch)
				break;
		}
		readContext.pngp = pngp;
		if(!pngp)
			throw new Exception("Failed to create PNG read struct.");
		auto infop = png_create_info_struct(readContext.pngp);
		readContext.infop = infop;
		if(!infop)
			throw new Exception("Failed to create PNG info struct.");
		png_set_progressive_read_fn(pngp, readContext, &infoCallback, &rowCallback, &endCallback);
		// Initially we have to provide enough data to reach our info callback, as we produce data through the AsyncRange which is started later.
		while(!readContext.infoRead) {
			auto size = context.input.leastSize;
			Buffer buff = BufferPool.Global.Acquire(size);
			context.input.read(buff.FullData[0..size]);
			png_process_data(pngp, infop, buff.FullData.ptr, size);
		}
		return Untyped(readContext.content);
	}
	
	private ReadContext* createReadContext(ImportContext context) {
		auto readContext = new ReadContext();	
		readContext.importer = this;
		readContext.importContext = context;
		return readContext;
	}
	
	private void produceData(Untyped state, ProducerCompletionCallback callback) {
		ReadContext* context = state.get!(ReadContext*);
		auto pngp = context.pngp;
		auto infop = context.infop;
		// Continuously read from the InputStream until we get enough data for a row.
		Color[] rowData;
		if(context.buffers.empty) {
			InputStream input = context.importContext.input;
			if(input.empty) {
				if(!context.finishedRead)
					throw new ContentImportException("The InputStream ended prior to reading a full PNG.");
				callback(ProducerStatus.complete, null);
				return;
			}
			auto size = input.leastSize;
			Buffer buffer = BufferPool.Global.Acquire(size);
			input.read(buffer.FullData[0..size]);
			png_process_data(pngp, infop, buffer.FullData.ptr, size);
			BufferPool.Global.Release(buffer);
		}
		rowData = context.buffers.front;
		context.buffers.removeFront();
		// We now have a buffer, so can use its data. This may be a buffer previous to this call as well.
		// After that, we wait until more data is requested by this being called again.
		callback(ProducerStatus.more, rowData);
	}
}

private struct ReadContext {
	// House-keeping:
	PngImporter importer;
	ImportContext importContext;
	png_structp pngp;
	png_infop infop;
	bool hadVersionMismatch;
	// For producing data:
	ProducerCompletionCallback producerCallback;
	DList!(Color[]) buffers; // Guaranteed to be rowSize bytes each.
	bool infoRead; // Read the info header.
	bool finishedRead; // Set when end callback is done.
	TextureContent content; // Set when infoRead is true.
	// Image info
	int numPasses;
	size_t rowSize;
	uint width;
	uint height;
}

// C callback functions below:

extern(C) private void errorCallback(png_structp pngp, const char* msg) {
	ReadContext* readContext = cast(ReadContext*)png_get_error_ptr(pngp);
	Asset asset = readContext.importContext.asset;
	BuildContext buildContext = readContext.importContext.buildContext;
	asset.warn("An error occurred in the raw content file: " ~ msg.text);
	//buildContext.logger.error("libpng error: " ~ msg.text, asset);
	throw new ContentImportException("libpng error: " ~ msg.text);
}

extern(C) private void warnCallback(png_structp pngp, const char* msg) {
	ReadContext* readContext = cast(ReadContext*)png_get_error_ptr(pngp);
	Asset asset = readContext.importContext.asset;
	BuildContext buildContext = readContext.importContext.buildContext;
	string mtext = msg.text;
	// Also a horrible hack, but the only versions we can verify work are the ones where this is true.
	readContext.hadVersionMismatch = mtext.canFind("but running with");
	if(!readContext.hadVersionMismatch)
		buildContext.logger.warn("libpng warning: " ~ mtext, asset);
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
	readContext.infoRead = true;
	readContext.importContext.asset.trace(format("Image is %dx%d and has %d pixels per row with %d passes.", readContext.width, readContext.height, readContext.rowSize, readContext.numPasses));
	readContext.content = new TextureContent(readContext.width, readContext.height, Untyped(readContext), &readContext.importer.produceData);
}

extern(C) private void rowCallback(png_structp pngp, void* row, uint rowNum, int pass) {
	ReadContext* readContext = cast(ReadContext*)png_get_progressive_ptr(pngp);
	size_t bytes = readContext.rowSize;
	Color[] elements = cast(Color[])row[0..bytes].dup;
	readContext.buffers.insertBack(elements);
}

extern(C) private void endCallback(png_structp pngp, png_infop infop) {
	ReadContext* readContext = cast(ReadContext*)png_get_progressive_ptr(pngp);
	readContext.finishedRead = true;
}