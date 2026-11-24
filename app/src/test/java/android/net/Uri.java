package android.net;

/** Test-only stand-in for android.net.Uri (the android.jar parse() returns null in local unit tests). */
public abstract class Uri {
    public static Uri parse(String uriString) {
        return new Uri() {
            @Override
            public String toString() { return uriString; }
        };
    }
}
