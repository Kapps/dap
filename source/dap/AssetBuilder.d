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
import dap.ContentImporter;

alias void delegate(Untyped) CompletionTask;

/// Provides a means of building any assets passed in, in parallel.
class AssetBuilder {

	/// Indicates if a build is currently in progress.
	@property final bool buildInProgress() @safe pure nothrow {
		return _buildInProgress;
	}

	/// Asynchronously begins building all assets within the given context.
	/// When the build completes, the BuildContext will be updated with the appropriate errors and messages.
	final AsyncAction build(BuildContext context) {
		if(!cas(&_buildInProgress, false, true))
			throw new InvalidOperationException("A new build may not begin until the previous build completes.");
		context.logger.trace("Began build.");
		shared size_t numStarted, numCompleted;
		auto waitedActions = new LinkedList!(Tuple!(AsyncAction, Asset))();
		auto result = new SignaledTask().Start();
		foreach(AssetStore store; context.allStores) {
			context.logger.trace("Starting build of store " ~ store.name ~ ".", store);
			foreach(Asset asset; store.allAssets) {
				context.logger.trace("Starting build of asset.", asset);
				AsyncAction action;
				try action = buildAsset(context, asset);
				catch (Throwable e) {
					context.logger.error("An exception occurred when building this asset. Details: " ~ e.msg, asset);
					context.logger.trace("Exception details: " ~ e.text, asset);
					action = null;
				}
				if(action) {
					waitedActions.Add(tuple(action, asset));
					atomicOp!"+="(numStarted, 1);
				} else
					context.logger.trace("Skipped build of asset.", asset);
			}
		}
		result.NotifyOnComplete(Untyped.init, delegate(_, __, ___) {
			enforce(cas(&_buildInProgress, true, false));
		});
		foreach(tup; waitedActions) {
			auto action = tup[0];
			auto asset = tup[1];
			action.NotifyOnComplete(Untyped.init, delegate(_, __, status) {
				context.logger.trace("Finished build of asset with status of " ~ status.text ~ ".", asset);
				if(status != CompletionType.Successful) {
					Throwable t;
					if(action.CompletionData.tryGet(t))
						context.logger.error("An exception occurred while building this asset: " ~ t.text, asset);
					else
						context.logger.error("An OutputSource returned a non-exception error while building this asset. Type was " ~ action.CompletionData.type.text ~ ".", asset);
				}
				if(atomicOp!"-="(numStarted, 1) == 0) {
					context.logger.trace("All assets finished; signaling complete.");
					result.SignalComplete(Untyped.init);
					context.logger.trace("Signaled.");
				}
			});
		}
		// Have to special-case no actions since we'll never reach count 0.
		if(waitedActions.Count == 0) {
			context.logger.warn("No assets were scheduled to be built.");
			result.SignalComplete(Untyped.init);
		}
		return result;
	}

	/// Returns an AsyncAction that completes when the given asset is finished building.
	protected AsyncAction buildAsset(BuildContext context, Asset asset) {
		auto store = asset.root;
		auto processor = asset.createProcessor();
		if(!processor) {
			context.logger.error("Failed to create a content processor for this asset. Ensure a valid processor name is set.", asset);
			return null;
		}
		auto importer = processor.createImporter();
		if(!importer) {
			context.logger.error("A valid processor was created, but no importer was able to provide data for it.", asset);
			return null;
		}
		auto inputSource = asset.getInputSource();
		scope(failure) {
			if(inputSource.Action is null || !inputSource.Action.HasBegun)
				inputSource.Close();
		}
		auto result = new SignaledTask().Start();
		// First have to wait for importer to complete.
		AsyncAction importTask;
		ImportContext importContext = ImportContext(inputSource, asset.extension, processor.inputType, context, asset);
		importTask = importer.process(importContext);
		importTask.NotifyOnComplete(Untyped.init, (importState, importAction, importStatus) {
			if(importStatus != CompletionType.Successful) {
				context.logger.error("Failed to import asset data.", asset);
				result.Abort(importTask.CompletionData);
			} else {
				Untyped importData = importTask.CompletionData;
				enforce(importData.type == processor.inputType);
				auto outputSource = asset.getOutputSource();
				scope(failure) {
					if(outputSource.Action is null || !outputSource.Action.HasBegun)
						outputSource.Close();
				}
				AsyncAction procAction;
				try {
					procAction = processor.process(importData, outputSource);
					// Then have to wait to process import data.
					procAction.NotifyOnComplete(Untyped.init, (procState, procAction, procStatus) {
						if(procStatus != CompletionType.Successful) {
							context.logger.error("Failed to process asset.", asset);
							result.Abort(procAction.CompletionData);
						} else {
							result.SignalComplete(procAction.CompletionData);
						}
					});
				} catch(Throwable t) {
					context.logger.error("The content processor threw an exception. Details: " ~ t.msg, asset);
					context.logger.trace("Exception details: " ~ t.text, asset);
					result.Abort(Untyped(t));
				}
			}
		});
		return result;
	}

private:
	shared bool _buildInProgress;
}

