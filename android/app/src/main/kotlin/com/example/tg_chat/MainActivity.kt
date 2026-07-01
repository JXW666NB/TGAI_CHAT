package com.example.tg_chat

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream

class MainActivity : FlutterActivity() {
    private val inferenceChannel = "tg_chat/inference"
    private val generateChannel = "tg_chat/generate"
    private val importChannel = "tg_chat/import"
    private val importProgressChannel = "tg_chat/import_progress"

    private lateinit var inference: TgaiInference
    private var generateSink: EventChannel.EventSink? = null
    private var importProgressSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        inference = TgaiInference(context)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, inferenceChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "loadModel" -> {
                        val prefill = call.argument<String>("prefillPath") ?: ""
                        val decode = call.argument<String>("decodePath") ?: ""
                        val tokenizer = call.argument<String>("tokenizerPath") ?: ""
                        val nCtx = call.argument<Int>("nCtx") ?: 512

                        // 后台线程加载模型，避免主线程阻塞导致 ANR（国产ROM容忍度低）
                        Thread {
                            try {
                                inference.loadModel(prefill, decode, tokenizer, nCtx)
                                runOnUiThread {
                                    result.success(mapOf("success" to true, "nCtx" to nCtx))
                                }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.success(mapOf("success" to false, "error" to (e.message ?: "unknown")))
                                }
                            }
                        }.start()
                    }
                    "unloadModel" -> {
                        inference.unloadModel()
                        result.success(null)
                    }
                    "stopGenerate" -> {
                        inference.stop()
                        result.success(null)
                    }
                    "countTokens" -> {
                        val text = call.argument<String>("text") ?: ""
                        try {
                            val count = inference.countTokens(text)
                            result.success(mapOf("count" to count))
                        } catch (e: Exception) {
                            result.success(mapOf("count" to 0, "error" to e.message))
                        }
                    }
                    "startGenerate" -> {
                        val prompt = call.argument<String>("prompt") ?: ""
                        val temperature = call.argument<Double>("temperature")?.toFloat() ?: 0.8f
                        val topK = call.argument<Int>("topK") ?: 40
                        val topP = call.argument<Double>("topP")?.toFloat() ?: 0.95f
                        val maxTokens = call.argument<Int>("maxTokens") ?: 256
                        val repeatPenalty = call.argument<Double>("repeatPenalty")?.toFloat() ?: 1.1f
                        val repeatLastN = call.argument<Int>("repeatLastN") ?: 64

                        Thread {
                            try {
                                inference.generate(
                                    prompt = prompt,
                                    temperature = temperature,
                                    topK = topK,
                                    topP = topP,
                                    maxTokens = maxTokens,
                                    repeatPenalty = repeatPenalty,
                                    repeatLastN = repeatLastN,
                                    onToken = { token ->
                                        runOnUiThread {
                                            generateSink?.success(mapOf("type" to "token", "text" to token))
                                        }
                                    }
                                )
                                runOnUiThread { generateSink?.success(mapOf("type" to "done")) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    generateSink?.success(mapOf("type" to "error", "error" to (e.message ?: "unknown")))
                                }
                            }
                        }.start()

                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        val mainHandler = Handler(Looper.getMainLooper())
        var importCancelFlag = false

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, importChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "extractTg" -> {
                        val tgPath = call.argument<String>("tgPath") ?: ""
                        val outDir = call.argument<String>("outDir") ?: ""
                        importCancelFlag = false

                        Thread {
                            try {
                                val outcomes = mutableMapOf<String, String>()
                                val tgFile = File(tgPath)
                                val totalSize = tgFile.length()
                                var processed = 0L
                                var lastReportedProgress = -1.0

                                ZipInputStream(FileInputStream(tgFile)).use { zis ->
                                    var entry: ZipEntry? = zis.nextEntry
                                    while (entry != null && !importCancelFlag) {
                                        val name = entry.name

                                        // 安全防护：防止路径穿越 (../../etc)
                                        if (name.contains("..")) {
                                            zis.closeEntry()
                                            entry = zis.nextEntry
                                            continue
                                        }

                                        val outFile = File(outDir, name)
                                        outFile.parentFile?.mkdirs()

                                        FileOutputStream(outFile).use { fos ->
                                            val buffer = ByteArray(65536)
                                            var len: Int
                                            while (zis.read(buffer).also { len = it } != -1 && !importCancelFlag) {
                                                fos.write(buffer, 0, len)
                                                processed += len

                                                // 限制进度更新频率：每 1% 才更新一次
                                                val progress = if (totalSize > 0) (processed.toDouble() / totalSize) else 0.0
                                                if (progress - lastReportedProgress >= 0.01 || progress >= 1.0) {
                                                    lastReportedProgress = progress
                                                    val currentName = name
                                                    val currentProcessed = processed
                                                    mainHandler.post {
                                                        importProgressSink?.success(mapOf(
                                                            "type" to "progress",
                                                            "progress" to progress,
                                                            "file" to currentName,
                                                            "processed" to currentProcessed,
                                                            "total" to totalSize
                                                        ))
                                                    }
                                                }
                                            }
                                        }

                                        when (name) {
                                            "prefill.ptl" -> outcomes["prefill"] = outFile.absolutePath
                                            "decode.ptl" -> outcomes["decode"] = outFile.absolutePath
                                            "tokenizer.json" -> outcomes["tokenizer"] = outFile.absolutePath
                                            "manifest.json" -> outcomes["manifest"] = outFile.absolutePath
                                        }

                                        zis.closeEntry()
                                        entry = zis.nextEntry
                                    }
                                }

                                if (importCancelFlag) {
                                    mainHandler.post {
                                        importProgressSink?.success(mapOf("type" to "cancelled"))
                                    }
                                    return@Thread
                                }

                                mainHandler.post {
                                    importProgressSink?.success(mapOf(
                                        "type" to "done",
                                        "prefill" to (outcomes["prefill"] ?: ""),
                                        "decode" to (outcomes["decode"] ?: ""),
                                        "tokenizer" to (outcomes["tokenizer"] ?: ""),
                                        "manifest" to (outcomes["manifest"] ?: ""),
                                    ))
                                }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    importProgressSink?.success(mapOf(
                                        "type" to "error",
                                        "error" to (e.message ?: "unknown")
                                    ))
                                }
                            }
                        }.start()

                        result.success(null)
                    }
                    "cancelImport" -> {
                        importCancelFlag = true
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, importProgressChannel)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    importProgressSink = events
                }
                override fun onCancel(arguments: Any?) {
                    importProgressSink = null
                }
            })

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, generateChannel)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    generateSink = events
                }

                override fun onCancel(arguments: Any?) {
                    generateSink = null
                }
            })
    }
}
