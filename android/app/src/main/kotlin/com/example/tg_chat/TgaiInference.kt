package com.example.tg_chat

import android.content.Context
import org.pytorch.executorch.EValue
import org.pytorch.executorch.Module
import org.pytorch.executorch.Tensor
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min

class TgaiInference(private val context: Context) {

    @Volatile
    private var module: Module? = null
    @Volatile
    private var tokenizer: TgaiTokenizer? = null

    private var nCtx: Int = 512
    private var vocabSize: Int = 0

    @Volatile
    private var stopRequested: Boolean = false

    fun loadModel(modelPath: String, tokenizerPath: String, nCtx: Int) {
        this.nCtx = nCtx
        module = Module.load(modelPath)
        tokenizer = TgaiTokenizer(context, tokenizerPath)
        vocabSize = tokenizer!!.vocabSize
    }

    fun unloadModel() {
        module = null
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
        val mod = module ?: throw IllegalStateException("模型未加载")

        stopRequested = false

        val promptIds = tok.encode(prompt, addSpecial = true).take(nCtx).map { it }
        if (promptIds.isEmpty()) throw IllegalArgumentException("prompt 为空")

        val generated = mutableListOf<Int>()
        generated.addAll(promptIds)

        var decoded = tok.decode(generated, skipSpecial = true)

        for (step in 0 until maxTokens) {
            if (stopRequested) break

            if (generated.size >= nCtx) break

            // 每次 forward 喂入当前所有 token
            val inputIds = generated.toIntArray()
            val inputTensor: Tensor = Tensor.fromBlob(inputIds, longArrayOf(1, inputIds.size.toLong()))

            val output = mod.forward(EValue.from(inputTensor))
            val logitsData = output[0].toTensor().dataAsFloatArray
            val seqLen = inputIds.size

            // 取最后一个位置的 logits
            val lastLogits = FloatArray(vocabSize) { logitsData[(seqLen - 1) * vocabSize + it] }

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

        val maxScore = scores.maxOrNull() ?: 0f
        val expScores = scores.map { exp((it - maxScore).toDouble()).toFloat() }
        val sumExp = expScores.sum()
        val probs = expScores.map { it / sumExp }

        if (probs.any { it.isNaN() || it < 0 }) {
            return generated.lastOrNull() ?: 0
        }

        val rand = java.util.Random().nextFloat()
        var cum = 0.0f
        for (i in probs.indices) {
            cum += probs[i]
            if (rand <= cum) return i
        }
        return probs.size - 1
    }
}
