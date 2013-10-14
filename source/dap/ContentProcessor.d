module dap.ContentProcessor;
import ShardIO.OutputSource;
import std.traits;
import ShardTools.Udas;
public import ShardTools.Reflection;
import std.algorithm;
import dap.Asset;
import dap.NodeSettings;
import std.string;

/// Processes of data returned by a ContentImporter to generate the data that will be read at runtime.
/// Each ContentProcessor instance is only used for building a single Asset a single time.
/// All fields not marked @Ignore will automatically be managed by the Asset's setting store.
/// All classes deriving from ContentProcessor must have metadata available and have a parameterless constructor.
/// Classes deriving from ContentProcessor should mixin makeProcessorMixin, or else implement storage themselves.
class ContentProcessor(T) {

	// TODO: Rename Content -> Asset for Importer|Processor.

	/// Returns the type of the data used as input for this ContentProcessor.
	@Ignore final const(TypeInfo) inputType() const {
		return typeid(Unqual!T);
	}

	/// Processes the given input data, writing the runtime data to the specified OutputSource.
	/// Returns the action that is used for generating the data.
	abstract AsyncAction process(T input, OutputSource output);

	/// Override to handle loading of stored settings for this asset.
	/// Note that mixing in makeProcessorMixin will automatically generate this method.
	/// Generating metadata is generally done here as well.
	protected abstract void load(Asset asset) { } // Has a definition so we can always use super.load();

	private static string propertyNameForValue(string name) @safe pure nothrow {
		return this.metadata.name ~ "." ~ name;
	}

	/// Must be mixed in to each type deriving from ContentProcessor to handle
	/// automatic saving and loading of fields and generate metadata.
	protected enum makeProcessorMixin(string name) {
		return format(q{
			shared static this() {
				auto metadata = createMetadata!(typeof(this));
				registerProcessor(%s, metadata);
			}
			/// Loads all settings for this processor from the given setting store.
			protected override void load(NodeSettings settings) {
				this.metadata = createMetadata!(typeof(this));
				loadSettings!(typeof(this))(settings, this);
			}

			/// Saves all settings of the given ContentProcessor to the given store.
			protected override void save(NodeSettings settings) {
				this.metadata = createMetadata!(typeof(this));
				saveSettings!(typeof(this))(settings, this);
			}
		}, name);
	}

	private static void loadSettings(T)(NodeSettings settings, T instance) @safe pure {
		// Note that instance.tupleof is different depending on T.
		// So have to call this for each base until we reach Object.
		foreach(i, m; instance.tupleof) {
			static if(isIgnored!m)
				continue;
			// TODO: Check if the type is an Asset, and load a reference instead.
			// Will need AssetReference(T) for this.
			enum name = __traits(identifier, m);
			string key = propertyNameForValue(name);
			auto val = settings.get!(typeof(instance.tupleof[i]))(key, instance.tupleof[i]);
			instance.tupleof[i] = val;
		}
		static if(!is(T == ContentProcessor))
			loadSettings!(BaseClassesTuple!(T)[0])(settings, instance);
	}

	private static void saveSettings(T)(NodeSettings settings, T instance) @safe pure {
		static if(!is(T == ContentProcessor))
			saveSettings!(BaseClassesTuple!(T)[0])(settings, instance);
		foreach(i, m; instance.tupleof) {
			static if(isIgnored!m)
				continue;
			// TODO: Check if the type is an Asset, and store a reference instead.
			// Will need AssetReference(T) for this.
			enum name = __traits(identifier, m);
			string key = propertyNameForValue(name);
			settings.set!(typeof(instance.tupleof[i]))(name, instance.tupleof[i]);
		}
	}

	/// Indicates if the given member should be ignored for purposes of saving/loading.
	protected static bool isIgnored(alias m)() {
		foreach(attrib; __traits(getAtributes, m)) {
			static if(is(attrib == Ignore)) {
				return (cast(Ignore)attrib).value;
			}
		}
		return false;
	}

	static void registerProcessor(string name, TypeMetadata type) {

	}
}

