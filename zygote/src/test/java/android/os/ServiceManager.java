package android.os;

import java.lang.reflect.Proxy;

/**
 * Test-only stand-in for the hidden-API stub android.os.ServiceManager (whose methods throw
 * "STUB"): every lookup returns a plain binder that implements no service interface, and the
 * thread of the last lookup is kept in lastLookupThread.
 */
public class ServiceManager {
    public static volatile Thread lastLookupThread;

    public static IBinder getService(String name) { return plainBinder(); }

    public static IBinder waitForService(String name) { return plainBinder(); }

    private static IBinder plainBinder() {
        lastLookupThread = Thread.currentThread();
        return (IBinder) Proxy.newProxyInstance(
                ServiceManager.class.getClassLoader(),
                new Class<?>[]{IBinder.class},
                (proxy, method, args) -> {
                    Class<?> type = method.getReturnType();
                    if (type == boolean.class) return false;
                    if (type == int.class) return 0;
                    return null;
                });
    }
}
