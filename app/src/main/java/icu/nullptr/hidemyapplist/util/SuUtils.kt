package icu.nullptr.hidemyapplist.util

object SuUtils {

    fun execPrivileged(cmd: String): Boolean {
        var exec: Process? = null
        return try {
            exec = Runtime.getRuntime().exec("su -c $cmd")
            exec.waitFor()
            return exec.exitValue() == 0
        } catch (_: Throwable) {
            false
        } finally {
            // closes the process's three pipes
            exec?.destroy()
        }
    }
}
