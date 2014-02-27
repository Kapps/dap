module dap.ContentProcessor;
public import vibe.core.stream;
import std.traits;
public import ShardTools.Udas;
public import ShardTools.Reflection;
import std.algorithm;
import dap.Asset;
public import dap.NodeSettings;
import std.string;
import std.variant;
public import ShardTools.Untyped;
import ShardTools.SpinLock;
import ShardTools.ExceptionTools;
import std.conv;
public import dap.ContentImporter;

/// Processes of data returned by a ContentImporter to generate the data that will be read at runtime.
/// Each ContentProcessor instance is only used for building a single Asset at most a single time.
/// All fields not marked @Ignore will automatically be managed by the Asset's setting store.
/// All classes deriving from ContentProcessor must have metadata available and have a parameter that takes in a single Asset.
/// Classes deriving from ContentProcessor should mixin makeProcessorMixin, or else implement storage themselves.
class ContentProcessor {

	// TODO: Rename Content -> Asset for Importer|Processor.
	// TODO: Processing should include a BuildContext.
	
	/// Registers the processor with the specified name and type.
	/// The processor is then also registered as the default processor for all extensions given.
	static void registerProcessor(string name, string extensions[], TypeMetadata type) {
		_storeLock.lock();
		scope(exit)
			_storeLock.unlock();
		_storedProcessorsByName[fixedKey(name)] = type;
		foreach(string extension; extensions)
			_storedNameByExtension[fixedKey(extension)] = name;
	}
	
	/// Creates an instance of the ContentProcessor with the given name, loading it's
	/// settings from the specified asset's setting store.
	/// If no processor is registered with the given name, null is returned.
	static ContentProcessor create(string name, Asset asset) {
		TypeMetadata instanceType;
		{
			_storeLock.lock();
			scope(exit)
				_storeLock.unlock();
			instanceType = _storedProcessorsByName.get(fixedKey(name), TypeMetadata.init);
		}
		std.stdio.writeln("Instance type is ", instanceType, ".");
		auto result = instanceType.createInstance(asset).get!ContentProcessor;
		std.stdio.writeln("Result is ", result, ".");
		if(asset)
			result.loadSettings();
		return result;
	}

	/// Returns the name of the default ContentProcessor set to handle the given extension.
	/// If no processor is assigned for the extension, null is returned.
	static string getDefaultProcessorForExtension(string extension) {
		_storeLock.lock();
		scope(exit)
			_storeLock.unlock();
		string result = _storedNameByExtension.get(fixedKey(extension), null);
		return result;
	} 

	/// Returns the type of the data used as input for this ContentProcessor.
	@Ignore(true) @property abstract TypeInfo inputType();

	/// Gets the asset that this ContentProcessor is created to process.
	@Ignore(true) @property final Asset asset() {
		return _asset;
	}
	
	/// Creates a new ContentProcessor capable of processing the specified asset,
	/// loading any existing settings contained by the node's setting store.
	this(Asset asset) {
		this._asset = asset;
	}

	/// Processes the specified input, writing the result to the given output stream.
	final void process(Untyped input, OutputStream output) {
		if(input.type != inputType)
			throw new InvalidFormatException("The type of the data in the variant does not match the expected type.");
		performProcess(input, output);
	}

	/// Reloads all settings from the underlying assets store.
	/// This may not necessarily reset all settings, as it will only
	/// reload those that are already saved to the store.
	final void loadSettings() {
		performLoad(asset.settings);
	}

	/// Saves all settings to the underlying assets store.
	final void saveSettings() {
		performSave(asset.settings);
	}

	/// Returns an instance of a ContentImporter used to generate the input type for this processor.
	/// If no importer is found, null is returned.
	ContentImporter createImporter() {
		return ContentImporter.findImporter(asset.extension, inputType);
	}

	/// Processes the given input data, writing the runtime data to the specified OutputSource.
	/// Returns the action that is used for generating the output data.
	/// The input data is guaranteed to be of exact type $(D inputType).
	protected abstract void performProcess(Untyped input, OutputStream output);

