package icu.nullptr.hidemyapplist.service

import android.os.IBinder
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import java.lang.reflect.Proxy

/** J22 (de3db0e): the service binder's death is linked once, not once per hand-over. */
class ServiceClientTest {
    private class FakeBinder {
        var linked = 0
        var unlinked = 0
        val binder = Proxy.newProxyInstance(javaClass.classLoader, arrayOf(IBinder::class.java)) { _, method, _ ->
            when (method.name) {
                "linkToDeath" -> { linked++; null }
                "unlinkToDeath" -> { unlinked++; true }
                "queryLocalInterface" -> null
                else -> when (method.returnType) {
                    java.lang.Boolean.TYPE -> false
                    Integer.TYPE -> 0
                    else -> null
                }
            }
        } as IBinder
    }

    // ServiceClient is a process-wide object: no fake service stays linked between tests
    @Before
    fun forgetPreviousBinder() = ServiceClient.binderDied()

    @After
    fun forgetFakeBinder() = ServiceClient.binderDied()

    @Test
    fun sameBinderHandedOverAgainIsLinkedOnce() {
        val fake = FakeBinder()
        val provider = ServiceProvider()

        repeat(3) { ServiceClient.linkService(provider, fake.binder) }

        assertEquals(1, fake.linked)
    }

    @Test
    fun newBinderReplacesTheDeathLinkOfTheOldOne() {
        val old = FakeBinder()
        val new = FakeBinder()
        val provider = ServiceProvider()

        ServiceClient.linkService(provider, old.binder)
        ServiceClient.linkService(provider, new.binder)

        assertEquals(1, old.unlinked)
        assertEquals(1, new.linked)
    }
}
