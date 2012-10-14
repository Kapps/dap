module ShardTools.ArrayOps;
private import std.traits;
import std.parallelism;
import std.functional;


/// Determines whether Range contains any element such that Condition for that element and Element evaluates to true.
/// Params:
/// 	Condition = The condition to evaluate. When this evaluates as true, the function returns true.
/// 	Collection = The type of the collection to use for this Range.
/// 	T = The type of the Element to compare to.
/// 	Range = The range to perform this operation on.
/// 	Element = The element to compare each element in the range to.
bool Contains(alias Condition = "a == b", Collection, T)(Collection Range, T Element) if(is(typeof(binaryFun!Condition))) {
	foreach(ref a; Range)
		if(binaryFun!Condition(a, Element))
			return true;
	return false;
}

/// Determines the number of elements in the collection that satisfy the given action.
/// Params:
///		Condition = The condition to evaluate. When this evalutes as true, the result is incremented.
///		Collection = The type of the collection to use for Range.
///		Range = The range to perform this operation on.
size_t Count(alias Condition = "true", Collection)(Collection Range) if(is(typeof(unaryFun!Condition))) {
	static if(hasMember!(Collection, "length")) {
		if(Condition == "true")
			return Range.length;
	}	
	size_t Result = 0;
	foreach(ref a; Range)
		if(unaryFun!Condition(a))
			Result++;
	return Result;
} 

/// Determines the first index within Range such that Condition is true, or -1 if Condition never evaluated to true.
/// Params:
/// 	Condition = The condition to evaluate. When this evaluates as true, the index it evaluated as true for is returned. Element is be defined as 'b'.
/// 	Collection = The type of the collection to use for this Range.
/// 	T = The type of the Element to compare to.
/// 	Range = The range to perform this operation on.
/// 	Element = The element to compare each element in the range to.
size_t IndexOf(alias Condition = "a == b", Collection, T)(Collection Range, T Element) if(is(typeof(binaryFun!Condition))) {	
	foreach(Index, ref a; Range)
		if(binaryFun!Condition(a, Element))
			return Index;
	return -1;
}
 
/// Performs the specified operation on all elements in Range (with each element aliased as a).
/// Params:
///		Collection = The type of the collection to use for Range.
///		Range = The range to perform this operation on.
///		Action = The operation to perform on each element.
void ForEach(alias Action, Collection)(Collection Range) {	
	foreach(ref a; Range)			
		(mixin(Action));					
}

/// Performs the specified operation on all elements in Range.
/// This method is less efficient than template alias ForEach.
/// Params:
/// 	ElementType = The type of each element within the range.
/// 	Collection  = The type of the range.
/// 	Range       = The range to loop over all elements for.
/// 	Callback    = A delegate to invoke upo neach element in this range.
void ForEach(ElementType, Collection)(Collection Range, void delegate(ref ElementType) Callback) {
	foreach(ref a; parallel(Range))
		Callback(a);
}

/// Performs the specified operation on all elements in Range (with each element aliased as a).
/// Params:
///		Collection = The type of the collection to use for Range.
///		Range = The range to perform this operation on.
///		Action = The operation to perform on each element.
///		ParallelCount = The number of elements per thread to use to perform this task. A value of zero allows the taskpool to decide how many threads to use.
void ForEach(alias Action, Collection)(Collection Range, int ParallelCount) {	
	if(ParallelCount == 0)
		foreach(ref a; parallel(Range))			
			(mixin(Action));					
	else
		foreach(ref a; parallel(Range, ParallelCount))			
			(mixin(Action));					
}


/// Determines if all of the elements in the given collection satisfy the given predicate.
/// Params:
///		Condition = The condition to evaluate. If this expression ever returns false, the function does as well.
///		Collection = The type of the collection to use for Range.
///		Range = The range to perform this operation on.
bool All(alias Condition, Collection)(Collection Range) if(is(typeof(unaryFun!Condition))) {
	foreach(ref Element; Range)
		if(!unaryFun!Condition(Element))
			return false;
	return true;
}

/// Determines if any of the elements in the given collection satisfy the given predicate.
/// Params:
///		Condition = The condition to evaluate. If this expression ever returns true, the function does as well.
///		Collection = The type of the collection to use for Range.
///		Range = The range to perform this operation on.
bool Any(alias Condition, Collection)(Collection Range) if(is(typeof(unaryFun!Condition))) {
	foreach(ref Element; Range)
		if(unaryFun!Condition(Element))
			return true;
	return false;
}

/// Evaluates condition on all elements in the collection until one evaluates to false, performing Action on all that evaluate to true.
/// Params:
///		Condition = The condition to evaluate. When this evalutes to false, no more elements are iterated over.
///		Collection = The type of the collection to use for Range.
///		Range = The range to perform this operation on.
///		Action = The operation to perform on each element.
void While(alias Action, alias Condition, Collection)(Collection Range) if(is(typeof(unaryFun!Condition))) {
	foreach(ref a; Range) {
		if(!mixin(Condition)) 
			break;
		mixin(Action);
	}
}

/// Performs Action on all elements in the collection until Action evaluates to false. Similar to Until, except that the result of Action is checked instead of a separate condition.
/// Params:
///		Collection = The type of the collection to use for Range.
///		Range = The range to perform this operation on.
///		Action = The operation to perform on each element. When this evaluates as false, the method returns.
void WhileTrue(alias Action, Collection)(Collection Range) if(is(typeof(unaryFun!Action))) {
	foreach(ref a; Range)
		if(!mixin(Action))
			break;		
}

/// Lazily iterates over all of the elements in Range that can be explicitly converted to type T.
/// Because this allows casting, ref is not allowed.
/// Params:
/// 	T = The type of the element to cast to.
/// 	Range = The underlying range to get the elements from.
/// 	CollectionType = The type of the range.
auto OfType(T, CollectionType)(CollectionType Range) {
	struct Result {		
		@property bool empty() {
			return Input.empty;
		}

		void popFront() {
			Input.popFront();
		}		

		@property auto front() {
			return cast(T)Input.front;
		}

		this(CollectionType Input) {
			this.Input = Where!(c=>cast(T)c !is null)(Input);
		}

		private typeof(Where!(c=>cast(T)c !is null)(Range)) Input;
	}
	return Result(Range);
}

/// Returns all of the elements in Range that evaluate to true for Condition.
/// Params:
/// 	Condition = The condition to evaluate for each element, with each element being called "a".
/// 	Collection = The type of the range.
/// 	Range = The range to perform this operation on.
auto Where(alias Condition, Collection)(Collection Range) if(is(typeof(unaryFun!Condition))) {
	struct WhereResult {
		alias Unqual!Collection R;			
		@property bool empty() {
			return Input.empty;
		}
			
		void popFront() {
			do 
				Input.popFront();
			while(!Input.empty && !unaryFun!Condition(Input.front));					
		}
			
		@property auto ref front() {
			return Input.front;
		}
			
		this(R Input) {
			this.Input = Input;
			while(!Input.empty && !unaryFun!Condition(Input.front))
				Input.popFront();
		}
			
		int opApply(int delegate(ref size_t) dg) {
			int DgResult;		
			foreach(ref a; Input) {
				if(!(mixin(Condition)))
					continue;					
				DgResult = dg(a);
				if(DgResult)
					break;
			}				
			return DgResult;
		}
			
		R Input;
	}
}