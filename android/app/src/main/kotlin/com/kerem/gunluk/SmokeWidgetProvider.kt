package com.kerem.gunluk

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Calendar
import java.util.Locale

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
            v.setTextViewText(R.id.count, "—")
            v.setTextViewText(R.id.label, "Önce uygulamada Sigara takibi ekle")
            return v
        }

        // Sayı başka bir güne aitse (gece yarısı geçti) bugün henüz 0.
        val cal = Calendar.getInstance()
        val key = String.format(
            Locale.US, "%04d-%02d-%02d",
            cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH)
        )
        val count = if (data.getString("smoke_day", null) == key) data.getString("smoke_today", "0") else "0"
        v.setTextViewText(R.id.count, count)
        v.setTextViewText(R.id.label, "sigara · bugün")
        return v
    }
}
