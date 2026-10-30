package com.kerem.gunluk

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.Locale

/** Ana ekran "Bugün" widget'ı: sıradaki etkinlik, bugünün listesi ve ✅ butonları. */
class TodayWidgetProvider : HomeWidgetProvider() {
    private val rows = intArrayOf(R.id.row0, R.id.row1, R.id.row2, R.id.row3)
    private val bars = intArrayOf(R.id.bar0, R.id.bar1, R.id.bar2, R.id.bar3)
    private val times = intArrayOf(R.id.time0, R.id.time1, R.id.time2, R.id.time3)
    private val titles = intArrayOf(R.id.title0, R.id.title1, R.id.title2, R.id.title3)
    private val checks = intArrayOf(R.id.check0, R.id.check1, R.id.check2, R.id.check3)

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, build(context, widgetData))
        }
    }

    private fun build(context: Context, data: SharedPreferences): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.widget_today)
        v.setOnClickPendingIntent(
            R.id.root,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("gunluk://open"))
        )
        v.setOnClickPendingIntent(R.id.mic, VoiceActivity.pendingIntent(context))

        val cal = Calendar.getInstance()
        val key = String.format(
            Locale.US, "%04d-%02d-%02d",
            cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH)
        )
        val nowMin = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
        for (r in rows) v.setViewVisibility(r, View.GONE)

        val day = findDay(data.getString("today_json", null), key)
        if (day == null) {
            v.setTextViewText(R.id.date, "")
            v.setTextViewText(R.id.next, "")
            v.setTextViewText(R.id.footer, "")
            v.setViewVisibility(R.id.empty, View.VISIBLE)
            v.setTextViewText(R.id.empty, "Programı görmek için uygulamayı bir kez aç")
            return v
        }
        v.setTextViewText(R.id.date, day.optString("label"))
        val items = day.optJSONArray("items") ?: JSONArray()
        val n = items.length()

        var doneCount = 0
        for (i in 0 until n) if (items.getJSONObject(i).optBoolean("done")) doneCount++

        // Şu an süren ya da sıradaki (tamamlanmamış) etkinlik.
        var next = ""
        for (i in 0 until n) {
            val o = items.getJSONObject(i)
            if (o.optBoolean("done")) continue
            val s = o.optInt("start")
            val e = o.optInt("end")
            if (s <= nowMin && nowMin < e) {
                next = "▶ Şimdi: " + o.optString("title")
                break
            }
            if (s > nowMin) {
                next = "⏭ Sıradaki: " + o.optString("title") + " · " + hm(s)
                break
            }
        }
        if (next.isEmpty() && n > 0) {
            next = if (doneCount == n) "🎉 Bugünkü her şey tamam" else "☑ Kalanları işaretlemeyi unutma"
        }
        v.setTextViewText(R.id.next, next)

        if (n == 0) {
            v.setViewVisibility(R.id.empty, View.VISIBLE)
            v.setTextViewText(R.id.empty, "Bugün program boş · 🎙️ ile ekle")
        } else {
            v.setViewVisibility(R.id.empty, View.GONE)
        }

        // Satırlar: süren ya da sıradaki ilk etkinlikten başlar, sığmayanlar için geri kayar.
        var first = 0
        while (first < n && items.getJSONObject(first).optInt("end") <= nowMin) first++
        if (first > n - rows.size) first = maxOf(0, n - rows.size)
        for (k in rows.indices) {
            val idx = first + k
            if (idx >= n) break
            val o = items.getJSONObject(idx)
            val done = o.optBoolean("done")
            v.setViewVisibility(rows[k], View.VISIBLE)
            v.setInt(bars[k], "setBackgroundColor", o.optInt("color", RED))
            v.setTextViewText(times[k], hm(o.optInt("start")))
            v.setTextViewText(titles[k], o.optString("title"))
            v.setTextColor(titles[k], if (done) GREY else WHITE)
            v.setTextViewText(checks[k], if (done) "✅" else "⬜")
            v.setOnClickPendingIntent(
                checks[k],
                HomeWidgetBackgroundIntent.getBroadcast(
                    context, Uri.parse("gunluk://done?id=" + o.optInt("id") + "&day=" + key)
                )
            )
        }

        v.setTextViewText(
            R.id.footer,
            when {
                n == 0 -> ""
                n > rows.size -> "$doneCount/$n tamamlandı · tümü için dokun"
                else -> "$doneCount/$n tamamlandı"
            }
        )
        return v
    }

    private fun findDay(json: String?, key: String): JSONObject? {
        if (json == null) return null
        return try {
            val arr = JSONArray(json)
            var found: JSONObject? = null
            for (i in 0 until arr.length()) {
                val d = arr.getJSONObject(i)
                if (d.optString("date") == key) found = d
            }
            found
        } catch (e: Exception) {
            null
        }
    }

    private fun hm(m: Int): String =
        String.format(Locale.US, "%02d:%02d", (m / 60) % 24, m % 60)

    companion object {
        private const val RED = -0x1ac6cb // 0xFFE53935
        private const val WHITE = -0x1 // 0xFFFFFFFF
        private const val GREY = -0x7a7a7b // 0xFF858585
    }
}
