module dap.importers.JpegImporter;

public import dap.ContentImporter;
import dap.TextureContent;
import ShardTools.AsyncRange;
import dap.bindings.libjpeg;
import ShardTools.Buffer;
import ShardTools.BufferPool;
import core.stdc.stdlib;
import core.stdc.string;
import core.memory;
import std.conv;

import std.stdio;
import std.algorithm;

class JpegImporter : ContentImporter {

	private __gshared bool libraryLoadFailed = false;
	private __gshared Exception libraryLoadFailException;
	
	shared static this() {
		try 
			DerelictJpeg.load();
		catch (Exception ex) {
			libraryLoadFailed = true;
			libraryLoadFailException = ex;
		}
		ContentImporter.register(new JpegImporter());
	}

	private static struct SourceManager {
		jpeg_source_mgr jsrc; // Must remain at offset 0.
		ImportContext context;
		Buffer currentBuffer; // Current buffer containing input data to handle.
		Buffer outputBuffer; // Stores the rows from read_scandata.
		size_t rowSize; // Number of bytes per row.
		Color[] colorBuffer; // Converted colours from outputBuffer.
	}

	private struct ErrorManager {
		jpeg_error_mgr jmgr; // Must remain at offset 0.
		ImportContext context;
	}

	// JPEG Source Manager callbacks:
	private static extern(C) void initSource(jpeg_decompress_struct* ds) {
		writeln("Inside initSource.");
	}

	private static extern(C) void termSource(jpeg_decompress_struct* ds) {
		writeln("In termSource.");
		SourceManager* man = cast(SourceManager*)ds.src;
		writeln("Called termSource. Current buffer is ", man.currentBuffer, ".");
		if(man.currentBuffer)
			BufferPool.Global.Release(man.currentBuffer);
	}

	private static extern(C) int fillBuffer(jpeg_decompress_struct* jd) {
		writeln("In fillBuffer");
		SourceManager* man = cast(SourceManager*)jd.src;
		auto src = &man.jsrc;
		auto input = man.context.input;
		if(man.currentBuffer)
			BufferPool.Global.Release(man.currentBuffer);
		auto size = min(64 * 1024, cast(size_t)input.leastSize);
		if(size == 0)
			return false;
		auto buffer = BufferPool.Global.Acquire(size);
		man.currentBuffer = buffer;
		input.read(buffer.FullData[0..size]);
		src.next_input_byte = buffer.FullData.ptr;
		src.bytes_in_buffer = size;
		return true;
	}

	private static extern(C) void skipBytes(jpeg_decompress_struct* jd, int count) {
		writeln("Skipping ", count, " bytes.");
		SourceManager* man = cast(SourceManager*)jd.src;
		auto src = &man.jsrc;
		long bytesRemaining = count;
		while(bytesRemaining > 0) {
			if(src.bytes_in_buffer > bytesRemaining) {
				writeln("Current buffer had enough bytes to skip.");
				src.bytes_in_buffer -= count;
				src.next_input_byte += count;
				break;
			} else {
				writeln("Subtracting current bytes and filling new.");
				bytesRemaining -= src.bytes_in_buffer;
				fillBuffer(jd);
			}
		}
	}

	// JPEG Error Manager callbacks:
	private static extern(C) void handleError(j_common_ptr cinfo) {
		writeln("Inside handleError.");
		auto err = cast(ErrorManager*)cinfo.err;
		err.jmgr.output_message(cinfo);
		throw new ContentImportException("The JPEG file was in an incorrect format or corrupt.");
	}

	private static extern(C) void handleMessage(j_common_ptr cinfo) {
		writeln("Inside handleMessage");
		auto err = cast(ErrorManager*)cinfo.err;
		char[jpeg_error_mgr.JMSG_LENGTH_MAX] buffer;
		err.jmgr.format_message(cinfo, buffer.ptr);
		writeln("Message was ", buffer.text, ".");
		err.context.asset.info(buffer.text);
	}

	// ContentImporter methods:

	private T* alloc(T)() {
		/+auto result = cast(T*)malloc(T.sizeof);
		memset(result, 0, T.sizeof);
		GC.addRoot(result);
		return result;+/
		return new T();
	}

	override bool canProcess(string extension, TypeInfo requestedType) {
		return requestedType == typeid(TextureContent) && (extension == "jpeg" || extension == "jpg");
	}

