package icu.nullptr.hidemyapplist.service

import android.os.IBinder
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Test
import java.lang.reflect.Proxy

/**
 * Saving the config hands the read end of a pipe to the service, which receives its own copy:
 * this process's descriptor must be closed after the call. The test-source ContentProvider and
 * ParcelFileDescriptor stand-ins are reached by reflection, so this file compiles against
 * android.jar alone.
 */
class ServiceClientConfigTest {
    private val pipeField = Class.forName("android.content.ContentProvider").getField("nextPipe")

    private fun fakeBinder() = Proxy.newProxyInstance(javaClass.classLoader, arrayOf(IBinder::class.java)) { _, method, _ ->
        when (method.returnType) {
            java.lang.Boolean.TYPE -> method.name == "unlinkToDeath"
            Integer.TYPE -> 0
            else -> null
        }
    } as IBinder

    @After
    fun reset() {
        ServiceClient.binderDied()
        pipeField.set(null, null)
    }

    @Test
    fun configPipeIsClosedAfterSendingIt() {
        val pipe = Class.forName("android.os.ParcelFileDescriptor").getConstructor().newInstance()
        pipeField.set(null, pipe)
        ServiceClient.linkService(ServiceProvider(), fakeBinder())

        ServiceClient.config = "{}"

        assertEquals(1, pipe.javaClass.getField("closed").getInt(pipe))
    }
}
