package icu.nullptr.hidemyapplist.ui.adapter

import org.junit.Assert.assertEquals
import org.junit.Test

/** J18 (02b297a): the level of a log line is the level, whatever the message holds. */
class LogAdapterTest {
    @Test
    fun messageThatLooksLikeALogHeaderDoesNotBecomePartOfTheLevel() {
        val item = LogAdapter.parseLog("[ERROR] <11-24 10:00:00> (ConfigManager) template x] <a> (b) c\n")!!

        assertEquals("ERROR", item.level)
        assertEquals("11-24 10:00:00", item.date)
        assertEquals("ConfigManager", item.tag)
        assertEquals("template x] <a> (b) c\n", item.message)
    }

    @Test
    fun assertLevelIsParsed() {
        val item = LogAdapter.parseLog("[?WTF?] <11-24 10:00:00> (Tag) made-up message\n")!!

        assertEquals("?WTF?", item.level)
        assertEquals("Tag", item.tag)
    }
}
