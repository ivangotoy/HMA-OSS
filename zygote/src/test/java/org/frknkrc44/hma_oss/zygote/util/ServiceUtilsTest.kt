package org.frknkrc44.hma_oss.zygote.util

import org.junit.Assert.assertEquals
import org.junit.Test

/** J34 (b113871): a rethrown original exception does not show the reflective call of the hook. */
class ServiceUtilsTest {
    @Test
    fun clearStackTracesDropsTheReflectiveCallFrame() {
        val error = SecurityException("made-up").apply {
            stackTrace = arrayOf(
                StackTraceElement("com.android.server.pm.ComputerEngine", "enforceCrossUserPermission", "ComputerEngine.java", 1),
                StackTraceElement("java.lang.reflect.Method", "invoke", "Method.java", -2),
                StackTraceElement("com.android.server.pm.PackageManagerService", "getPackageInfo", "PackageManagerService.java", 2),
            )
        }

        ServiceUtils.clearStackTraces(error)

        assertEquals(
            listOf("enforceCrossUserPermission", "getPackageInfo"),
            error.stackTrace.map { it.methodName },
        )
    }
}
