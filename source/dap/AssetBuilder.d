module dap.AssetBuilder;
import ShardTools.ConcurrentStack;
import ShardTools.TaskManager;
import ShardTools.Untyped;
import std.parallelism;
import dap.BuildContext;
import core.atomic;
import ShardTools.ExceptionTools;
import ShardTools.SignaledTask;
import ShardTools.LinkedList;
import std.conv;
import std.typecons;
import std.exception;
import std.array;
import std.string;
import dap.ContentImporter;
import core.thread;
import vibe.vibe;

alias void delegate(Untyped) CompletionTask;

/// Provides a means of building any assets passed in, in parallel.
class AssetBuilder {

	/// Indicates if a build is currently in progress.
	@property final bool buildInProgress() @safe pure nothrow {
		return _buildInProgress;
	}

	/// Builds all assets within the given context using a vibe.d event loop.
	/// When the build completes, the BuildContext will be updated with the appropriate errors and messages.
	final void build(BuildContext context) {
		if(!cas(&_buildInProgress, false, true))
			throw new InvalidOperationException("A new build may not begin until the previous build completes.");
		context.logger.trace("Began build.");
		shared size_t numStarted, numCompleted;
		foreach(AssetStore store_; context.allStores) {
			context.logger.info("Starting build of store " ~ store_.name ~ ".", store_);
			foreach(Asset asset_; store_.allAssets) {
				atomicOp!"+="(numStarted, 1);
				void delegate(Asset) dg = (asset) {
					// Copy to prevent accessing only last asset.
					try {
						StopWatch sw = StopWatch(AutoStart.yes);
						context.logger.trace("Starting build of asset.", asset);
						buildAsset(context, asset);
						sw.stop();
						context.logger.info("Finished building asset in " ~ (cast(Duration)sw.peek).text ~ ".", asset);
					} catch (Exception e) {
						context.logger.error("An exception occurred when building this asset. Details: " ~ e.msg, asset);
						context.logger.trace("\tException details: " ~ e.text.replace("\n", "\n\t"), asset);
					}
					atomicOp!"+="(numCompleted, 1);
				};
				string filterDetails;
				if(isFilteredOut(asset_, filterDetails)) {
					context.logger.info("Skipped build of asset: " ~ filterDetails, asset_);
					atomicOp!"+="(numCompleted, 1);
				} else
					runWorkerTask(&buildAssetWrapper, cast(shared)dg, cast(shared)asset_);
			}
		}
		ptrdiff_t curr = numStarted;
		while(numStarted > numCompleted) {
			// Wait on all tasks to finish. Ideally we'd use a Condition or such, but eh.
			vibe.core.core.yield();
		}
		enforce(cas(&_buildInProgress, true, false));
		context.logger.trace("Finished building all assets (" ~ curr.text ~ "/" ~ numCompleted.text ~ ").");
	}

	/// Adds the given filter to be used when deciding whether to build an asset.
	/// If the filter returns true, the asset is built; if any return false, it is skipped.
	/// The out parameter is used as the details for why the asset is skipped.
	void addFilter(AssetFilter filter) {
		synchronized(this) {
			_filters ~= filter;
		}
	}

	private bool isFilteredOut(Asset asset, out string details) {
		synchronized(this) {
			string filterDetails;
			bool anyMatch = false;
			foreach(filter; _filters) {
				string detail;
				if(!filter(asset, detail)) {
					assert(detail);
					filterDetails ~= detail.replace("\n", "\n\t") ~ "\n";
					anyMatch = true;
				} else
					asset.trace("Filter " ~ filter.text ~ " not filtering out " ~ asset.text);
			}
			details = filterDetails.strip;
			return anyMatch;
		}
	}

	private static void buildAssetWrapper(shared(void delegate(Asset)) runner, shared Asset asset) {
		runner(cast()asset);
	}

	/// Returns an AsyncAction that completes when the given asset is finished building.
	protected void buildAsset(BuildContext context, Asset asset) {
		auto store = asset.root;
		auto processor = asset.createProcessor();
		if(!processor) {
			context.logger.error("Failed to create a content processor for this asset. Ensure a valid processor name is set.", asset);
			return;
		}
		auto importer = processor.createImporter();
		if(!importer) {
			context.logger.error("A valid processor was created, but no importer was able to provide data for it.", asset);
			return;
		}
		auto inputStream = asset.getInputStream();
		scope(exit)
			destroy(inputStream);
		auto importContext = ImportContext(inputStream, asset.extension, processor.inputType, context, asset);
		Untyped importData = importer.process(importContext);
		if(importData == Untyped.init) {
			context.logger.error("Failed to import asset data.", asset);
		} else {
			enforce(importData.type == processor.inputType);
			auto outputStream = asset.getOutputStream();
			scope(exit) {
				outputStream.finalize();
				destroy(outputStream);
			}
			processor.process(importData, outputStream);
		}
	}

private:
	shared bool _buildInProgress;
	AssetFilter[] _filters;
}

/// Represents a filter that is executed to determine whether to build each asset.
/// If any filters return false, the asset is skipped and the out parameter used as the reason.
alias AssetFilter = bool delegate(Asset, out string);