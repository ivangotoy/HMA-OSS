package org.frknkrc44.hma_oss.ui.fragment

import android.os.Bundle
import icu.nullptr.hidemyapplist.common.settings_presets.ReplacementItem
import org.frknkrc44.hma_oss.ui.adapter.SettingsTemplateListAdapter
import org.frknkrc44.hma_oss.withObserverList
import org.junit.Assert.assertEquals
import org.junit.Test

/** J28 (a14bb68): editing a setting replaces the entry it started from. */
class SettingsTemplateInnerFragmentTest {
    private fun setDelegate(target: Any, name: String, value: Any) {
        target.javaClass.getDeclaredField("$name\$delegate").apply { isAccessible = true }.set(target, lazyOf(value))
    }

    /** Runs the fragment's result handling for an edit of [original] that came back as [edited]. */
    private fun edit(items: MutableList<ReplacementItem>, original: ReplacementItem, edited: ReplacementItem) {
        val fragment = SettingsTemplateInnerFragment()
        val adapter = SettingsTemplateListAdapter(Bundle()) { _, _ -> }.apply { withObserverList() }
        setDelegate(adapter, "items", items)
        setDelegate(fragment, "adapter", adapter)

        val process = SettingsTemplateInnerFragment::class.java.declaredMethods
            .first { it.name == "processIncomingSetting" }.apply { isAccessible = true }
        // the method takes the edited entry, and since the fix also the entry it started from
        if (process.parameterCount == 2) process.invoke(fragment, edited, original) else process.invoke(fragment, edited)
    }

    @Test
    fun renamedSettingReplacesTheOriginal() {
        val x = ReplacementItem("made_up_x", "1", "secure")
        val y = ReplacementItem("made_up_y", "2", "global")
        val items = mutableListOf(x, y)

        edit(items, x, ReplacementItem("made_up_z", "3", "secure"))

        assertEquals(listOf("made_up_z", "made_up_y"), items.map { it.name })
    }

    @Test
    fun renameOntoAnExistingSettingLeavesOneEntry() {
        val x = ReplacementItem("made_up_x", "1", "secure")
        val y = ReplacementItem("made_up_y", "2", "global")
        val items = mutableListOf(x, y)

        edit(items, x, ReplacementItem("made_up_y", "3", "global"))

        assertEquals(listOf(ReplacementItem("made_up_y", "3", "global")), items)
    }
}
