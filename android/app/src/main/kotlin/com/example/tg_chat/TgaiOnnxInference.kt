package com.example.tg_chat

import android.content.Context
import android.os.Build
import ai.onnxruntime.*
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.*

/**
 * 执行提供器模式
 * - AUTO:     自动选择最优（NNAPI > ACL > CPU）
 * - NNAPI:    Android NNAPI（可能走 NPU/DSP/GPU，速度最快但兼容性差）
 * - CPU_ACL:  ARM Compute Library + XNNPACK（稳定，当前默认）
 * - CPU_ONLY: 纯 XNNPACK（最大兼容性，部分手机 ACL 有 bug 时的底牌）
 */
enum class ExecutionProvider {
    AUTO, NNAPI, CPU_ACL, CPU_ONLY;

    companion object {
        fun fromString(s: String?): ExecutionProvider = when (s?.lowercase()) {
            "nnapi" -> NNAPI
            "cpu_acl" -> CPU_ACL
            "cpu_only" -> CPU_ONLY
            else -> AUTO
        }
    }
}

class TgaiOnnxInference {

    private var env: OrtEnvironment? = null
    private var session: OrtSession? = null
    private var tokenizer: TgaiTokenizer? = null

    private var nCtx: Int = 512
    private var vocabSize: Int = 0
    private var activeProvider: String = "unknown"

    @Volatile
    private var stopRequested: Boolean = false

