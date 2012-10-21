module dap.AssetStore;

/// Provides the implementation of any storage operations, such as loading data for an asset.
class AssetStore {

	this() {
		// Constructor code
	}
	
	/// Returns an InputSource used to read data for the given asset.
	abstract InputSource getInputSource(Asset asset);
	
	/// Returns an OutputSource used to write the generated data for the asset. This is the location of the built asset.
	abstract OutputSource getOutputSource(Asset asset);

	/// Returns all top level AssetContainers.
	@property abstract AssetContainer[] containers();
	
	/// Gets all references to the given asset.
	abstract AssetReference[] referencesToAsset(Asset asset);	
}

