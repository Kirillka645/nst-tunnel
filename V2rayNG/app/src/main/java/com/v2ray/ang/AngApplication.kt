package com.v2ray.ang

import android.content.Context
import android.os.Build
import android.util.Log
import androidx.multidex.MultiDexApplication
import androidx.work.Configuration
import androidx.work.WorkManager
import com.tencent.mmkv.MMKV
import com.v2ray.ang.AppConfig.ANG_PACKAGE
import com.v2ray.ang.handler.SettingsManager
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter

class AngApplication : MultiDexApplication() {
    companion object {
        lateinit var application: AngApplication
        private const val TAG = "NSTCrash"
    }

    /**
     * Attaches the base context to the application.
     * @param base The base context.
     */
    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        application = this
    }

    private val workManagerConfiguration: Configuration = Configuration.Builder()
        .setDefaultProcessName("${ANG_PACKAGE}:bg")
        .build()

    /**
     * Initializes the application.
     */
    override fun onCreate() {
        super.onCreate()
        installCrashLogger()

        MMKV.initialize(this)

        // Initialize WorkManager with the custom configuration
        WorkManager.initialize(this, workManagerConfiguration)

        // Ensure critical preference defaults are present in MMKV early
        SettingsManager.initApp(this)
        SettingsManager.setNightMode()

        es.dmoral.toasty.Toasty.Config.getInstance()
            .setGravity(android.view.Gravity.BOTTOM, 0, 300)
            .apply()
    }

    /** Write uncaught exceptions to app files so BlueStacks/ADB can pull them. */
    private fun installCrashLogger() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                val sw = StringWriter()
                error.printStackTrace(PrintWriter(sw))
                val text = buildString {
                    appendLine("time=${System.currentTimeMillis()}")
                    appendLine("thread=${thread.name}")
                    appendLine("sdk=${Build.VERSION.SDK_INT} abi=${Build.SUPPORTED_ABIS.joinToString()}")
                    appendLine("model=${Build.MODEL} brand=${Build.BRAND}")
                    appendLine(sw.toString())
                }
                Log.e(TAG, text)
                val dir = getExternalFilesDir(null) ?: filesDir
                File(dir, "nst_crash.txt").writeText(text)
            } catch (_: Exception) {
            }
            previous?.uncaughtException(thread, error)
        }
    }
}