    /**
     * 获取设备信息（芯片型号、核心数、架构等）
     * 供 Flutter 端展示
     */
    fun getDeviceInfo(): Map<String, Any> {
        val socModel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (Build.SOC_MODEL ?: "unknown")
        } else "unknown"
        val socMfr = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (Build.SOC_MANUFACTURER ?: "unknown")
        } else "unknown"
        val cores = Runtime.getRuntime().availableProcessors()
        val abis = Build.SUPPORTED_ABIS?.joinToString(", ") ?: "unknown"

        // 判断芯片厂商，给出推荐
        val recommended: String = when {
            socMfr.lowercase().contains("qualcomm") || socModel.lowercase().contains("snapdragon") -> "NNAPI"
            socMfr.lowercase().contains("mediatek") || socModel.lowercase().contains("dimensity") -> "NNAPI"
            socMfr.lowercase().contains("samsung") || socModel.lowercase().contains("exynos") -> "NNAPI"
            socMfr.lowercase().contains("hisilicon") || socModel.lowercase().contains("kirin") -> "NNAPI"
            else -> "CPU_ACL"
        }

        return mapOf(
            "manufacturer" to (Build.MANUFACTURER ?: "unknown"),
            "model" to (Build.MODEL ?: "unknown"),
            "hardware" to (Build.HARDWARE ?: "unknown"),
            "soc_manufacturer" to socMfr,
            "soc_model" to socModel,
            "cores" to cores,
            "arch" to abis,
            "recommended" to recommended,
            "sdk" to Build.VERSION.SDK_INT,
        )
    }

    /**
     * 加载模型，支持多种执行提供器
     *
     * @param providerMode 执行提供器模式（auto/nnapi/cpu_acl/cpu_only）
     * @param nThreads 线程数，0=自动
     */
    fun loadModel(
        context: Context,
        modelPath: String,
        tokenizerPath: String,
        nCtx: Int,
        providerMode: String = "auto",
        nThreads: Int = 0,
    ) {
        this.nCtx = nCtx
        tokenizer = TgaiTokenizer(context, tokenizerPath)
        vocabSize = tokenizer!!.vocabSize

        env = OrtEnvironment.getEnvironment()
        val opts = OrtSession.SessionOptions()

        // 基础优化
        try { opts.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT) } catch (_: Exception) {}
        try { opts.setExecutionMode(OrtSession.SessionOptions.ExecutionMode.SEQUENTIAL) } catch (_: Exception) {}
        try { opts.addConfigEntry("session.intra_op.allow_spinning", "0") } catch (_: Exception) {}

        // 线程数
        val cores = if (nThreads > 0) nThreads else Runtime.getRuntime().availableProcessors()
        try { opts.setIntraOpNumThreads(cores) } catch (_: Exception) {}
        try { opts.setInterOpNumThreads(1) } catch (_: Exception) {}

        val mode = ExecutionProvider.fromString(providerMode)

        when (mode) {
            ExecutionProvider.AUTO -> configureAuto(opts)
            ExecutionProvider.NNAPI -> configureNnapi(opts)
            ExecutionProvider.CPU_ACL -> configureCpuAcl(opts)
            ExecutionProvider.CPU_ONLY -> configureCpuOnly(opts)
        }

        session = env!!.createSession(modelPath, opts)
    }

    /**
     * AUTO: NNAPI → ACL → CPU_ONLY 逐级回退
     */
    private fun configureAuto(opts: OrtSession.SessionOptions) {
        // 先试 NNAPI（多数新手机支持）
        var nnapiOK = tryAddNnapi(opts)
        if (nnapiOK) {
            activeProvider = "NNAPI"
            // NNAPI 成功后加 ACL 作为 CPU 回退
            try { opts.addACL(true) } catch (_: Exception) {}
            try { opts.addCPU(true) } catch (_: Exception) {}
            return
        }

        // NNAPI 不可用，试 ACL
        try { opts.addACL(true) } catch (_: Exception) {}
        try { opts.addCPU(true) } catch (_: Exception) {}
        activeProvider = "CPU_ACL"
    }

    /**
     * NNAPI 模式：优先 NNAPI，回退 CPU
     */
    private fun configureNnapi(opts: OrtSession.SessionOptions) {
        val ok = tryAddNnapi(opts)
        if (ok) {
            activeProvider = "NNAPI"
        } else {
            // NNAPI 不可用就降级到 CPU
            try { opts.addACL(true) } catch (_: Exception) {}
            try { opts.addCPU(true) } catch (_: Exception) {}
            activeProvider = "CPU_ACL (fallback: NNAPI unavailable)"
        }
    }

    /**
     * CPU_ACL 模式：ACL + XNNPACK（最稳定）
     */
    private fun configureCpuAcl(opts: OrtSession.SessionOptions) {
        try { opts.addACL(true) } catch (_: Exception) {}
        try { opts.addCPU(true) } catch (_: Exception) {}
        activeProvider = "CPU_ACL"
    }

    /**
     * CPU_ONLY 模式：纯 XNNPACK（最大兼容性）
     */
    private fun configureCpuOnly(opts: OrtSession.SessionOptions) {
        try { opts.addCPU(true) } catch (_: Exception) {}
        activeProvider = "CPU_ONLY"
    }

    /**
     * 尝试添加 NNAPI 执行提供器
     * @return true 如果添加成功
     */
    private fun tryAddNnapi(opts: OrtSession.SessionOptions): Boolean {
        return try {
            // ONNX Runtime 1.18+ 的 NNAPI API
            opts.addNnapi(mapOf(
                "nnapi.use_fp16" to "1",
                "nnapi.use_nchw" to "0",
            ))
            true
        } catch (e: Exception) {
            try {
                // 旧版 API（无参数）
                opts.addNnapi()
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    fun unloadModel() {
        stopRequested = true
        session?.close()
        env?.close()
        session = null
        env = null
        tokenizer = null
        activeProvider = "unknown"
    }

    fun countTokens(text: String): Int {
        return tokenizer?.encode(text, addSpecial = true)?.size ?: 0
    }

    fun generate(
        prompt: String,
        temperature: Float = 0.8f,
        topK: Int = 40,
        topP: Float = 0.95f,
        maxTokens: Int = 256,
        repeatPenalty: Float = 1.1f,
        repeatLastN: Int = 64,
        prefillWindow: Int = 64,
        decodeWindow: Int = 16,
        onToken: (String) -> Unit
    ) {
        val tok = tokenizer ?: throw IllegalStateException("模型未加载")
        val sess = session ?: throw IllegalStateException("模型未加载")
        val ortEnv = env ?: throw IllegalStateException("环境未初始化")

        stopRequested = false

        val promptIds = tok.encode(prompt, addSpecial = true).take(nCtx).map { it }
        if (promptIds.isEmpty()) throw IllegalArgumentException("prompt 为空")

        val generated = mutableListOf<Int>()
        generated.addAll(promptIds)

        var decoded = tok.decode(generated, skipSpecial = true)

        for (step in 0 until maxTokens) {
            if (stopRequested) break
            if (generated.size >= nCtx) break

            // 预填充 + 窗口解码：
            //   首步：喂 prefillWindow token → 建上下文
            //   后续：只喂最近 decodeWindow token → 速度优先/质量优先取决于窗口大小
            val fullIds = generated.toIntArray()
            val ctxSize = if (step == 0) prefillWindow else decodeWindow
            val windowIds = if (fullIds.size > ctxSize) {
                fullIds.copyOfRange(fullIds.size - ctxSize, fullIds.size)
            } else {
                fullIds
            }
            val inputShape = longArrayOf(1, windowIds.size.toLong())

            val byteBuffer = ByteBuffer.allocateDirect(windowIds.size * 4)
                .order(ByteOrder.nativeOrder())
            byteBuffer.asIntBuffer().put(windowIds)

            val inputTensor = OnnxTensor.createTensor(
                ortEnv, byteBuffer, inputShape, OnnxJavaType.INT32
            )

            // 推理
            val outputs: OrtSession.Result = sess.run(
                mapOf("input_ids" to inputTensor)
            )

            // 读取 logits: output[1, seq_len, vocab_size]
            val outputTensor = outputs.get(0) as OnnxTensor
            val logitsData = outputTensor.floatBuffer
            val seqLen = windowIds.size

            // 取最后一个位置的 logits
            val offset = (seqLen - 1) * vocabSize
            val lastLogits = FloatArray(vocabSize)
            for (i in 0 until vocabSize) {
                lastLogits[i] = logitsData[offset + i]
            }

            val nextToken = sample(
                lastLogits, temperature, topK, topP,
                generated, repeatPenalty, repeatLastN
            )

            if (nextToken == tok.eosId) break
            generated.add(nextToken)

            val newDecoded = tok.decode(generated, skipSpecial = true)
            val piece = newDecoded.substring(decoded.length)
            decoded = newDecoded
            if (piece.isNotEmpty()) onToken(piece)

            outputTensor.close()
            inputTensor.close()
            outputs.close()
        }
    }

    fun stop() {
        stopRequested = true
    }

    /** 返回当前实际使用的执行提供器（用于调试/展示） */
    fun getActiveProvider(): String = activeProvider

    private fun sample(
        logits: FloatArray,
        temperature: Float,
        topK: Int,
        topP: Float,
        generated: List<Int>,
        repeatPenalty: Float,
        repeatLastN: Int
    ): Int {
        val vocab = logits.size
        val invTemp = 1.0f / max(temperature, 0.01f)
        val scores = FloatArray(vocab) { logits[it] * invTemp }

        if (repeatPenalty > 1.0f) {
            val recent = generated.takeLast(repeatLastN).toSet()
            for (id in recent) {
                if (id in 0 until vocab) scores[id] /= repeatPenalty
            }
        }

        if (topK > 0) {
            val k = min(topK, vocab)
            val sorted = scores.sortedDescending()
            val threshold = sorted[k - 1]
            for (i in scores.indices) {
                if (scores[i] < threshold) scores[i] = Float.NEGATIVE_INFINITY
            }
        }

        if (topP < 1.0f) {
            val indexed = scores.mapIndexed { idx, value -> idx to value }
                .sortedByDescending { it.second }
            val expVals = indexed.map {
                exp((it.second - (scores.maxOrNull() ?: 0f)).toDouble()).toFloat()
            }
            val sumExp = expVals.sum()
            val probs = expVals.map { it / sumExp }
            var cum = 0.0f
            val keep = BooleanArray(vocab) { false }
            for (i in indexed.indices) {
                keep[indexed[i].first] = true
                cum += probs[i]
                if (cum >= topP) break
            }
            for (i in scores.indices) {
                if (!keep[i]) scores[i] = Float.NEGATIVE_INFINITY
            }
        }

        val maxScore = scores.maxOrNull() ?: 0f
        val expScores = scores.map { exp((it - maxScore).toDouble()).toFloat() }
        val sumExp = expScores.sum()
        val probs = expScores.map { it / sumExp }

        if (probs.any { it.isNaN() || it < 0 }) {
            return generated.lastOrNull() ?: 0
        }

        val rand = Random().nextFloat()
        var cum = 0.0f
        for (i in probs.indices) {
            cum += probs[i]
            if (rand <= cum) return i
        }
        return probs.size - 1
    }
}
