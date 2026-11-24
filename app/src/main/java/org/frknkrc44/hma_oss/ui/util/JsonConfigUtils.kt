package org.frknkrc44.hma_oss.ui.util

import android.os.Bundle
import icu.nullptr.hidemyapplist.common.settings_presets.ReplacementItem

object JsonConfigUtils {
    fun Collection<ReplacementItem>.targetSettingListToBundle() = Bundle().apply {
        forEach { item ->
            // keyed by database and name: one name can be set in more than one database
            putStringArray("${item.database}/${item.name}", arrayOf(item.value, item.database, item.name))
        }
    }

    fun Bundle.toTargetSettingList() = keySet().mapNotNull {
        val item = getStringArray(it) ?: return@mapNotNull null
        // a two-element value is keyed by the name alone (EditSettingFragment's result)
        ReplacementItem(item.getOrNull(2) ?: it, item[0], item[1])
    }
}
