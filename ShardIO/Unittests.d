/// Provides unit tests for testing DataSources, as this requires more than one module.
module ShardIO.Unittests;

private:
private import core.thread;
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

alias InputSource delegate(ubyte[]) InputFactoryCallback;
alias OutputSource delegate() OutputFactoryCallback;
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
	Inputs ~= InputData(delegate(Data) { return new MemoryInput(Data, false); });
	Outputs ~= OutputData(
		delegate() { return new MemoryOutput(); },
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
		if(exists(FilePath))
			remove(FilePath);
		return FilePath;
	}

	Inputs ~= InputData(delegate(Data) {
		string FilePath = GetTempFile();
		File f = File(FilePath, "w");
		f.rawWrite(Data);
		f.close();
		return new FileInput(FilePath);
	});
	
	string LastFile;
	Outputs ~= OutputData(
		delegate() { LastFile = GetTempFile(); return new FileOutput(LastFile); },
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
		InputSource Input = InData.Callback(SomeArray);
		OutputSource Output = OutData.Callback();		
		IOAction Action = new IOAction(Input, Output);
		bool DoneVerifying = false;
		Action.NotifyOnComplete(delegate(IOAction Acton, CompletionType Type) {
			assert(Type == CompletionType.Successful, "The action did not complete successfully for " ~ typeid(Input).stringof ~ " and " ~ typeid(Output).stringof ~ " on run number " ~ to!string(i) ~ ".");
			assert(OutData.Verifier(Action, SomeArray), "The action did not verify successfully for " ~ typeid(Input).stringof ~ " and " ~ typeid(Output).stringof ~ " on run number " ~ to!string(i) ~ ".");
			DoneVerifying = true;
		});
		Action.Start();
		try {
			Action.WaitForCompletion(dur!"seconds"(10));		
		} catch (TimeoutException) {
			assert(0, "The action using " ~ to!string(typeid(Input)) ~ " and " ~ to!string(typeid(Output)) ~ " did not complete prior to the timeout on run number " ~ to!string(i) ~ ".");
		}
	}
} 