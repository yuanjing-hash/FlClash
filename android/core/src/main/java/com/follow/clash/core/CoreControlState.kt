package com.follow.clash.core

import com.google.gson.JsonObject
import com.google.gson.JsonParser

class CoreControlState {
    fun requiresSettledCore(data: String): Boolean =
        runCatching { JsonParser.parseString(data).asJsonObject["method"]?.asString in TRANSITION_MUTATIONS }.getOrDefault(true)

    private var updates = JsonObject()
    private var selections = JsonObject()
    private var selectionSequence = 0L
    private val selectionCalls = mutableMapOf<String, Long>()
    private val selectionVersions = mutableMapOf<String, Long>()
    private var transitioning = false
    private val calls = mutableListOf<String>()
    private val subscriptions = mutableMapOf<String, String>()

    @Synchronized
    fun capture(data: String) {
        val request = runCatching { JsonParser.parseString(data).asJsonObject }.getOrNull() ?: return
        val method = request["method"]?.asString
        when (method) {
            "setupConfig" -> {
                updates = JsonObject()
                selectionCalls.clear()
                selectionVersions.clear()
                selections = request["arguments"]
                    ?.takeIf { it.isJsonObject }
                    ?.asJsonObject
                    ?.get("selected-map")
                    ?.takeIf { it.isJsonObject }
                    ?.asJsonObject
                    ?.deepCopy() ?: JsonObject()
                calls.clear()
            }
            "changeProxy" -> selectionCalls[data] = ++selectionSequence
            "updateConfig" ->
                request["arguments"]?.takeIf { it.isJsonObject }?.asJsonObject?.entrySet()?.forEach { (key, value) ->
                    if (!value.isJsonNull) {
                        val previous = updates[key]
                        if (previous?.isJsonObject == true && value.isJsonObject) {
                            value.asJsonObject.entrySet().forEach { (nestedKey, nested) ->
                                if (!nested.isJsonNull) previous.asJsonObject.add(nestedKey, nested.deepCopy())
                            }
                        } else {
                            updates.add(key, value.deepCopy())
                        }
                    }
                }
            "watchRoute" -> subscriptions["watchRoute"] = data
            "startLog" -> subscriptions["log"] = data
            "stopLog" -> subscriptions.remove("log")
        }
        if (transitioning && method in MUTATIONS) calls.add(data)
    }

    @Synchronized
    fun currentUpdates(): String = updates.toString()

    @Synchronized
    fun currentSelections(): String = selections.toString()

    @Synchronized
    fun complete(
        data: String,
        response: ByteArray?,
    ) {
        val sequence = selectionCalls.remove(data) ?: return
        val answer = runCatching { JsonParser.parseString(response?.decodeToString()).asJsonObject }.getOrNull()
        val result = answer?.get("result")?.takeIf { it.isJsonObject }?.asJsonObject
        if (answer == null || answer["error"]?.isJsonNull == false || result?.get("message")?.asString != "") {
            calls.remove(data)
            return
        }
        val args = JsonParser.parseString(data).asJsonObject.getAsJsonObject("arguments")
        val group = args["group-name"].asString
        if (sequence >= (selectionVersions[group] ?: 0)) {
            selections.addProperty(group, args["proxy-name"].asString)
            selectionVersions[group] = sequence
        }
    }

    @Synchronized
    fun beginTransition() {
        transitioning = true
        calls.clear()
    }

    @Synchronized
    fun finishTransition(): List<String> {
        transitioning = false
        return (calls.toList() + subscriptions.values).also { calls.clear() }
    }

    private companion object {
        val TRANSITION_MUTATIONS =
            setOf(
                "initClash",
                "shutdown",
                "setupConfig",
                "updateConfig",
                "changeProxy",
                "buildProfile",
                "updateGeoData",
                "sideLoadExternalProvider",
            )
        val MUTATIONS =
            setOf(
                "setupConfig",
                "updateConfig",
                "changeProxy",
                "resetTraffic",
                "updateExternalProvider",
                "sideLoadExternalProvider",
                "updateGeoData",
            )
    }
}
