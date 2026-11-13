package com.jeevan.jeevan_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jeevan/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getTimeZoneId" -> result.success(TimeZone.getDefault().id)
                    "speakPrompt" -> {
                        val prompt = call.argument<String>("text")?.trim().orEmpty()
                        if (prompt.isEmpty()) {
                            result.error("empty_prompt", "Speech text is empty", null)
                        } else {
                            val urgent = call.argument<Boolean>("urgent") == true
                            VoicePromptPlayer.speak(
                                applicationContext,
                                prompt,
                                urgent = urgent,
                                onFailure = {
                                    VoicePromptPlayer.fallbackTone(applicationContext)
                                },
                            )
                            result.success(null)
                        }
                    }
                    "syncMedicationVoiceAlarms" -> {
                        val schedules = (call.arguments as? List<*>)
                            ?.mapNotNull { item ->
                                val row = item as? Map<*, *> ?: return@mapNotNull null
                                val id = (row["id"] as? Number)?.toInt() ?: return@mapNotNull null
                                val name = row["name"] as? String ?: return@mapNotNull null
                                val time = row["time"] as? String ?: return@mapNotNull null
                                MedicationVoiceSchedule(id, name, time)
                            }.orEmpty()
                        MedicineVoiceAlarmScheduler.sync(applicationContext, schedules)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

}
// Jeevan sync: 2026-11-13
