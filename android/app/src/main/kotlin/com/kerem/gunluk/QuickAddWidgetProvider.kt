package com.kerem.gunluk

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/** Ana ekran "Hızlı ekle" widget'ı: dokununca uygulama açılmadan sesle ekler. */
class QuickAddWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (id in appWidgetIds) {
            val v = RemoteViews(context.packageName, R.layout.widget_quick)
            v.setOnClickPendingIntent(R.id.root, VoiceActivity.pendingIntent(context))
            appWidgetManager.updateAppWidget(id, v)
        }
    }
}
