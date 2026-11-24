package org.frknkrc44.hma_oss.ui.adapter

import androidx.recyclerview.widget.RecyclerView
import icu.nullptr.hidemyapplist.MyApp
import icu.nullptr.hidemyapplist.common.FilterHolder
import org.frknkrc44.hma_oss.withObserverList
import org.junit.Assert.assertTrue
import org.junit.Test

/** J27 (3c1df5c): after a re-sort every row that now shows another app is refreshed. */
class StatAdapterTest {
    private fun count(n: Int) = FilterHolder.FilterCount(packageManagerCount = n)

    @Suppress("UNCHECKED_CAST")
    private fun rows(adapter: StatAdapter) =
        (StatAdapter::class.java.getDeclaredField("logs").apply { isAccessible = true }.get(adapter)
                as List<StatAdapter.StatItem>).map { it.packageName }

    @Test
    fun everyRowWhoseAppChangedIsNotified() {
        // PackageHelper (read by addOrUpdateEntry) needs the application object
        MyApp.hmaApp = MyApp()
        val adapter = StatAdapter { }
        val observers = adapter.withObserverList()
        adapter.addOrUpdateEntry("com.example.b", count(5))
        adapter.addOrUpdateEntry("com.example.a", count(5))
        adapter.addOrUpdateEntry("com.example.c", count(3))

        val notified = mutableSetOf<Int>()
        observers += object : RecyclerView.AdapterDataObserver() {
            override fun onItemRangeChanged(positionStart: Int, itemCount: Int) {
                notified += positionStart until positionStart + itemCount
            }
            override fun onItemRangeChanged(positionStart: Int, itemCount: Int, payload: Any?) =
                onItemRangeChanged(positionStart, itemCount)
            override fun onItemRangeMoved(fromPosition: Int, toPosition: Int, itemCount: Int) {
                notified += fromPosition
                notified += toPosition
            }
            override fun onChanged() {
                notified += 0 until adapter.itemCount
            }
        }
        val before = rows(adapter)

        adapter.addOrUpdateEntry("com.example.c", count(4))

        val after = rows(adapter)
        val changedRows = after.indices.filter { it >= before.size || before[it] != after[it] || after[it] == "com.example.c" }
        assertTrue("changed rows $changedRows, notified $notified", notified.containsAll(changedRows))
    }
}
