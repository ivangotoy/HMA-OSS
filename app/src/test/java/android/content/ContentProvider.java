package android.content;

import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.os.ParcelFileDescriptor;

/**
 * Test-only stand-in for android.content.ContentProvider (the android.jar class is a no-op stub in
 * local unit tests, so openPipeHelper would return null). openPipeHelper hands out the descriptor
 * a test puts into nextPipe; the writer callback is not run.
 */
public abstract class ContentProvider {
    public static ParcelFileDescriptor nextPipe;

    public interface PipeDataWriter<T> {
        void writeDataToPipe(ParcelFileDescriptor output, Uri uri, String mimeType, Bundle opts, T args);
    }

    public ContentProvider() {}

    public abstract boolean onCreate();

    public abstract Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder);

    public abstract String getType(Uri uri);

    public abstract Uri insert(Uri uri, ContentValues values);

    public abstract int delete(Uri uri, String selection, String[] selectionArgs);

    public abstract int update(Uri uri, ContentValues values, String selection, String[] selectionArgs);

    public Bundle call(String method, String arg, Bundle extras) { return null; }

    public final String getCallingPackage() { return null; }

    public <T> ParcelFileDescriptor openPipeHelper(Uri uri, String mimeType, Bundle opts, T args, PipeDataWriter<T> func) {
        return nextPipe;
    }
}