	override Untyped performProcess(ImportContext context) {
		if(libraryLoadFailed)
			throw libraryLoadFailException;
		// Initialize error handling.
		ErrorManager* errmgr = alloc!ErrorManager;
		jpeg_decompress_struct* ds = alloc!jpeg_decompress_struct;
		ds.err = jpeg_std_error(&errmgr.jmgr);
		errmgr.jmgr.error_exit = &handleError;
		errmgr.jmgr.output_message = &handleMessage;
		errmgr.context = context;
		jpeg_create_decompress(ds);
		// TODO: IMPORTANT: Make sure this gets freed after this asset is done building (successful or not).
		// Also free the allocated stuff we have above. And the end_decompress call.
		/+jpeg_destroy_decompress(&ds);+/

		// Initialize source management (where to get buffer data from).
		SourceManager* source = alloc!SourceManager;
		source.context = context;
		jpeg_source_mgr* jsrc = &source.jsrc;
		jsrc.init_source = &initSource;
		jsrc.term_source = &termSource;
		jsrc.fill_input_buffer = &fillBuffer;
		jsrc.skip_input_data = &skipBytes;
		jsrc.resync_to_restart = jpeg_resync_to_restart;
		ds.src = cast(jpeg_source_mgr*)source;

		// Read the header and return texture contents.
		if(jpeg_read_header(ds, true) != 1)
			throw new ContentImportException("Failed to read the JPEG header.");
		// Start this now to not worry about state in produceData. It just allocates.
		if(!jpeg_start_decompress(ds))
			throw new ContentImportException("Failed to start decompressing the image.");
		TextureContent content = new TextureContent(ds.image_width, ds.image_height, Untyped(ds), &produceData);
		source.rowSize = ds.image_width * ds.num_components;
		source.outputBuffer = BufferPool.Global.Acquire(source.rowSize);
		source.colorBuffer = new Color[ds.image_width];
		context.asset.trace("Image is " ~ ds.image_width.text ~ "x" ~ ds.image_height.text ~ "x" ~ ds.output_components.text ~ ".");
		return Untyped(content);
		// The actual decompress start comes when the AsyncRange requests the bytes.
	}

	private void produceData(Untyped state, ProducerCompletionCallback callback) {
		jpeg_decompress_struct* ds = cast(jpeg_decompress_struct*)state;
		SourceManager* source = cast(SourceManager*)ds.src;
		if(ds.output_scanline >= ds.image_height) {
			callback(ProducerStatus.complete, null);
			return;
		}
		// Read a single row at a time. Should always get a single row back.
		ubyte* dataPtr = source.outputBuffer.FullData.ptr;
		int rowsRead = jpeg_read_scanlines(ds, &dataPtr, 1);
		assert(rowsRead == 1, "Expected to read exactly 1 row, not " ~ rowsRead.text ~ ".");
		Color[] colors = source.colorBuffer;
		assert(colors.length == ds.output_width, "Colors array was not the correct size. Expected " ~ (source.rowSize / 4).text ~ ", got " ~ colors.length.text ~ ".");
		// If outside foreach for performance reasons. Not sure if compiler would handle that optimization.
		// Would be nice if we could make the library change the colour format for us, would be more efficient too.
		// A Color!(8, 8, 8) or such would also be useful, could use that instead.
		if(ds.output_components == 1) {
			foreach(i, ref color; colors) {
				color.r = color.g = color.b = dataPtr[i];
				color.a = 255;
			}
		} else if(ds.output_components == 3) {
			foreach(i, ref color; colors) {
				size_t byteIndex = i * 3;
				color.r = dataPtr[byteIndex];
				color.g = dataPtr[byteIndex + 1];
				color.b = dataPtr[byteIndex + 2];
				color.a = 255;
			}
		} else if(ds.output_components == 4) {
			// I don't think that 4 components is actually possible with libjpeg.
			// But libjpeg-turbo may in some cases be able to handle it?
			// If so, just RGBA format, which is the same as our desired output format, so can just set it.
			// It's safe to assign the buffer without making a copy.
			colors = cast(Color[])source.outputBuffer.FullData[0 .. source.rowSize];
		} else
			throw new ContentImportException("Image had " ~ ds.output_components.text ~ " components, not the expected 1 (greyscale) or 3 (RGB).");
		callback(ProducerStatus.more, colors);
	}
}

