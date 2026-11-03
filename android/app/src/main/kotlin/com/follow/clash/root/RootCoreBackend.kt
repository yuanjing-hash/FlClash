package com.follow.clash.root

import com.follow.clash.core.CoreBackend
import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

internal class RootCoreBackend(
    private val port: Int,
    private val token: String,
) : CoreBackend {
    private val gson = Gson()
    private val sequence = AtomicLong()
    private val pending = ConcurrentHashMap<String, (ByteArray?) -> Unit>()
    private val scheduler = Executors.newSingleThreadScheduledExecutor { work -> Thread(work, "RootCoreTimeout").apply { isDaemon = true } }
    private val writer =
        ThreadPoolExecutor(1, 1, 0, TimeUnit.SECONDS, ArrayBlockingQueue(512)) { work ->
            Thread(work, "RootCoreWriter").apply { isDaemon = true }
        }
    private val writes = Any()

    @Volatile private var socket: Socket? = null

    @Volatile private var events: ((ByteArray) -> Unit)? = null

    @Volatile private var closed = false
    private var output: DataOutputStream? = null

    @Volatile private var routeWatch: Any? = null

    @Volatile private var logging = false

    @Volatile private var restoring = false

    @Volatile private var restoreFailed = false

    @Volatile private var pendingHandoff = emptyList<String>()

    @Volatile var startupError: String? = null
        private set

    init {
        scheduler.scheduleWithFixedDelay({
            if (socket == null && !closed) {
                runCatching {
                    writer.execute {
                        if (socket == null && !closed) {
                            runCatching {
                                connect()
                                updateEventListener(events)
                                if (pendingHandoff.isNotEmpty()) {
                                    restoreState(pendingHandoff)
                                } else {
                                    routeWatch?.let { call("watchRoute", it) }
                                    if (logging) call("startLog")
                                }
                            }
                        }
                    }
                }
            }
        }, 1, 1, TimeUnit.SECONDS)
    }

    @Synchronized
    fun connect() {
        check(!closed)
        if (socket != null) return
        val connection = Socket()
        try {
            connection.connect(InetSocketAddress("127.0.0.1", port), 1_000)
            connection.tcpNoDelay = true
            connection.soTimeout = 2_000
            val writer = DataOutputStream(connection.getOutputStream())
            writeFrame(writer, gson.toJson(mapOf("token" to token)).toByteArray())
            val input = DataInputStream(connection.getInputStream())
            check(JsonParser.parseString(readFrame(input).decodeToString()).asJsonObject["ready"]?.asBoolean == true) {
                "Root Core rejected authentication"
            }
            connection.soTimeout = 0
            synchronized(writes) {
                check(!closed)
                socket = connection
                output = writer
            }
            Thread({ read(connection, input) }, "RootCoreReader").apply {
                isDaemon = true
                start()
            }
        } catch (error: Exception) {
            connection.close()
            throw error
        }
    }

    private fun read(
        connection: Socket,
        input: DataInputStream,
    ) {
        try {
            while (!closed) {
                val frame = readFrame(input)
                val envelope = JsonParser.parseString(frame.decodeToString()).asJsonObject
                if (envelope["method"]?.asString == "message") {
                    runCatching { events?.invoke(frame) }
                } else {
                    val id = envelope["id"]?.asString ?: continue
                    pending.remove(id)?.let { callback -> runCatching { callback(frame) } }
                }
            }
        } catch (_: Exception) {
        } finally {
            synchronized(writes) {
                if (socket === connection) {
                    socket = null
                    output = null
                    failPending()
                }
            }
            connection.close()
        }
    }

    override fun invokeMethod(
        data: String,
        callback: (ByteArray?) -> Unit,
    ) {
        val request = JsonParser.parseString(data).asJsonObject
        when (request["method"]?.asString) {
            "watchRoute" -> routeWatch = request["arguments"]
            "startLog" -> logging = true
            "stopLog" -> logging = false
        }
        val originalId = request["id"]?.asString
        val id = originalId ?: "root-native-${sequence.incrementAndGet()}"
        if (originalId == null) request.addProperty("id", id)
        pending[id] = { response ->
            if (response == null) {
                callback(
                    gson
                        .toJson(
                            mapOf(
                                "id" to originalId,
                                "result" to null,
                                "error" to
                                    mapOf("code" to "root_core_unavailable", "message" to "Root Core connection is unavailable"),
                            ),
                        ).toByteArray(),
                )
            } else {
                callback(response)
            }
        }
        val timeout = scheduler.schedule({ pending.remove(id)?.invoke(null) }, 120, TimeUnit.SECONDS)
        val delivery = pending[id]
        if (delivery != null) {
            pending[id] = { response ->
                timeout.cancel(false)
                delivery(response)
            }
        }
        try {
            writer.execute {
                try {
                    synchronized(writes) {
                        writeFrame(checkNotNull(output) { "Root Core is disconnected" }, gson.toJson(request).toByteArray())
                    }
                } catch (_: Exception) {
                    pending.remove(id)?.invoke(null)
                }
            }
        } catch (_: Exception) {
            pending.remove(id)?.invoke(null)
        }
    }

    private fun call(
        method: String,
        arguments: Any? = null,
        callback: (JsonObject?) -> Unit = {},
    ) {
        invokeMethod(gson.toJson(mapOf("method" to method, "arguments" to arguments))) { data ->
            callback(data?.let { JsonParser.parseString(it.decodeToString()).asJsonObject })
        }
    }

    private fun result(
        method: String,
        arguments: Any? = null,
    ): JsonObject? {
        val answer = CompletableFuture<JsonObject?>()
        call(method, arguments, answer::complete)
        return runCatching { answer.get(3, TimeUnit.SECONDS) }.getOrNull()
    }

    fun healthy(): Boolean =
        !restoring && !restoreFailed && result("__root.health")?.getAsJsonObject("result")?.get("ready")?.asBoolean == true

    fun dnsEnabled(): Boolean = result("__root.health")?.getAsJsonObject("result")?.get("dnsEnabled")?.asBoolean == true

    override fun updateEventListener(callback: ((ByteArray) -> Unit)?) {
        events = callback
        call("__root.events", callback != null)
    }

    override fun restoreState(calls: List<String>) {
        if (calls.isEmpty()) return
        calls.forEach { data ->
            val request = JsonParser.parseString(data).asJsonObject
            when (request["method"]?.asString) {
                "watchRoute" -> routeWatch = request["arguments"]
                "startLog" -> logging = true
                "stopLog" -> logging = false
            }
        }
        pendingHandoff = calls
        restoreFailed = false
        restoring = true
        call("__root.handoff", calls.map(JsonParser::parseString)) { response ->
            restoreFailed = response == null || response.has("error")
            if (!restoreFailed) pendingHandoff = emptyList()
            startupError = if (restoreFailed) response?.get("error")?.toString() ?: "Root Core disconnected during UI handoff" else null
            restoring = false
        }
    }

    override fun quickSetup(
        initParams: String,
        setupParams: String,
        callback: (String?) -> Unit,
    ) {
        call("initClash", JsonParser.parseString(initParams)) { initialized ->
            if (initialized?.has("error") == true || initialized == null) {
                callback(initialized?.get("error")?.toString() ?: "Root Core is disconnected")
            } else {
                call("setupConfig", JsonParser.parseString(setupParams)) { response ->
                    callback(
                        if (response ==
                            null
                        ) {
                            "Root Core is disconnected"
                        } else {
                            response["error"]?.toString() ?: response["result"]?.asString.orEmpty()
                        },
                    )
                }
            }
        }
    }

    override fun forceGC() = call("forceGc")

    override fun updateDNS(dns: String) = call("updateDns", dns)

    override fun updateDnsCapture(dns: String) = call("__root.dnsCapture", dns)

    override fun resetNetwork() = call("__root.resetNetwork")

    override fun startListener() = call("startListener")

    override fun stopListener() = call("stopListener")

    override fun getTraffic(onlyStatisticsProxy: Boolean): String =
        result("getTraffic", onlyStatisticsProxy)?.get("result")?.toString() ?: "{}"

    override fun getTotalTraffic(onlyStatisticsProxy: Boolean): String =
        result("getTotalTraffic", onlyStatisticsProxy)?.get("result")?.toString() ?: "{}"

    private fun failPending() {
        pending.keys.forEach { id -> pending.remove(id)?.let { callback -> runCatching { callback(null) } } }
    }

    override fun close() {
        closed = true
        synchronized(writes) {
            socket?.close()
            socket = null
            output = null
        }
        events = null
        failPending()
        scheduler.shutdownNow()
        writer.shutdownNow()
    }

    companion object {
        private const val MAX_FRAME = 64 * 1024 * 1024

        internal fun readFrame(input: DataInputStream): ByteArray {
            val length = Integer.reverseBytes(input.readInt())
            require(length in 1..MAX_FRAME) { "Invalid Root Core frame size" }
            return ByteArray(length).also(input::readFully)
        }

        internal fun writeFrame(
            output: DataOutputStream,
            bytes: ByteArray,
        ) {
            require(bytes.size in 1..MAX_FRAME)
            output.writeInt(Integer.reverseBytes(bytes.size))
            output.write(bytes)
            output.flush()
        }
    }
}
