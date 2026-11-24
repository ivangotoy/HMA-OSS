package org.frknkrc44.hma_oss.zygote.util

import org.frknkrc44.hma_oss.zygote.util.FileWriteUtils.replaceWith
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.nio.file.Files
import java.nio.file.attribute.BasicFileAttributes

/** J1 (b30093a): service files are replaced by a complete temp file renamed over them. */
class FileWriteUtilsTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private fun fileKey(file: File): Any =
        Files.readAttributes(file.toPath(), BasicFileAttributes::class.java).fileKey()

    @Test
    fun replacesTheFileByARenameAndLeavesNoTempFile() {
        val target = File(tmp.root, "status.json").apply { writeText("{\"workMode\":3}") }

        for ((i, sync) in listOf(true, false).withIndex()) {
            // a second link keeps the old inode alive, so its number cannot be handed out again
            Files.createLink(File(tmp.root, "old$i").toPath(), target.toPath())
            val before = fileKey(target)

            assertTrue(target.replaceWith("{\"workMode\":$i}".toByteArray(), sync))

            assertEquals("{\"workMode\":$i}", target.readText())
            // a new inode: the old file was never truncated and rewritten in place
            assertNotEquals(before, fileKey(target))
            assertFalse(File(tmp.root, "status.json.tmp").exists())
        }
    }

    @Test
    fun failedRenameKeepsTheTargetAndRemovesTheTempFile() {
        // a non-empty directory as the target: the rename over it fails
        val target = File(tmp.root, "config.json").apply { mkdir() }
        File(target, "keep").writeText("old")

        assertFalse(target.replaceWith("{}".toByteArray()))

        assertTrue(target.isDirectory)
        assertEquals("old", File(target, "keep").readText())
        assertFalse(File(tmp.root, "config.json.tmp").exists())
    }
}
