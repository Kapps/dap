module ShardTools.Mixins;
private import std.conv;
private import ShardTools.ArrayOps;
private import std.uni;



static class Mixins  {

public:
	/// Initializes all of the given fields with a default constructor.
	/// Params:
	/// 	Fields = The fields to construct.
	static string ConstructEmpty(string[] Fields...) {
		string Result = "";
		foreach(string Field; Fields) {
			Result ~= Field ~ " = new typeof(" ~ Field ~ ");\r\n";
		}
		return Result;
	}

	/// Returns a mixin that for each non-private non-class upper-case member in the class, creates an alias with the first letter lowercase.	
	static string CreateLowercaseAliases(T)(string[] FieldsToExclude ...) {
		string[] CreatedAliases;
		foreach(Field; FieldsToExclude)
			CreatedAliases ~= Field;
		string Result = "";				
		foreach(MemberName; __traits(derivedMembers, T)) {
			if(CreatedAliases.Contains(MemberName))
				continue;				
			if(isUpper(MemberName[0])) {
				string NewAlias = to!string(toLower(MemberName[0])) ~ MemberName[1..$];
				Result ~= "alias " ~ MemberName ~ " " ~ NewAlias ~ "; ";
				CreatedAliases ~= MemberName;
			}
		}
		return Result;
		//return "";
	}

private:
}