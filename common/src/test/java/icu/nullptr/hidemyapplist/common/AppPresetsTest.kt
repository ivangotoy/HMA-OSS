package icu.nullptr.hidemyapplist.common

import android.content.pm.ApplicationInfo
import android.content.pm.IPackageManager
import icu.nullptr.hidemyapplist.common.app_presets.AccessibilityAppsPreset
import icu.nullptr.hidemyapplist.common.app_presets.RootAppsPreset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.lang.reflect.Proxy
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Package event and boot paths of AppPresets, on a fresh instance with made-up APK files. */
class AppPresetsTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private fun newPresets(): AppPresets =
        AppPresets::class.java.getDeclaredConstructor().apply { isAccessible = true }.newInstance()

    // the package manager is not needed when the caller resolves the app itself
    private val pms = Proxy.newProxyInstance(
        javaClass.classLoader, arrayOf(IPackageManager::class.java)
    ) { _, method, _ -> throw UnsupportedOperationException(method.name) } as IPackageManager

    /** A zip whose AndroidManifest.xml holds [markers] the way binary XML stores strings (UTF-16). */
    private fun apk(name: String, vararg markers: String): File {
        val file = tmp.newFile("$name.apk")
        ZipOutputStream(file.outputStream()).use { zip ->
            zip.putNextEntry(ZipEntry("AndroidManifest.xml"))
            zip.write(markers.joinToString(" ").toByteArray(Charsets.UTF_16BE))
            zip.closeEntry()
        }
        return file
    }

    private fun appInfo(packageName: String, file: File, flags: Int = 0) = ApplicationInfo().apply {
        this.packageName = packageName
        sourceDir = file.path
        publicSourceDir = file.path
        this.flags = flags
    }

    // J10 (a5a7248): the boot reload over the cache forgets apps that are no longer installed
    @Test
    fun bootReloadDropsRemovedAppsFromTheKnownList() {
        val presets = newPresets()
        presets.importCache(PresetCache(allAppsList = mutableSetOf("com.example.kept", "com.example.removed")))

        presets.reloadPresets(listOf(appInfo("com.example.kept", apk("kept"))), fromScratch = false)

        assertEquals(setOf("com.example.kept"), presets.exportCache().allAppsList)
    }

    // J11 (34b579a): an update of an app already in a preset is still checked for a GMS connection
    @Test
    fun packageAlreadyInAPresetIsStillCheckedForGms() {
        val presets = newPresets()
        val pkg = "com.example.inpreset.gms"
        presets.getPresetByName(RootAppsPreset.NAME)!!.packageNames.add(pkg)
        val info = appInfo(pkg, apk("gms", "com.google.android.gms.version"))

        presets.handlePackageAdded(pms, pkg, { info }) { }

        assertTrue(RiskyPackageUtils.instance.appHasGMSConnection(pkg, true))
    }

    // J12 (f01bf17): a system app never joins the accessibility preset on a package event
    @Test
    fun systemAppIsKeptOutOfTheAccessibilityPresetOnPackageEvents() {
        val presets = newPresets()
        val pkg = "com.example.system.a11y"
        val info = appInfo(
            pkg, apk("a11y", "android.permission.BIND_ACCESSIBILITY_SERVICE"),
            ApplicationInfo.FLAG_SYSTEM or ApplicationInfo.FLAG_UPDATED_SYSTEM_APP,
        )

        presets.handlePackageAdded(pms, pkg, { info }) { }

        assertFalse(presets.containsPackage(AccessibilityAppsPreset.NAME, pkg))
    }

    // control for J12: the same manifest from a user app does join the preset
    @Test
    fun userAppWithAnAccessibilityServiceJoinsThePreset() {
        val presets = newPresets()
        val pkg = "com.example.user.a11y"
        val info = appInfo(pkg, apk("usera11y", "android.permission.BIND_ACCESSIBILITY_SERVICE"))

        presets.handlePackageAdded(pms, pkg, { info }) { }

        assertTrue(presets.containsPackage(AccessibilityAppsPreset.NAME, pkg))
    }
}
