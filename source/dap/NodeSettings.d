module dap.NodeSettings;
public import dap.Asset;
import ShardTools.Untyped;
import ShardTools.MessagePack;
import std.string;
import dap.HierarchyNode;
import ShardTools.Buffer;
import ShardTools.StreamReader;
import ShardTools.BufferPool;
import ShardTools.ExceptionTools;
import std.stdio;

/// Provides the processor settings for a given HierarchyNode, usually an asset.
/// This class is thread-safe.
/// All setting operations operate on snapshots of a value, thus changing the value after setting it 
/// will not propogate the changes to this instance. Instead, a copy is saved using MessagePack serialization.
final class NodeSettings {
	
	/// Creates a new instance of NodeSettings for the given node.
	this(HierarchyNode node) {
		this._node = node;
	}
	
	/// Gets the node that these settings are being used for.
	@property final HierarchyNode node() {
		return _node;
	}
	
	/**
	 * Returns an input range that iterates over the names of settings stored on this node.
	 */
	public auto keys() {
		synchronized(this) {
			auto results = settings.keys.dup;
			return results;
		}
	}
	
	/// Returns the number of settings contained in this instance.
	public size_t length() {
		return settings.length;	
	}
	
	/**
	 * Returns the stored snapshot of the value of the setting with the given name.
	 */
	public T get(T)(string name, lazy T defaultValue = T.init) {
		synchronized(this) {
			ubyte[] data = settings.get(fixedKey(name), null);
			if(data == null)
				return defaultValue();
			T result;
			unpack(data, result);
			return result;
		}
	}
	
	/**
	 * Assigns the specified setting to a snapshot of value.
	 * Future changes to value will not be propogated until another call to set.
	 */
	public void set(T)(string name, T value) {
		settings[fixedKey(name)] = pack(value);	
	}
	
	/// Serializes this instance to the given Buffer.
	/// This may then be deserialized through a call to deserialize.
	void serialize(Buffer buffer) {
		buffer.Write(cast(uint)settings.length);
		foreach(string key, ubyte[] value; settings) {
			buffer.WritePrefixed(key);
			buffer.WritePrefixed(value);
		}
	}
	
	/// Deserializes data returned by a call to serialize. This NodeSettings instance must be empty.
	/// Returns the amount of bytes used from data.
	size_t deserialize(ubyte[] data) {
		if(settings.length != 0)
			throw new InvalidOperationException("The NodeSettings instance must be empty in order to deserialize values.");
		StreamReader reader = new StreamReader(data, true);
		uint length = reader.Read!uint;
		for(uint i = 0; i < length; i++) {
			string key = cast(string)reader.ReadPrefixed!char;
			ubyte[] value = reader.ReadPrefixed!ubyte;
			settings[key] = value;	
		}
		return reader.Position;
	}
	
	unittest {
		NodeSettings Settings = new NodeSettings(null);
		Settings.set("test", 3);
		Settings.set("testString", "This is a test!");
		Buffer buff = BufferPool.Global.Acquire(4096);
		Settings.serialize(buff);
		NodeSettings Deserialized = new NodeSettings(null);
		Deserialized.deserialize(buff.Data);
		assert(Deserialized.get!int("test") == 3);
		assert(Deserialized.get!string("testString") == "This is a test!");
		assert(Deserialized.get!int("TeSt") == 3);
		
	}
	
	private string fixedKey(string input) {
		return toLower(input).strip;	
	}
	
	private alias ubyte[] ContentData;
	HierarchyNode _node;
	ContentData[string] settings;
}

