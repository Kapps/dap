module ShardTools.SortedList;
import std.array;

/// Represents a list sorted by an integer key.
class SortedList(T) {
	
	/// Initializes a new instance of the SortedList class.
	/// Params: Capacity = The number of elements to be capable of storing initially.
	this(int Capacity) {
		Items = new SortedListItem[Capacity];
		_Length = 0;
	}
	
	/// Removes the specified item from the collection.
	/// Params: item = The item to remove.
	void Remove(T item) {
		int index = -1;
		for(index = 0; index < _Length; index++) {
			if(Items[index].Item == item)
				break;			
		}		
		if(index == _Length)
			return;
		_Length--;
		for(size_t i = index; i < _Length; i++)
			Items[index] = Items[index + 1];
		Items.length = Items.length - 1;
	}
	
	/// Adds the specified item to the collection.
	/// Params: 
	///		item = The item to add.
	///		key = The key of the item to add.
	void Add(T item, int Key) {
		size_t Index = GetIndexForKey(Key);
		_Length++;				
		//Items.insertInPlace(Index, new SortedListItem(item, Key));	
		Items = Items[0..Index] ~ new SortedListItem(item, Key) ~ Items[Index..$];
	}
	
	/// Returns the number of elements inside this SortedList.
	@property size_t Count() {
		return _Length;	
	}	

	T opIndex(size_t Index) {
		assert(Index < _Length && Index >= 0);
		return Items[Index].Item;
	}

	int opApply(int delegate(ref T) dg) {
		int Result;
		foreach(ref Item; Items)
			if((Result = dg(Item.Item)) != 0)
				break;
		return Result;
	}
	
private:
	SortedListItem[] Items;
	size_t _Length;
	
	class SortedListItem {
		T Item;
		int Key;
		
		this(T Item, int Key) {
			this.Item = Item;
			this.Key = Key;
		}
		
		override int opCmp(Object other) {			
			SortedListItem item = cast(SortedListItem)other;
			return Key > item.Key ? 1 : Key == item.Key ? 0 : -1;			
		}
	}
	
	size_t GetIndexForKey(int Key) {
		// TODO: Binary search.
		for(size_t i = 0; i < _Length; i++) {
			if(Items[i].Key >= Key)
				return i;
		}
		return _Length;		
	}
}