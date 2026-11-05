package com.kerem.gunluk

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Ana ekran "Sigara içtim" widget'ı: dokununca uygulama açılmadan arka planda kaydeder. */
class SmokeWidgetProvider : HomeWidgetProvider() {
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
        val v = RemoteViews(context.packageName, R.layout.widget_smoke)
        v.setOnClickPendingIntent(
            R.id.root,
            HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("gunluk://smoke"))
        )

        if (!data.getBoolean("smoke_has_tracker", false)) {
            v.setViewVisibility(R.id.since, View.GONE)
            v.setViewVisibility(R.id.empty, View.VISIBLE)
            v.setTextViewText(R.id.today, "Önce uygulamada Sigara takibi ekle")
            return v
        }

        // Son sigaradan beri geçen süre: widget kendi kendine saymaya devam eder.
        val last = data.getString("smoke_last", null)?.toLongOrNull()
        if (last == null) {
            v.setViewVisibility(R.id.since, View.GONE)
            v.setViewVisibility(R.id.empty, View.VISIBLE)
        } else {
            val elapsed = maxOf(0L, System.currentTimeMillis() - last)
            v.setViewVisibility(R.id.empty, View.GONE)
            v.setViewVisibility(R.id.since, View.VISIBLE)
            v.setChronometer(R.id.since, SystemClock.elapsedRealtime() - elapsed, null, true)
        }
        val today = data.getString("smoke_today", "0")
        v.setTextViewText(R.id.today, "Bugün: $today")
        return v
    }
}
