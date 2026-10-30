package com.kerem.gunluk

import android.app.Activity
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.speech.RecognizerIntent
import android.widget.Toast
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/**
 * Widget'taki 🎙️: uygulamayı açmadan Android'in ses tanıma penceresini gösterir,
 * söyleneni arka planda Dart'a (gunluk://add) gönderir. Sonuç bildirimle gelir.
 * Telefonda ses tanıma yoksa uygulamadaki ses penceresi açılır.
 */
class VoiceActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState != null) return // döndürmede yeniden başlatma
        val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "tr-TR")
            putExtra(RecognizerIntent.EXTRA_PROMPT, "Ne ekleyeyim? Örn: yarın 9'da spor")
        }
        try {
            startActivityForResult(i, REQUEST)
        } catch (e: ActivityNotFoundException) {
            openApp()
            finish()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val text = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
        if (requestCode == REQUEST && resultCode == RESULT_OK && !text.isNullOrBlank()) {
            try {
                HomeWidgetBackgroundIntent.getBroadcast(
                    this, Uri.parse("gunluk://add?text=" + Uri.encode(text))
                ).send()
                Toast.makeText(this, "🎙️ \"$text\"", Toast.LENGTH_SHORT).show()
            } catch (e: Exception) {
                openApp()
            }
        }
        finish()
    }

    private fun openApp() {
        try {
            HomeWidgetLaunchIntent.getActivity(
                this, MainActivity::class.java, Uri.parse("gunluk://voice")
            ).send()
        } catch (e: Exception) {
        }
    }

    companion object {
        private const val REQUEST = 7

        /** Widget'taki mikrofon için: uygulamayı açmadan sesli ekleme. */
        fun pendingIntent(context: Context): PendingIntent = PendingIntent.getActivity(
            context,
            REQUEST,
            Intent(context, VoiceActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }
}
