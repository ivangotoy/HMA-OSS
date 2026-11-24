package org.frknkrc44.hma_oss

import androidx.recyclerview.widget.RecyclerView

/**
 * RecyclerView.Adapter keeps its observers in an android.database.Observable, whose list the
 * android.jar stub never creates (and whose registerObserver is a stub): give it a list so notify
 * calls work on the JVM, and return that list for adding observers.
 */
fun RecyclerView.Adapter<*>.withObserverList(): MutableList<RecyclerView.AdapterDataObserver> {
    val observable = RecyclerView.Adapter::class.java.getDeclaredField("mObservable")
        .apply { isAccessible = true }.get(this)
    val observers = ArrayList<RecyclerView.AdapterDataObserver>()
    android.database.Observable::class.java.getDeclaredField("mObservers")
        .apply { isAccessible = true }.set(observable, observers)
    return observers
}
