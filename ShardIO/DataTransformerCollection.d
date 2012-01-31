module ShardIO.DataTransformerCollection;
private import ShardIO.DataTransformer;
private import std.array;
private import std.algorithm;
import ShardTools.ArrayOps;

/// A collection used to get sorted access to a series of DataTransformers.
class DataTransformerCollection  {

public:
	/// Initializes a new instance of the DataTransformerCollection object.
	this() {
		
	}

	/// Adds the given transformer to the collection.
	/// Params:
	/// 	Transformer = The transformer to add.
	void Add(DataTransformer Transformer) {
		size_t InsertIndex = IndexOf!"a.Priority > b.Priority"(_Transformers, Transformer);
		_Transformers.insertInPlace(InsertIndex + 1, Transformer);
	}

	/// Helper method to add multiple transformers.	
	/// Params:
	/// 	Transformers = The transformers to add.
	void Add(DataTransformer[] Transformers...) {
		foreach(DataTransformer Transformer; Transformers)
			Add(Transformer);
	}

	/// Removes the given transformer from the collection.
	/// Params:
	/// 	Transformer = The transformer to remove.
	/// Returns:
	///		True if the transformer was removed; false if not found.
	bool Remove(DataTransformer Transformer) {
		size_t Index = _Transformers.IndexOf(Transformer);
		if(Index == -1)
			return false;
		_Transformers = _Transformers[0..Index] ~ _Transformers[Index+1..$];		
		return true;
	}

	/// Provides sorted foreach access to the transformers in this collection.	
	int opApply(int delegate(ref DataTransformer) dg) {
		int Result;
		foreach(DataTransformer Transformer; _Transformers)
			if((Result = dg(Transformer)) != 0)
				break;
		return Result;
	}

	/// Provides reverse sorted foreach access to the transformers in this collection.
	int opApplyReverse(int delegate(ref DataTransformer) dg) {
		int Result;
		foreach_reverse(DataTransformer Transformer; _Transformers)
			if((Result = dg(Transformer)) != 0)
				break;
		return Result;
	}
	
private:
	DataTransformer[] _Transformers;
}