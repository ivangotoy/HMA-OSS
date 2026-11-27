package android.os;

/**
 * Test-only stand-in for the hidden-API stub android.os.SystemProperties (whose methods throw
 * "STUB"), so code that logs can run in local unit tests. No property is set.
 */
public class SystemProperties {
    public static String get(String key) { return ""; }

    public static boolean getBoolean(String key, boolean def) { return def; }
}
