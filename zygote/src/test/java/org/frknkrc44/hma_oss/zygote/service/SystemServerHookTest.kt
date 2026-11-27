package org.frknkrc44.hma_oss.zygote.service

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import java.util.Collections

/**
 * K1: a failed package manager lookup in the init thread stays inside that thread's error
 * handling instead of escaping it as an uncaught exception. The test-source ServiceManager
 * stand-in returns a binder that is no IPackageManager.
 */
class SystemServerHookTest {
    @Test
    fun failedServiceLookupDoesNotEscapeTheInitThread() {
        val uncaught = Collections.synchronizedList(mutableListOf<Throwable>())
        val oldHandler = Thread.getDefaultUncaughtExceptionHandler()
        val before = Thread.getAllStackTraces().keys
        try {
            Thread.setDefaultUncaughtExceptionHandler { _, e -> uncaught += e }
            // a known class loader skips the wait for the system server's class loader
            SystemServerHook.classLoader = javaClass.classLoader

            SystemServerHook.init()

            // the init thread: started by init(), running SystemServerHook code
            // (it waits 250 ms before its first lookup below Android 11, which the JVM reports as SDK 0)
            var started = emptySet<Thread>()
            for (i in 0 until 100) {
                started = (Thread.getAllStackTraces() - before).filterValues { stack ->
                    stack.any { it.className.startsWith(SystemServerHook::class.java.name) }
                }.keys
                if (started.isNotEmpty()) break
                Thread.sleep(10)
            }
            assertEquals("init threads", 1, started.size)
            started.single().join(10_000)
            assertFalse("init thread still running", started.single().isAlive)
        } finally {
            Thread.setDefaultUncaughtExceptionHandler(oldHandler)
            SystemServerHook.classLoader = null
        }

        assertEquals(emptyList<Throwable>(), uncaught.toList())
    }
}
