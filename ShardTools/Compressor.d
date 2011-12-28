﻿module ShardTools.Compressor;
import etc.c.zlib;
import std.zlib;

/// A class used to compress data.
public class Compressor  {

public:
	/// Compresses the given data using the deflate specification.
	static void[] ToDeflate(void[] Data, bool IncludeMagicNumber = false) {		
		void[] Result = cast(void[])compress(Data);
		char* Ptr = cast(char*)Result.ptr;
		if(!IncludeMagicNumber && Ptr[0] == 0x78 && Ptr[1] == 0x9C)
			Result = Result[2..$]; // Strip off magic number.
		return Result;
	}

	/// Compresses the given data using the gzip specification.
	static void[] ToGzip(void[] Data) {
		void[] Deflated = ToDeflate(Data, false);
		return DeflateToGzip(Deflated, Data);
	}

	/// Converts the data that was converted to gzip format with ToGzip into deflate format.
	/// This ONLY works for data converted with ToGzip, as it assumes the header is 10 bytes.
	/// The data returned is the deflate portion of the gzip stream, and thus editing this data edits the initial gzip data.
	static void[] GzipToDeflate(void[] Data) {
		return (cast(ubyte[])Data)[10..$-8];
	}

	/// Converts the data that was converted to deflate format with ToDeflate into gzip format.	The original data, or the crc and length of the original data, is required.
	/// Params:
	///		Data = The deflated data to convert.
	/// 	Original = The non-compressed data.
	/// 	OriginalCRC = The crc32 of the original data.
	/// 	OriginalLength = The length of the original data.
	static void[] DeflateToGzip(void[] Data, const void[] Original) {
		return ToGzipInternal(Data, Original.length, std.zlib.crc32(0, Original));
	}

	/// Ditto
	static void[] DeflateToGzip(void[] Data, uint OriginalCRC, ulong OriginalLength) {
		return ToGzipInternal(Data, OriginalLength, OriginalCRC);
	}

	private static void[] ToGzipInternal(void[] Deflated, ulong OriginalLength, uint OriginalCRC) {
		ubyte[10] Header;
		Header[0] = 0x1F; // Magic Number (2 bytes).
		Header[1] = 0x8B;
		Header[2] = 8; // Deflate algorithm.
		Header[3] = 0; // Flags. None.
		Header[4] = 0; // Timestamp indicating last change (4 bytes).
		Header[5] = 0;
		Header[6] = 0;
		Header[7] = 0;
		Header[8] = 0; // Extra flags. None.
		version(Windows)
			Header[9] = 0;
		else version(Posix)
			Header[9] = 3;		
		else
			Header[9] = 255;
		uint[2] Footer;
		Footer[0] = OriginalCRC;
		Footer[1] = cast(uint)(OriginalLength % uint.max);
		void[] FooterVoid = cast(void[])Footer;

		return cast(void[])Header ~ Deflated ~ FooterVoid;
	}
	
private:
}