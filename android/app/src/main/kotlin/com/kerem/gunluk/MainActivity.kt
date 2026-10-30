package com.kerem.gunluk

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Ekran süresi: Android'in uygulama kullanım istatistikleri (Dijital Denge ile aynı kaynak).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gunluk/usage")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermission" -> result.success(hasUsagePermission())
                    "openSettings" -> {
                        openUsageSettings()
                        result.success(null)
                    }
                    "query" -> {
                        val start = call.argument<Number>("start")!!.toLong()
                        val end = call.argument<Number>("end")!!.toLong()
                        Thread {
                            val data = try {
                                queryUsage(start, end)
                            } catch (e: Exception) {
                                null
                            }
                            runOnUiThread {
                                if (data == null) {
                                    result.error("query", "Kullanım verisi okunamadı", null)
                                } else {
                                    result.success(data)
                                }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasUsagePermission(): Boolean {
        val ops = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        } else {
            ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        }
        if (mode == AppOpsManager.MODE_DEFAULT) {
            return checkCallingOrSelfPermission(android.Manifest.permission.PACKAGE_USAGE_STATS) ==
                PackageManager.PERMISSION_GRANTED
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun openUsageSettings() {
        try {
            // Bazı telefonlar doğrudan bu uygulamanın iznini açar.
            startActivity(
                Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS, Uri.parse("package:$packageName"))
            )
        } catch (e: ActivityNotFoundException) {
            startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
        }
    }

    /** [start, end) aralığında her uygulamanın ön planda kaldığı süre ve açılma sayısı. */
    private fun queryUsage(start: Long, end: Long): List<Map<String, Any>> {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = usm.queryEvents(start, end)
        val total = HashMap<String, Long>()
        val launches = HashMap<String, Int>()
        val openSince = HashMap<String, Long>() // "paket/aktivite" -> ön plana geldiği an
        val seen = HashSet<String>()
        var current: String? = null
        val e = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            val pkg = e.packageName ?: continue
            val key = pkg + "/" + (e.className ?: "")
            when (e.eventType) {
                1 -> { // ACTIVITY_RESUMED (eski adıyla MOVE_TO_FOREGROUND)
                    openSince[key] = e.timeStamp
                    seen.add(key)
                    if (current != pkg) launches[pkg] = (launches[pkg] ?: 0) + 1
                    current = pkg
                }
                2 -> { // ACTIVITY_PAUSED (MOVE_TO_BACKGROUND)
                    val since = openSince.remove(key) ?: if (seen.add(key)) start else null
                    if (since != null) total[pkg] = (total[pkg] ?: 0L) + (e.timeStamp - since)
                }
            }
        }
        // Hâlâ açık olanlar: şu ana (ya da aralık sonuna) kadar say.
        val until = minOf(end, System.currentTimeMillis())
        for ((key, since) in openSince) {
            val pkg = key.substringBefore('/')
            if (until > since) total[pkg] = (total[pkg] ?: 0L) + (until - since)
        }

        val pm = packageManager
        val home = pm.resolveActivity(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME),
            PackageManager.MATCH_DEFAULT_ONLY
        )?.activityInfo?.packageName
        val out = ArrayList<Map<String, Any>>()
        for ((pkg, ms) in total) {
            // Ana ekran ve açılamayan sistem bileşenleri (bildirim paneli vb.) sayılmaz.
            if (ms < 1000 || pkg == home) continue
            if (pm.getLaunchIntentForPackage(pkg) == null) continue
            var label = pkg
            var category = -1
            try {
                val info = pm.getApplicationInfo(pkg, 0)
                label = pm.getApplicationLabel(info).toString()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) category = info.category
                val isGame = (info.flags and ApplicationInfo.FLAG_IS_GAME) != 0
                if (isGame) category = 0 // CATEGORY_GAME
            } catch (e: PackageManager.NameNotFoundException) {
                // etiket bulunamazsa paket adı kalır
            }
            out.add(
                mapOf(
                    "package" to pkg,
                    "label" to label,
                    "category" to category,
                    "ms" to ms,
                    "launches" to (launches[pkg] ?: 0)
                )
            )
        }
        return out
    }
}
