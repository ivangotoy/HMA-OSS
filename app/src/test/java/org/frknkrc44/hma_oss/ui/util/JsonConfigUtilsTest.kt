package org.frknkrc44.hma_oss.ui.util

import icu.nullptr.hidemyapplist.common.settings_presets.ReplacementItem
import org.frknkrc44.hma_oss.ui.util.JsonConfigUtils.targetSettingListToBundle
import org.frknkrc44.hma_oss.ui.util.JsonConfigUtils.toTargetSettingList
import org.junit.Assert.assertEquals
import org.junit.Test

class JsonConfigUtilsTest {
    @Test
    fun sameNameInTwoDatabasesSurvivesTheBundleRoundTrip() {
        val items = listOf(
            ReplacementItem("example_setting", "1", "global"),
            ReplacementItem("example_setting", "0", "secure"),
        )
        val back = items.targetSettingListToBundle().toTargetSettingList()
        assertEquals(
            items.map { Triple(it.name, it.value, it.database) }.toSet(),
            back.map { Triple(it.name, it.value, it.database) }.toSet(),
        )
    }
}
