package com.follow.clash.core

import com.follow.clash.core.mobile.Mobile
import com.follow.clash.core.mobile.ResultHandler
import com.follow.clash.core.mobile.TunHandler
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.URI
import java.util.concurrent.CompletableFuture
import java.util.concurrent.atomic.AtomicInteger

object Core {
    @Volatile private var backend: CoreBackend? = null
    private var eventCallback: ((ByteArray) -> Unit)? = null

    @Volatile private var latestDns = ""

    @Volatile private var latestDnsCapture: String? = null
    private val controlState = CoreControlState()
    private val localCalls = AtomicInteger()

    @Volatile private var held = false

    @Volatile private var preparingRoot = false
    private var generation = 0L
    private val queued = mutableListOf<Pair<String, (ByteArray?) -> Unit>>()
    private var localReplay = emptyList<String>()

    fun currentUpdates(): String = controlState.currentUpdates()

    fun currentSelections(): String = controlState.currentSelections()

    fun currentDns(): List<String> = latestDns.split(',').filter(String::isNotBlank)

    fun beginRootTransition(allowed: () -> Boolean): Boolean {
        synchronized(this) {
            generation++
            held = true
            preparingRoot = true
            controlState.beginTransition()
        }
        val deadline = System.nanoTime() + 45_000_000_000L
        while (localCalls.get() != 0) {
            if (!allowed()) return false
            check(System.nanoTime() < deadline) { "Previous Core calls did not settle" }
            Thread.sleep(20)
        }
        if (!allowed()) return false
        check(Mobile.pauseForRoot()) { "Previous Core listeners did not close" }
        return allowed()
    }

    @Synchronized
    fun useBackend(next: CoreBackend?) {
        if (next != null && backend === next) return
        generation++
        preparingRoot = false
        val pending = queued.toList()
        queued.clear()
        val replay = controlState.finishTransition().filterNot { data -> pending.any { it.first == data } }
        val previous = backend
        Mobile.setEventListener(null)
        Mobile.stopListener()
        backend = next
        previous?.close()
        if (next != null) {
            held = false
            next.updateEventListener(eventCallback)
            next.updateDNS(latestDns)
            latestDnsCapture?.let(next::updateDnsCapture)
            next.restoreState(replay)
            pending.forEach { (data, callback) -> next.invokeMethod(data, callback) }
        } else {
            held = true
            localReplay = replay
            queued.addAll(pending)
            updateEventListener(eventCallback)
        }
    }

    @Synchronized
    fun restoreEmbedded(calls: List<String>): CompletableFuture<Boolean> {
        val completed = CompletableFuture<Boolean>()
        val revision = ++generation
        held = true
        val restoring = calls + localReplay
        localReplay = emptyList()

        fun step(index: Int) {
            synchronized(this) {
                if (revision != generation || backend != null) {
                    completed.complete(false)
                    return
                }
                if (index == restoring.size) {
                    Mobile.setEventListener(eventCallback?.let { callback -> ResultHandler { data -> callback(data ?: ByteArray(0)) } })
                    Mobile.resumeAfterRoot()
                    held = false
                    val pending = queued.toList()
                    queued.clear()
                    pending.forEach { (data, callback) -> invokeLocal(data, callback) }
                    completed.complete(true)
                } else {
                    invokeLocal(restoring[index]) { step(index + 1) }
                }
            }
        }
        step(0)
        return completed
    }

    private fun invokeLocal(
        data: String,
        callback: (ByteArray?) -> Unit,
    ) {
        val settling = controlState.requiresSettledCore(data)
        if (settling) localCalls.incrementAndGet()
        try {
            Mobile.invokeMethod(
                data,
                ResultHandler { result ->
                    if (settling) localCalls.decrementAndGet()
                    callback(result)
                },
            )
        } catch (error: Throwable) {
            if (settling) localCalls.decrementAndGet()
            throw error
        }
    }

    fun forceGC() {
        backend?.let {
            it.forceGC()
            return
        }
        Mobile.forceGC()
    }

    fun updateDNS(dns: String) {
        latestDns = dns
        backend?.let {
            it.updateDNS(dns)
            return
        }
        Mobile.updateDns(dns)
    }

    fun updateDnsCapture(dns: String) {
        latestDnsCapture = dns
        backend?.updateDnsCapture(dns)
    }

    fun resetNetwork() {
        backend?.let {
            it.resetNetwork()
            return
        }
        Mobile.resetNetwork()
    }

    private fun parseInetSocketAddress(address: String): InetSocketAddress {
        val uri = URI("tcp://$address")
        val host = requireNotNull(uri.host) { "Missing host in address: $address" }
        require(uri.port >= 0) { "Missing port in address: $address" }
        return InetSocketAddress(InetAddress.getByName(host), uri.port)
    }

    fun startTun(
        fd: Int,
        protect: (Int) -> Boolean,
        resolveUid: (protocol: Int, source: InetSocketAddress, target: InetSocketAddress) -> Int,
        resolvePackage: (uid: Int) -> String,
        stack: String,
        address: String,
        dns: String,
        options: String,
    ): Boolean =
        Mobile.startTun(
            fd,
            object : TunHandler {
                override fun protect(fd: Int): Boolean = protect(fd)

                override fun resolveUid(
                    protocol: Int,
                    source: String,
                    target: String,
                ): Int =
                    resolveUid(
                        protocol,
                        parseInetSocketAddress(source),
                        parseInetSocketAddress(target),
                    )

                override fun resolvePackage(uid: Int): String = resolvePackage(uid)
            },
            stack,
            address,
            dns,
            options,
        )

    @Synchronized
    fun invokeMethod(
        data: String,
        cb: (result: ByteArray?) -> Unit,
    ) {
        controlState.capture(data)
        val answer: (ByteArray?) -> Unit = { response ->
            controlState.complete(data, response)
            cb(response)
        }
        if (held) {
            queued.add(data to answer)
            return
        }
        backend?.let {
            it.invokeMethod(data, answer)
            return
        }
        invokeLocal(data, answer)
    }

    @Synchronized
    fun updateEventListener(callback: ((result: ByteArray) -> Unit)?) {
        eventCallback = callback
        if (held) {
            Mobile.setEventListener(null)
            return
        }
        backend?.let {
            it.updateEventListener(callback)
            return
        }
        Mobile.setEventListener(
            callback?.let { ResultHandler { result -> it(result ?: ByteArray(0)) } },
        )
    }

    fun quickSetup(
        initParamsString: String,
        setupParamsString: String,
        callback: (result: String?) -> Unit,
    ) {
        if (preparingRoot || backend != null || held) {
            callback("Core mode is changing")
            return
        }
        localCalls.incrementAndGet()
        Mobile.quickSetup(
            initParamsString,
            setupParamsString,
            ResultHandler { result ->
                localCalls.decrementAndGet()
                callback(result?.decodeToString())
            },
        )
    }

    fun stopTun() = Mobile.stopTun()

    fun startListener() = Mobile.startListener()

    fun stopListener() = Mobile.stopListener()

    fun getTraffic(onlyStatisticsProxy: Boolean): String =
        backend?.getTraffic(onlyStatisticsProxy) ?: Mobile.getTraffic(onlyStatisticsProxy)

    fun getTotalTraffic(onlyStatisticsProxy: Boolean): String =
        backend?.getTotalTraffic(onlyStatisticsProxy) ?: Mobile.getTotalTraffic(onlyStatisticsProxy)
}
