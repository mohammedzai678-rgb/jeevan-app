package com.jeevan.jeevan_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.media.ToneGenerator
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.media.AudioAttributes
import android.os.Handler
import android.os.Looper
import android.os.Bundle
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.Locale

internal data class MedicationVoiceSchedule(
    val id: Int,
    val name: String,
    val time: String,
)

internal object MedicineVoiceAlarmScheduler {
    private const val PREFS = "jeevan_local_voice_alerts"
    private const val SCHEDULES = "medication_schedules"
    private const val ACTION_MEDICATION = "com.jeevan.jeevan_app.MEDICATION_VOICE"

    fun sync(context: Context, schedules: List<MedicationVoiceSchedule>) {
        val old = readSchedules(context)
        old.forEach { cancel(context, it) }
        val valid = schedules.filter { it.id > 0 && it.name.isNotBlank() && validTime(it.time) }
        val json = JSONArray()
        valid.forEach { row ->
            json.put(JSONObject().put("id", row.id).put("name", row.name).put("time", row.time))
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(SCHEDULES, json.toString()).apply()
        valid.forEach { scheduleNext(context, it) }
    }

    fun restore(context: Context) {
        readSchedules(context).forEach { scheduleNext(context, it) }
    }

    fun onAlarm(context: Context, schedule: MedicationVoiceSchedule) {
        scheduleNext(context, schedule)
    }

    private fun readSchedules(context: Context): List<MedicationVoiceSchedule> {
        val value = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(SCHEDULES, null) ?: return emptyList()
        return try {
            val json = JSONArray(value)
            (0 until json.length()).mapNotNull { index ->
                val item = json.optJSONObject(index) ?: return@mapNotNull null
                MedicationVoiceSchedule(
                    item.optInt("id"),
                    item.optString("name"),
                    item.optString("time"),
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun scheduleNext(context: Context, schedule: MedicationVoiceSchedule) {
        val parts = schedule.time.split(":")
        val hour = parts.getOrNull(0)?.toIntOrNull() ?: return
        val minute = parts.getOrNull(1)?.toIntOrNull() ?: return
        if (hour !in 0..23 || minute !in 0..59) return

        val calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_YEAR, 1)
        }
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val pending = pendingIntent(context, schedule) ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, calendar.timeInMillis, pending)
            } else {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, calendar.timeInMillis, pending)
            }
        } catch (_: SecurityException) {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, calendar.timeInMillis, pending)
        }
    }

    private fun cancel(context: Context, schedule: MedicationVoiceSchedule) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val pending = pendingIntent(context, schedule) ?: return
        alarmManager.cancel(pending)
    }

    private fun pendingIntent(context: Context, schedule: MedicationVoiceSchedule): PendingIntent? {
        val intent = Intent(context, MedicineVoiceReceiver::class.java).apply {
            action = ACTION_MEDICATION
            putExtra("schedule_id", schedule.id)
            putExtra("medication_name", schedule.name)
            putExtra("medication_time", schedule.time)
        }
        return PendingIntent.getBroadcast(
            context,
            schedule.id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun validTime(value: String): Boolean {
        val pieces = value.split(":")
        val hour = pieces.getOrNull(0)?.toIntOrNull() ?: return false
        val minute = pieces.getOrNull(1)?.toIntOrNull() ?: return false
        return hour in 0..23 && minute in 0..59
    }

}

internal object VoicePromptPlayer {
    private data class Request(
        val id: String,
        val text: String,
        val onFinished: () -> Unit,
        val onFailure: () -> Unit,
        var timeout: Runnable? = null,
    )

    private val handler = Handler(Looper.getMainLooper())
    private val queue = ArrayDeque<Request>()
    private var engine: TextToSpeech? = null
    private var ready = false
    private var speaking: Request? = null
    private var nextId = 1L

    fun speak(
        context: Context,
        phrase: String,
        urgent: Boolean = false,
        onFinished: () -> Unit = {},
        onFailure: () -> Unit = {},
    ) {
        val request = Request("jeevan-voice-${nextId++}", phrase, onFinished, onFailure)
        if (urgent) {
            val interrupted = speaking
            if (interrupted != null) {
                speaking = null
                interrupted.timeout?.let(handler::removeCallbacks)
                engine?.stop()
                interrupted.onFinished()
            }
            queue.addFirst(request)
        } else {
            queue.addLast(request)
        }
        ensureEngine(context.applicationContext)
        flushQueue()
    }

    private fun ensureEngine(context: Context) {
        if (engine != null) return
        engine = TextToSpeech(context) { status ->
            handler.post {
                val tts = engine
                if (status != TextToSpeech.SUCCESS || tts == null) {
                    engine = null
                    ready = false
                    while (queue.isNotEmpty()) {
                        val request = queue.removeFirst()
                        request.onFailure()
                        request.onFinished()
                    }
                    return@post
                }
                val locale = Locale.US
                tts.language = if (tts.isLanguageAvailable(locale) >= TextToSpeech.LANG_AVAILABLE) {
                    locale
                } else {
                    Locale.getDefault()
                }
                tts.setSpeechRate(0.92f)
                tts.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build(),
                )
                tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) = Unit
                    override fun onDone(utteranceId: String?) {
                        handler.post { complete(utteranceId, failed = false) }
                    }
                    override fun onStop(utteranceId: String?, interrupted: Boolean) {
                        handler.post { complete(utteranceId, failed = false) }
                    }
                    @Deprecated("Deprecated in Android API")
                    override fun onError(utteranceId: String?) {
                        handler.post { complete(utteranceId, failed = true) }
                    }
                    override fun onError(utteranceId: String?, errorCode: Int) {
                        handler.post { complete(utteranceId, failed = true) }
                    }
                })
                ready = true
                flushQueue()
            }
        }
    }

    private fun flushQueue() {
        if (!ready || speaking != null || queue.isEmpty()) return
        val tts = engine ?: return
        val request = queue.removeFirst()
        speaking = request
        val params = Bundle().apply {
            putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, request.id)
            putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 1.0f)
        }
        request.timeout = Runnable { complete(request.id, failed = true) }
        handler.postDelayed(request.timeout!!, 15_000)
        if (tts.speak(request.text, TextToSpeech.QUEUE_FLUSH, params, request.id) == TextToSpeech.ERROR) {
            complete(request.id, failed = true)
        }
    }

    private fun complete(id: String?, failed: Boolean) {
        val request = speaking ?: return
        if (id != null && request.id != id) return
        speaking = null
        request.timeout?.let(handler::removeCallbacks)
        if (failed) {
            request.onFailure()
        }
        request.onFinished()
        flushQueue()
    }

    fun fallbackTone(context: Context) {
        val tone = ToneGenerator(AudioManager.STREAM_ALARM, 90)
        tone.startTone(ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 800)
        Handler(Looper.getMainLooper()).postDelayed({ tone.release() }, 1_000)
    }
}

class MedicineVoiceReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("schedule_id", 0)
        val name = intent.getStringExtra("medication_name") ?: "your medicine"
        val time = intent.getStringExtra("medication_time") ?: return
        if (id > 0) {
            val schedule = MedicationVoiceSchedule(id, name, time)
            MedicineVoiceAlarmScheduler.onAlarm(context.applicationContext, schedule)
            val pending = goAsync()
            VoicePromptPlayer.speak(
                context.applicationContext,
                "Take your medicine. $name.",
                onFinished = { pending.finish() },
                onFailure = { VoicePromptPlayer.fallbackTone(context.applicationContext) },
            )
        }
    }
}

class MedicineVoiceBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            MedicineVoiceAlarmScheduler.restore(context.applicationContext)
        }
    }
}
