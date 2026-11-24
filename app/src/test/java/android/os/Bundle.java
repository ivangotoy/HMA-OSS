package android.os;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;

/**
 * Test-only stand-in for android.os.Bundle (the android.jar class is a no-op stub in local unit
 * tests). Holds string arrays in insertion order; only the calls JsonConfigUtils makes.
 */
public final class Bundle {
    private final Map<String, String[]> map = new LinkedHashMap<>();

    public Bundle() {}

    public void putStringArray(String key, String[] value) { map.put(key, value); }

    public String[] getStringArray(String key) { return map.get(key); }

    public Set<String> keySet() { return map.keySet(); }
}
