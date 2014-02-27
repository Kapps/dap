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
		foreach(AssetStore store; context.allStores) {
			context.logger.trace("Starting build of store " ~ store.name ~ ".", store);
			foreach(Asset asset; store.allAssets) {
				atomicOp!"+="(numStarted, 1);
				try {
					context.logger.trace("Starting build of asset.", asset);
					buildAsset(context, asset);
					context.logger.trace("Finished build of asset", asset);
				} catch (Exception e) {
					context.logger.error("An exception occurred when building this asset. Details: " ~ e.msg, asset);
					context.logger.info("\tException details: " ~ e.text.replace("\n", "\n\t"), asset);
				}
				atomicOp!"+="(numCompleted, 1);
			}
		}
		while(numStarted < numCompleted) {
			// Wait on vibe.d event loop to finish.
			// TODO: Implement this properly.
			Thread.sleep(5.msecs);
		}
		enforce(cas(&_buildInProgress, true, false));
		context.logger.trace("Finished building all assets.");
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
}
