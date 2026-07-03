package com.example.tg_chat

import android.content.Context
import ai.onnxruntime.*
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.*

class TgaiOnnxInference {

    private var env: OrtEnvironment? = null
    private var session: OrtSession? = null
    private var tokenizer: TgaiTokenizer? = null

    private var nCtx: Int = 512
    private var vocabSize: Int = 0

    @Volatile
    private var stopRequested: Boolean = false

    fun loadModel(context: Context, modelPath: String, tokenizerPath: String, nCtx: Int) {
        this.nCtx = nCtx
        tokenizer = TgaiTokenizer(context, tokenizerPath)
        vocabSize = tokenizer!!.vocabSize

        env = OrtEnvironment.getEnvironment()
        val opts = OrtSession.SessionOptions().apply {
            // XNNPACK 加速（CPU EP 内置），不额外注册 NNAPI 避免频繁回退
            try { addCPU(true) } catch (_: Exception) {}
            // 匹配物理核心数
            val numCores = Runtime.getRuntime().availableProcessors()
            try { setIntraOpNumThreads(numCores) } catch (_: Exception) {}
            try { setInterOpNumThreads(1) } catch (_: Exception) {}
            // 禁用 intra-op spinning 避免与 XNNPACK 内部线程池抢资源
            try { addConfigEntry("session.intra_op.allow_spinning", "0") } catch (_: Exception) {}
            // 启用图优化 + 内存复用
            try { setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT) } catch (_: Exception) {}
            try { setExecutionMode(OrtSession.SessionOptions.ExecutionMode.SEQUENTIAL) } catch (_: Exception) {}
        }

        session = env!!.createSession(modelPath, opts)
    }

    fun unloadModel() {
        stopRequested = true
        session?.close()
        env?.close()
        session = null
        env = null
        tokenizer = null
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
