module dap.BuildContext;
public import dap.BuildLogger;
import std.range;
import ShardTools.Map;
import std.string;
import std.conv;
import ShardTools.ExceptionTools;
import ShardTools.StringTools;

/// Provides information about a build, such as Asset Stores and loggers.
class BuildContext {

	/// Creates a new BuildContext with the given logger.
	this(BuildLogger logger) {
		this._logger = logger;
	}
	
	/// Gets the BuildLogger used for this context.
	@property BuildLogger logger() {
		return _logger;
	}
	
	/// Gets the AssetStore with the given identifier, or null if none was found.
	AssetStore getStore(string store) {
		string fixed = toLower(store).strip();
		synchronized(this) {
			return _stores.get(fixed, null);
		}
	}

	/// Returns all of the AssetStores within this BuildContext.
	auto allStores() {
		synchronized(this) {
			return _stores.values.array;
		}
	}
	
	/+/**
	 * Finds the asset with the given qualified name, including AssetStore name.
	 * If no Asset was found, or qualifiedName is in an incorrect format, returns null.
	 */
	public Asset getAsset(string qualifiedName) {
		auto nameParts = HierarchyNode.splitQualifiedName(qualifiedName).array;
		if(nameParts.length < 2)
			return null;
		AssetStore store = getStore(nameParts[0]);
		string[] folderParts = nameParts[1..$-1];
		string assetName = nameParts[$-1];
		HierarchyNode current = store;
		foreach(part; folderParts) {
			HierarchyNode next = current.getChild(part);
			if(next is null) {
				next = store.createAssetContainer(current, part);
				return null;
			}
			current = next;
		}
		Asset asset = current.getChild(assetName);
		if(asset is null)
			asset = store.loadAsset(current, assetName);
		return asset;
	}+/
	
	/**
	 * Finds the node with the given qualified name, including AssetStore name.
	 * If no asset was found, or qualifiedName is in an incorrect format, returns null.
	 */
	public HierarchyNode getNode(string qualifiedName) {
		auto nameParts = HierarchyNode.splitQualifiedName(qualifiedName).array;
		auto store = nameParts ? getStore(nameParts[0]) : null;
		if(store is null)
			return null;
		HierarchyNode current = store;
		foreach(part; nameParts[1..$]) {
			HierarchyNode next = current.children[part];
			if(next is null) {
				logger.trace("Getting " ~ qualifiedName ~ " failed because " ~ current.name 
				             ~ " did not contain a child named " ~ part ~ ".");
				return null;
			}
			current = next;
		}
		return current;
	}
	
	package void registerStore(AssetStore store) {
		logger.trace("Registering " ~ store.text ~ ".", store);
		string key = toLower(store.name).strip();
		synchronized(this) {
			if(key in _stores)
				throw new DuplicateKeyException("A store named " ~ key ~ " was already registered for this BuildContext.");

			_stores[key] = store;
			logger.trace("Done registering " ~ store.text ~ ".", store);
		}
	}
	
	BuildLogger _logger;
	AssetStore[string] _stores;
}

