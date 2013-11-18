module dap.TextureImporter;

// TODO: Just here for documentation of roughly how it'd work.

class TextureContent {
	uint width, height;
	// Read!Colour width * height times.
	//StreamOutput colours;
	// Then convert it to whatever format and use a StreamInput to write to our OutputSource.
	// The IOAction would automatically finish when we reach the end of this stream, so all is well. In theory.
	// Maybe include an IOAction for good measure. No need, can access it through the StreamOutput.
	// This way can stop early if needed.

}

class TextureImporter
{
	this()
	{
		// Constructor code
	}
}

