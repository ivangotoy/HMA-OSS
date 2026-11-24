package org.frknkrc44.hma_oss.zygote.hook

import android.app.usage.UsageEvents
import android.app.usage.UsageStats
import android.content.pm.ParceledListSlice
import android.os.Build
import org.frknkrc44.hma_oss.zygote.service.ReturnValue
import org.frknkrc44.hma_oss.zygote.util.CollectionUtils.firstOrNullWithType
import org.frknkrc44.hma_oss.zygote.util.CollectionUtils.lastOrNullWithType
import org.frknkrc44.hma_oss.zygote.util.Logcat.logD
import org.frknkrc44.hma_oss.zygote.util.Logcat.logI
import org.frknkrc44.hma_oss.zygote.util.ZLUtils.dumpArgs
import org.frknkrc44.hma_oss.zygote.util.ZLUtils.getObjectField
import org.frknkrc44.hma_oss.zygote.util.ZygoteConstants.USAGE_STATS_BINDER_SERVICE_CLASS
import java.util.concurrent.atomic.AtomicReference

class UsageStatsHook : IFrameworkHook {
    override val TAG = "UsageStatsHook"

    @PublishedApi
    internal val lastFilteredApp: AtomicReference<String?> = AtomicReference(null)

    override fun load() {
        logI(TAG) { "Load hook" }

        hooker.apply {
            hookAfter(
                USAGE_STATS_BINDER_SERVICE_CLASS,
                "queryUsageStats",
            ) { methodName, frame, returnValue ->
                @Suppress("UNCHECKED_CAST")
                val result = returnValue.result as? ParceledListSlice<UsageStats> ?: return@hookAfter

                val args = frame.dumpArgs()
                val caller = args.lastOrNullWithType<String>() ?: return@hookAfter
                val isHookEnabled = service.isHookEnabled(caller)
                if (!isHookEnabled) return@hookAfter

                logD(TAG) { "@$methodName: $caller requested stats" }

                val filtered = result.list.filterTo(mutableListOf()) {
                    !service.shouldHide(caller, it.packageName)
                }

                val count = result.list.size - filtered.size
                if (count > 0) {
                    val last = lastFilteredApp.getAndSet(caller)
                    if (last != caller) logI(TAG) { "@$methodName: query from $caller" }
                    logD(TAG) { "@$methodName: $count entries hidden from $caller" }

                    service.increasePMFilterCount(caller, count)

                    returnValue.result = ParceledListSlice(filtered)
                }
            }

            val helperMethod = "queryEventsHelper"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
                hookAfter(
                    USAGE_STATS_BINDER_SERVICE_CLASS,
                    helperMethod,
                ) { methodName, frame, returnValue ->
                    val result = returnValue.result as? UsageEvents ?: return@hookAfter
                    val args = frame.dumpArgs()

                    applyUsageEventsHiding(
                        methodName,
                        returnValue,
                    ) { args.firstOrNullWithType() }
                }
            }

            if (!isHookAvailable(USAGE_STATS_BINDER_SERVICE_CLASS, helperMethod)) {
                hookAfter(
                    USAGE_STATS_BINDER_SERVICE_CLASS,
                    "queryEvents",
                ) { methodName, frame, returnValue ->
                    val result = returnValue.result as? UsageEvents ?: return@hookAfter
                    val args = frame.dumpArgs()

                    applyUsageEventsHiding(
                        methodName,
                        returnValue,
                    ) { args.firstOrNullWithType() }
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
                    hookAfter(
                        USAGE_STATS_BINDER_SERVICE_CLASS,
                        "queryEventsWithFilter",
                    ) { methodName, frame, returnValue ->
                        val result = returnValue.result as? UsageEvents ?: return@hookAfter
                        val args = frame.dumpArgs()

                        applyUsageEventsHiding(
                            methodName,
                            returnValue,
                        ) { args.firstOrNullWithType() }
                    }
                }

                hookAfter(
                    USAGE_STATS_BINDER_SERVICE_CLASS,
                    "queryEventsForUser",
                ) { methodName, frame, returnValue ->
                    val result = returnValue.result as? UsageEvents ?: return@hookAfter
                    val args = frame.dumpArgs()

                    applyUsageEventsHiding(
                        methodName,
                        returnValue,
                    ) { args.firstOrNullWithType() }
                }
            }

            hookAfter(
                USAGE_STATS_BINDER_SERVICE_CLASS,
                "queryEventsForPackageForUser",
            ) { methodName, frame, returnValue ->
                val result = returnValue.result as? UsageEvents ?: return@hookAfter
                val args = frame.dumpArgs()

                applyUsageEventsHiding(
                    methodName,
                    returnValue,
                ) { args.lastOrNullWithType() }
            }
        }
    }

    @Suppress("UNCHECKED_CAST")
    private inline fun applyUsageEventsHiding(
        methodName: String,
        returnValue: ReturnValue,
        getCaller: () -> String?,
    ) {
        val events = returnValue.result as? UsageEvents ?: return
        val eventsList = getObjectField(events, "mEventsToWrite") as? List<UsageEvents.Event> ?: return

        val caller = getCaller() ?: return
        val isHookEnabled = service.isHookEnabled(caller)
        if (!isHookEnabled) return

        // task roots are sent only when the service included them; a kept event must not name a hidden one
        val includeTaskRoots = getObjectField(events, "mIncludeTaskRoots") as? Boolean ?: false
        val filtered = eventsList.filterTo(mutableListOf()) {
            !service.shouldHide(caller, it.packageName) && !(includeTaskRoots &&
                    service.shouldHide(caller, getObjectField(it, "mTaskRootPackage") as? String))
        }

        val count = eventsList.size - filtered.size
        if (count > 0) {
            // a new object, not a new list in the old one: its event count and the string pool sent
            // with the events have to match the kept events (every string they reference, no other)
            val pool = sortedSetOf<String>()
            val fields = if (includeTaskRoots) {
                arrayOf("mPackage", "mClass", "mTaskRootPackage", "mTaskRootClass")
            } else {
                arrayOf("mPackage", "mClass")
            }
            filtered.forEach { event ->
                fields.forEach { field -> (getObjectField(event, field) as? String)?.let(pool::add) }
            }
            val rebuilt = UsageEvents::class.java.getConstructor(
                List::class.java,
                Array<String>::class.java,
                Boolean::class.javaPrimitiveType,
            ).newInstance(filtered, pool.toTypedArray(), includeTaskRoots)

            val last = lastFilteredApp.getAndSet(caller)
            if (last != caller) logI(TAG) { "@$methodName: query from $caller" }
            logD(TAG) { "@$methodName: $count entries hidden from $caller" }

            service.increasePMFilterCount(caller, count)

            returnValue.result = rebuilt
        }
    }
}
