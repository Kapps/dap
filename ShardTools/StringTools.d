module ShardTools.StringTools;

import std.conv;
import std.string;
import ShardTools.Logger;

/// Returns a null-terminated string containing the letters in String up to any null terminated characters, or otherwise the length.
/// A new string is always made, even if String ends with a single null terminator.
static char[] Terminate(in char[] String) {	
	for(size_t i = 0; i < String.length; i++)
		if(String[i] == '\0')
			return String[0 .. i].dup;	
	return String[0 .. String.length].dup ~ '\0';			
}	

/// Trims the length of the specified string to equal to the size of the string up to the first found null terminator.
/// Params: 
///		String = [inout] The string to alter the length of.
///		IncludeNull = Whether to include the null terminator in the altered string.
/// Returns: Whether any alterations were performed. None will be performed if the string ends in null or did not contain any null terminators.
static bool TrimToNull(ref char[] String, bool IncludeNull = false) {
	size_t nullIndex = IndexOfNull(String);
	if(nullIndex == -1)
		return false;
	if(nullIndex == String.length - 1)
		if(IncludeNull)
			return false;				
	String = String[0 .. nullIndex + (IncludeNull ? 1 : 0)];	
	return true;
}

/// Trims the length of the specified string to equal to the size of the string up to the first found null terminator.
/// Unlike TrimToNull, this method returns the string passed in, and instead WasTrimmed is set to false if the string was not trimmed.
/// Params: 
///		String = [inout] The string to alter the length of.
///		IncludeNull = Whether to include the null terminator in the altered string.
static char[] TrimReturn(ref char[] String, bool IncludeNull = false, bool* WasTrimmed = null) {
	if(!IsTerminated(String)) {
		if(WasTrimmed !is null)
			*WasTrimmed = false;
		return String;
	}			
	if(WasTrimmed != null)
		*WasTrimmed = TrimToNull(String, IncludeNull);
	else
		TrimToNull(String, IncludeNull);
	return String;
}

/// Returns the index of the first null terminator inside the specified string, or -1 if none was found.	
static size_t IndexOfNull(in char[] String) {
	for(size_t i = 0; i < String.length; i++)
		if(String[i] == '\0')
			return i;
	return -1;
}

/// Returns whether the specified string contains any null terminators.
static bool IsTerminated(in char[] String) {
	return IndexOfNull(String) != -1;
}