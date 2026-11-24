package org.frknkrc44.hma_oss.zygote.util

import java.io.File
import java.io.FileOutputStream

object FileWriteUtils {
    /**
     * Replaces this file with [bytes] without leaving a partial file behind: the bytes go to
     * "<name>.tmp" in the same directory and are renamed over this file, so a reader (or the
     * next boot after a crash) sees either the old or the new content. With [sync] the bytes
     * reach the disk before the rename, so a power loss cannot leave an empty file either.
     * Writers of one file must be serialized by the caller. Returns false, with this file
     * untouched and no temp file left, when the rename fails; a failed write throws.
     */
    fun File.replaceWith(bytes: ByteArray, sync: Boolean = true): Boolean {
        val temp = File("$path.tmp")
        try {
            FileOutputStream(temp).use {
                it.write(bytes)
                if (sync) it.fd.sync()
            }
            if (temp.renameTo(this)) return true
        } catch (cause: Throwable) {
            temp.delete()
            throw cause
        }
        temp.delete()
        return false
    }
}
