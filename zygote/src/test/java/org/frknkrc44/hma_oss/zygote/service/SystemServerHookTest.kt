package org.frknkrc44.hma_oss.zygote.service

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Test
import java.util.Collections

/**
 * K1: a failed package manager lookup in the init thread stays inside that thread's error
 * handling instead of escaping it as an uncaught exception. The test-source ServiceManager
 * stand-in returns a binder that is no IPackageManager and records the thread that looked it up
 * (reached by reflection, so this file compiles against the stub module alone).
 */
class SystemServerHookTest {
    private val lookupThread = Class.forName("android.os.ServiceManager").getField("lastLookupThread")

    @Test
    fun failedServiceLookupDoesNotEscapeTheInitThread() {
        val uncaught = Collections.synchronizedList(mutableListOf<Throwable>())
        val oldHandler = Thread.getDefaultUncaughtExceptionHandler()
        try {
            lookupThread.set(null, null)
            Thread.setDefaultUncaughtExceptionHandler { _, e -> uncaught += e }
            // a known class loader skips the wait for the system server's class loader
            SystemServerHook.classLoader = javaClass.classLoader

            SystemServerHook.init()

            // the init thread waits 250 ms before its first lookup below Android 11 (the JVM reports SDK 0)
            val deadline = System.currentTimeMillis() + 10_000
            while (lookupThread.get(null) == null && System.currentTimeMillis() < deadline) Thread.sleep(10)
            val initThread = lookupThread.get(null) as Thread?
            assertNotNull("no service lookup from the init thread", initThread)
            initThread!!.join(10_000)
            assertFalse("init thread still running", initThread.isAlive)
        } finally {
            Thread.setDefaultUncaughtExceptionHandler(oldHandler)
            SystemServerHook.classLoader = null
            lookupThread.set(null, null)
        }

        assertEquals(emptyList<Throwable>(), uncaught.toList())
    }
}
