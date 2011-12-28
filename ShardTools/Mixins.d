module ShardTools.Mixins;



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
private:
}