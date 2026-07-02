package com.example.tg_chat

import android.content.Context
import org.json.JSONObject
import java.io.File

class TgaiTokenizer(context: Context, tokenizerPath: String) {

    private val vocab: MutableMap<String, Int> = mutableMapOf()
    private val idToToken: MutableMap<Int, String> = mutableMapOf()
    private val merges: MutableMap<Pair<String, String>, Int> = mutableMapOf()
    private val specialTokens: Set<String>

    val padId: Int
    val unkId: Int
    val bosId: Int
    val eosId: Int
    val vocabSize: Int get() = vocab.size

    init {
        val json = JSONObject(File(tokenizerPath).readText())

        padId = json.getJSONObject("special_ids").getInt("pad")
        unkId = json.getJSONObject("special_ids").getInt("unk")
        bosId = json.getJSONObject("special_ids").getInt("bos")
        eosId = json.getJSONObject("special_ids").getInt("eos")

        specialTokens = setOf("<PAD>", "<UNK>", "<BOS>", "<EOS>", "<IMG>", "<AUD>", "<VID>")

        val vocabObj = json.getJSONObject("token_to_id")
        for (key in vocabObj.keys()) {
            val id = vocabObj.getInt(key)
            vocab[key] = id
            idToToken[id] = key
        }

        val mergesArray = json.getJSONArray("merges")
        for (i in 0 until mergesArray.length()) {
            val mergeStr = mergesArray.getString(i)
            val parts = mergeStr.split(" ")
            if (parts.size == 2) {
                merges[Pair(parts[0], parts[1])] = i
            }
        }
    }

    fun encode(text: String, addSpecial: Boolean = true): List<Int> {
        if (text.isEmpty()) {
            return if (addSpecial) listOf(bosId, eosId) else emptyList()
        }

        val preTokens = pretokenize(text)
        val ids = mutableListOf<Int>()
        for (token in preTokens) {
            ids.addAll(encodeWord(token))
        }

        return if (addSpecial) listOf(bosId) + ids + listOf(eosId) else ids
    }

    fun decode(ids: List<Int>, skipSpecial: Boolean = true): String {
        val tokens = ids.mapNotNull { idToToken[it] }
        val filtered = if (skipSpecial) {
            tokens.filter { it !in specialTokens }
        } else tokens
        return cleanCjkSpacing(filtered.joinToString(""))
    }

    private fun pretokenize(text: String): List<String> {
        val regex = Regex("[\\u4e00-\\u9fff]{1,4}|[\\u3400-\\u4dbf]|[a-zA-Z]+|\\d+|[\\s]+|[^\\s\\w]")
        return regex.findAll(text).map { it.value }.toList()
    }

    private fun encodeWord(word: String): List<Int> {
        var symbols = word.map { it.toString() }.toMutableList()

        while (symbols.size >= 2) {
            var bestRank: Int? = null
            var bestPair: Pair<String, String>? = null

            for (i in 0 until symbols.size - 1) {
                val pair = Pair(symbols[i], symbols[i + 1])
                val rank = merges[pair]
                if (rank != null && (bestRank == null || rank < bestRank)) {
                    bestRank = rank
                    bestPair = pair
                }
            }

            if (bestPair == null) break

            val newSymbol = bestPair.first + bestPair.second
            val newSymbols = mutableListOf<String>()
            var i = 0
            while (i < symbols.size) {
                if (i < symbols.size - 1 && symbols[i] == bestPair.first && symbols[i + 1] == bestPair.second) {
                    newSymbols.add(newSymbol)
                    i += 2
                } else {
                    newSymbols.add(symbols[i])
                    i += 1
                }
            }
            symbols = newSymbols
        }

        return symbols.map { vocab[it] ?: unkId }
    }

    private fun cleanCjkSpacing(text: String): String {
        val cjk = Regex("(?<=[\\u4e00-\\u9fff\\u3400-\\u4dbf\\u3000-\\u303f\\uff00-\\uffef]) | (?=[\\u4e00-\\u9fff\\u3400-\\u4dbf\\u3000-\\u303f\\uff00-\\uffef])")
        return cjk.replace(text, "")
    }
}
