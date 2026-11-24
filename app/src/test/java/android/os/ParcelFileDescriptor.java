package android.os;

import java.io.Closeable;

/** Test-only stand-in for android.os.ParcelFileDescriptor that counts close() calls. */
public class ParcelFileDescriptor implements Closeable {
    public int closed;

    public ParcelFileDescriptor() {}

    @Override
    public void close() { closed++; }
}
