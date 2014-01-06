/// Provides helper functions for creating dynamically loaded bindings to libraries.
/// Generally it is recommended to manually mix in the code in order to assist with tooling.
/// License: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>
/// Authors: Ognjen Ivkovic
/// Copyright: © 2013 Ognjen Ivkovic
module dap.bindings.utils;

struct Sym {
	const string returnType;
	const string name;
	const string args;

	this(string returnType, string name, string args) {
		this.returnType = returnType;
		this.name = name;
		this.args = args;
	}
}

string getLoaderMixin(string libNames, string loaderName)(Sym[] syms...) {
	enum prefix = "da_";
	enum className = "Derelict" ~ loaderName ~ "Loader";
	string wrappers = "extern(C) nothrow {\n";
	string vars = "__gshared {\n";
	string loader = 
"class " ~ className ~ ": SharedLibLoader {
\tpublic this() {
\t\tsuper(\"" ~ libNames ~ "\");
\t}

\tprotected override void loadSymbols() {\n";

	foreach(Sym sym; syms) {
		wrappers ~= "\talias " ~ sym.returnType ~ " function(" ~ sym.args ~ ") " ~ prefix ~ sym.name ~ ";\n";
		vars ~= "\t" ~ prefix ~ sym.name ~ " " ~ sym.name ~ ";\n";
		loader ~= "\t\tbindFunc(cast(void**)&" ~ sym.name ~ ", \"" ~ sym.name ~ "\");\n";
	}

	wrappers ~= "}";
	vars ~= "}";
	loader ~= "\t}\n}\n\n__gshared " ~ className ~ " Derelict" ~ loaderName ~ ";\n\n";
	loader ~= "shared static this() {\n\tDerelict" ~ loaderName ~ " = new " ~ className ~ "();\n}";
	return wrappers ~ "\n" ~ vars ~ "\n" ~ loader;
}