	/// Override to handle loading settings for this processor from the specified node's settings.
	/// Note that mixing in $(D makeProcessorMixin) will automatically generate this method.
	protected abstract void performLoad(NodeSettings settings);

	/// Override to handle saving settings for this processor to the specified node's settings.
	/// Note that mixing in $(D makeProcessorMixin) will automatcally generate this method.
	protected abstract void performSave(NodeSettings settings);

	/// Gets the metadata used for this processor.
	@Ignore(true) final @property TypeMetadata metadata() {
		auto result = typeid(this).metadata;
		if(result == TypeMetadata.init || result.type != typeid(this))
			throw new ReflectionException("No metadata was generated for " ~ typeid(this).text ~ ".");
		return result;
	}


	/// Must be mixed in to each type deriving from ContentProcessor to handle
	/// automatic saving and loading of fields and generates metadata.
	/// The processor is registered with the given name and set as
	/// the default processor for the specified extensions.
	protected static string makeProcessorMixin(string name, string[] extensions) {
		return format(q{
			shared static this() {
				auto metadata = createMetadata!(typeof(this));
				registerProcessor("%s", %s, metadata);
			}
			/// Loads all settings for this processor from the given setting store.
			protected override void performLoad(NodeSettings settings) {
				loadSettings!(typeof(this))(settings, this);
			}

			/// Saves all settings of the given ContentProcessor to the given store.
			protected override void performSave(NodeSettings settings) {
				saveSettings!(typeof(this))(settings, this);
			}
		}, name, extensions);
	}

	/// Indicates if the given member should be ignored for purposes of saving/loading.
	protected static bool isIgnored(T, size_t i)() {
		foreach(attrib; __traits(getAttributes, T.tupleof[i])) {
			static if(is(typeof(attrib) == Ignore)) {
				return attrib.value;
			}
		}
		return false;
	}

	// Intentionally not documented; exposed for mixin functionality only.
	protected static void loadSettings(T)(NodeSettings settings, T instance) {
		// Note that instance.tupleof is different depending on T.
		// So have to call this for each base until we reach Object.
		foreach(i, m; instance.tupleof) {
			static if(!isIgnored!(T, i)) {
				// TODO: Check if the type is an Asset, and load a reference instead.
				// Will need AssetReference(T) for this.
				enum name = __traits(identifier, instance.tupleof[i]);
				string key = propertyNameForValue(instance.metadata, name);
				auto val = settings.get!(typeof(instance.tupleof[i]))(key, instance.tupleof[i]);
				instance.tupleof[i] = val;
			}
		}
		static if(!is(T == ContentProcessor)) {
			loadSettings!(BaseClassesTuple!(T)[0])(settings, instance);
		}
	}

	// Intentionally not documented; exposed for mixin functionality only.
	protected static void saveSettings(T)(NodeSettings settings, T instance) {
		static if(!is(T == ContentProcessor))
			saveSettings!(BaseClassesTuple!(T)[0])(settings, instance);
		foreach(i, m; instance.tupleof) {
			static if(!isIgnored!(T, i)) {
				// TODO: Check if the type is an Asset, and store a reference instead.
				// Will need AssetReference(T) for this.
				enum name = __traits(identifier, instance.tupleof[i]);
				string key = propertyNameForValue(instance.metadata, name);
				settings.set!(typeof(instance.tupleof[i]))(key, instance.tupleof[i]);
			}
		}
	}
	
	private static string propertyNameForValue(TypeMetadata metadata, string name) @safe pure {
		return metadata.name ~ "." ~ name;
	}

	private static string fixedKey(string val) @safe pure {
		string result = val.strip.toLower;
		if(result.length > 1 && result[0] == '.')
			result = result[1..$];
		return result;
	}

	@Ignore(true) Asset _asset;
	@Ignore(true) __gshared TypeMetadata[string] _storedProcessorsByName;
	@Ignore(true) __gshared string[string] _storedNameByExtension;
	@Ignore(true) __gshared SlimSpinLock _storeLock;
}

