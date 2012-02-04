/// Provides unit tests for testing DataSources, as this requires more than one module.
module ShardIO.Unittests;

private:
private import ShardIO.FileOutput;
private import ShardIO.FileInput;
private import std.stdio;
private import std.conv;
private import std.math;
private import std.array;
private import ShardIO.MemoryOutput;
private import ShardIO.MemoryInput;
private import ShardIO.IOAction;
private import std.random;
private import std.file;

__gshared int NumTests;
__gshared InputData[] Inputs;
__gshared OutputData[] Outputs;

alias InputSource delegate(IOAction, ubyte[]) InputFactoryCallback;
alias OutputSource delegate(IOAction) OutputFactoryCallback;
alias bool delegate(IOAction, ubyte[]) VerificationCallback;

struct InputData {
	InputFactoryCallback Callback;

	this(InputFactoryCallback Callback) {
		this.Callback = Callback;
	}
}

struct OutputData {
	OutputFactoryCallback Callback;
	VerificationCallback Verifier;

	this(OutputFactoryCallback Callback, VerificationCallback Verifier) {
		this.Callback = Callback;
		this.Verifier = Verifier;
	}
}

private void RunAllTests() {
	foreach(InputData Input; Inputs) {
		foreach(OutputData Output; Outputs) {
			RunTest(Input, Output);
		}
	}
}

unittest {
	// MemoryInput / MemoryOutput
	Inputs ~= InputData(delegate(Action, Data) { return new MemoryInput(Action, Data, false); });
	Outputs ~= OutputData(
		delegate(Action) { return new MemoryOutput(Action); },
		delegate(Action, Data) { 
			MemoryOutput Output = cast(MemoryOutput)Action.Output;
			return Output.Data == Data;
		}
	);

	// FileInput / FileOutput
	string[] TmpFiles;
	scope(exit) {
		foreach(string FilePath; TmpFiles)
			if(exists(FilePath))
				remove(FilePath);
	}	

	string GetTempFile() {
		string FilePath = "ShardIOUnitTest" ~ to!string(NumTests++) ~ ".txt";
		TmpFiles ~= FilePath;
		return FilePath;
	}

	Inputs ~= InputData(delegate(Action, Data) {
		string FilePath = GetTempFile();
		File f = File(FilePath, "w");
		f.rawWrite(Data);
		f.close();
		return new FileInput(FilePath, Action);
	});
	
	string LastFile;
	Outputs ~= OutputData(
		delegate(Action) { LastFile = GetTempFile(); return new FileOutput(LastFile, Action); },
		delegate(Action, Data) { 			
			ubyte[] FileData = new ubyte[Data.length];
			auto file = File(LastFile, "r");
			file.rawRead(FileData);
			file.close();
			return FileData == Data;
		}
	);

	RunAllTests();
}

private void RunTest(InputData InData, OutputData OutData) {
	enum NumTests = 5;
	enum Base = 50;
	for(int i = 1; i <= NumTests; i++) {
		ubyte[] SomeArray = new ubyte[5 * pow(Base, i - 1)];
		foreach(ref ubyte Element; SomeArray)
			Element = uniform!ubyte();	
		IOAction Action = new IOAction();
		InputSource Input = InData.Callback(Action, SomeArray);
		OutputSource Output = OutData.Callback(Action);		
		Action.Completed.Add(delegate(IOAction Acton, CompletionType Type) {
			assert(Type == CompletionType.Successful, "The action did not complete successfully for " ~ typeid(Input).stringof ~ " and " ~ typeid(Output).stringof ~ " on run number " ~ to!string(i) ~ ".");
			assert(OutData.Verifier(Action, SomeArray), "The action did not verify successfully for " ~ typeid(Input).stringof ~ " and " ~ typeid(Output).stringof ~ " on run number " ~ to!string(i) ~ ".");
		});
		Action.Start(Input, Output);
		Action.WaitForCompletion();
	}
} 