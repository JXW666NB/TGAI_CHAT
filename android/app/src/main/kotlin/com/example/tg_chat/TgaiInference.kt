package com.example.tg_chat

import android.content.Context
import org.pytorch.IValue
import org.pytorch.Module
import org.pytorch.Tensor
import java.io.File
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min

class TgaiInference(private val context: Context) {

    private var prefillModule: Module? = null
    private var decodeModule: Module? = null
    private var tokenizer: TgaiTokenizer? = null

    private var nCtx: Int = 512
    private var nLayers: Int = 0
    private var nHeads: Int = 0
    private var dK: Int = 0
    private var vocabSize: Int = 0

    @Volatile
    private var stopRequested: Boolean = false

    fun loadModel(prefillPath: String, decodePath: String, tokenizerPath: String, nCtx: Int) {
        this.nCtx = nCtx
        prefillModule = Module.load(prefillPath)
        decodeModule = Module.load(decodePath)
        tokenizer = TgaiTokenizer(context, tokenizerPath)

        // 从 prefill 输出形状推断维度
        val probeInput = Tensor.fromBlob(longArrayOf(tokenizer!!.bosId.toLong()), longArrayOf(1, 1))
        val output = prefillModule!!.forward(IValue.from(probeInput)).toTuple()
        val logitsShape = output[0].toTensor().shape()
        val kvShape = output[1].toTensor().shape()

        vocabSize = logitsShape[2].toInt()
        nLayers = (kvShape[0].toInt()) / 2
        nHeads = kvShape[2].toInt()
        dK = kvShape[4].toInt()
    }

    fun unloadModel() {
        prefillModule = null
        decodeModule = null
        tokenizer = null
        stopRequested = true
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
        onToken: (String) -> Unit
    ) {
        val tok = tokenizer ?: throw IllegalStateException("模型未加载")
        val prefill = prefillModule ?: throw IllegalStateException("模型未加载")
        val decode = decodeModule ?: throw IllegalStateException("模型未加载")

        stopRequested = false

        val promptIds = tok.encode(prompt, addSpecial = true).take(nCtx).map { it.toLong() }.toLongArray()
        if (promptIds.isEmpty()) throw IllegalArgumentException("prompt 为空")

        // Prefill
        val prefillInput = Tensor.fromBlob(promptIds, longArrayOf(1, promptIds.size.toLong()))
        val prefillOut = prefill.forward(IValue.from(prefillInput)).toTuple()
        val prefillLogits = prefillOut[0].toTensor()
        val kvCache = prefillOut[1].toTensor()

        val logitsData = prefillLogits.dataAsFloatArray
        val vocab = vocabSize
        val seqLen = promptIds.size

        // 取最后一个 token 的 logits
        val lastLogits = FloatArray(vocab) { logitsData[(seqLen - 1) * vocab + it] }

        val generated = mutableListOf<Int>()
        promptIds.forEach { generated.add(it.toInt()) }

        var nextToken = sample(lastLogits, temperature, topK, topP, generated, repeatPenalty)
        generated.add(nextToken)

        var decoded = tok.decode(generated, skipSpecial = true)
        if (decoded.isNotEmpty()) onToken(decoded)

        var cachePos = seqLen

        for (step in 0 until maxTokens) {
            if (stopRequested) break
            if (nextToken == tok.eosId) break
            if (cachePos >= nCtx) break

            val inputIds = longArrayOf(nextToken.toLong())
            val inputTensor = Tensor.fromBlob(inputIds, longArrayOf(1, 1))
            val cachePosTensor = Tensor.fromBlob(longArrayOf(cachePos.toLong()), longArrayOf(1))

            val decodeOut = decode.forward(IValue.from(inputTensor), IValue.from(cachePosTensor), IValue.from(kvCache))
            val decodeLogits = decodeOut.toTensor().dataAsFloatArray

            nextToken = sample(decodeLogits, temperature, topK, topP, generated, repeatPenalty)
            generated.add(nextToken)
            cachePos++

            val newDecoded = tok.decode(generated, skipSpecial = true)
            val piece = newDecoded.substring(decoded.length)
            decoded = newDecoded
            if (piece.isNotEmpty()) onToken(piece)
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
        repeatPenalty: Float
    ): Int {
        val vocab = logits.size
        val invTemp = 1.0f / max(temperature, 0.01f)
        val scores = FloatArray(vocab) { logits[it] * invTemp }

        // 重复惩罚（仅惩罚最近 repeatLastN 个 token）
        if (repeatPenalty > 1.0f) {
            val recent = generated.takeLast(repeatLastN).toSet()
            for (id in recent) {
                if (id in 0 until vocab) scores[id] /= repeatPenalty
            }
        }

        // Top-K
        if (topK > 0) {
            val k = min(topK, vocab)
            val sorted = scores.sortedDescending()
            val threshold = sorted[k - 1]
            for (i in scores.indices) {
                if (scores[i] < threshold) scores[i] = Float.NEGATIVE_INFINITY
            }
        }

        // Top-P
        if (topP < 1.0f) {
            val indexed = scores.mapIndexed { idx, value -> idx to value }.sortedByDescending { it.second }
            val expVals = indexed.map { exp((it.second - (scores.maxOrNull() ?: 0f)).toDouble()).toFloat() }
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

        // Softmax
        val maxScore = scores.maxOrNull() ?: 0f
        val expScores = scores.map { exp((it - maxScore).toDouble()).toFloat() }
        val sumExp = expScores.sum()
        val probs = expScores.map { it / sumExp }

        // 防止全 -inf
        if (probs.any { it.isNaN() || it < 0 }) {
            return generated.lastOrNull() ?: 0
        }

        // Multinomial
        val rand = java.util.Random().nextFloat()
        var cum = 0.0f
        for (i in probs.indices) {
            cum += probs[i]
            if (rand <= cum) return i
        }
        return probs.size - 1
    }
}
