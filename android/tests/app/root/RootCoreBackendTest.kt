package com.follow.clash.root

import com.google.gson.JsonParser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class RootCoreBackendTest {
    @Test
    fun forwardsOriginalIdsArgumentsSpillReferencesAndEvents() {
        val listener = ServerSocket(0, 1, InetAddress.getByName("127.0.0.1"))
        val worker = Executors.newSingleThreadExecutor()
        val backend = RootCoreBackend(listener.localPort, "private-token")
        val event = """{"method":"message","arguments":[{"type":"routeChanged","data":{"picks-version":7}}]}"""
        val receivedEvent = CompletableFuture<String>()
        val requests =
            worker.submit<List<String>> {
                listener.accept().use { socket ->
                    socket.soTimeout = 5_000
                    val input = DataInputStream(socket.getInputStream())
                    val output = DataOutputStream(socket.getOutputStream())
                    val hello = JsonParser.parseString(RootCoreBackend.readFrame(input).decodeToString()).asJsonObject
                    assertEquals("private-token", hello["token"].asString)
                    RootCoreBackend.writeFrame(output, """{"ready":true}""".toByteArray())
                    val subscription = JsonParser.parseString(RootCoreBackend.readFrame(input).decodeToString()).asJsonObject
                    RootCoreBackend.writeFrame(output, """{"id":"${subscription["id"].asString}","result":true}""".toByteArray())
                    val first = RootCoreBackend.readFrame(input).decodeToString()
                    val second = RootCoreBackend.readFrame(input).decodeToString()
                    RootCoreBackend.writeFrame(
                        output,
                        """{"id":"android-2","result":null,"file":"/app/responses/large.json"}""".toByteArray(),
                    )
                    RootCoreBackend.writeFrame(output, event.toByteArray())
                    RootCoreBackend.writeFrame(output, """{"id":"android-1","result":{"changed":true},"error":null}""".toByteArray())
                    listOf(first, second)
                }
            }
        try {
            backend.connect()
            backend.updateEventListener { receivedEvent.complete(it.decodeToString()) }
            val first = CompletableFuture<String>()
            val second = CompletableFuture<String>()
            backend.invokeMethod("""{"id":"android-1","method":"changeProxy","arguments":{"group-name":"节点","proxy-name":"DIRECT"}}""") {
                first.complete(it!!.decodeToString())
            }
            backend.invokeMethod("""{"id":"android-2","method":"getProxies","arguments":null}""") { second.complete(it!!.decodeToString()) }
            assertTrue(first.get(5, TimeUnit.SECONDS).contains("\"changed\":true"))
            assertEquals("""{"id":"android-2","result":null,"file":"/app/responses/large.json"}""", second.get(5, TimeUnit.SECONDS))
            assertEquals(event, receivedEvent.get(5, TimeUnit.SECONDS))
            val frames = requests.get(5, TimeUnit.SECONDS)
            val call = JsonParser.parseString(frames[0]).asJsonObject
            assertEquals("android-1", call["id"].asString)
            assertEquals("changeProxy", call["method"].asString)
            assertEquals("节点", call.getAsJsonObject("arguments")["group-name"].asString)
            assertEquals("getProxies", JsonParser.parseString(frames[1]).asJsonObject["method"].asString)
        } finally {
            backend.close()
            listener.close()
            worker.shutdownNow()
        }
    }

    @Test
    fun disconnectFailsPendingCallsWithoutFallingBackToEmbeddedCore() {
        val listener = ServerSocket(0, 1, InetAddress.getByName("127.0.0.1"))
        val worker = Executors.newSingleThreadExecutor()
        val backend = RootCoreBackend(listener.localPort, "private-token")
        val accepted = CountDownLatch(1)
        val server =
            worker.submit {
                listener.accept().use { socket ->
                    val input = DataInputStream(socket.getInputStream())
                    RootCoreBackend.readFrame(input)
                    RootCoreBackend.writeFrame(DataOutputStream(socket.getOutputStream()), """{"ready":true}""".toByteArray())
                    RootCoreBackend.readFrame(input)
                    accepted.countDown()
                }
            }
        try {
            backend.connect()
            val response = CompletableFuture<String>()
            backend.invokeMethod("""{"id":"android-9","method":"updateConfig","arguments":{"mode":"global"}}""") {
                response.complete(it!!.decodeToString())
            }
            assertTrue(accepted.await(5, TimeUnit.SECONDS))
            val answer = JsonParser.parseString(response.get(5, TimeUnit.SECONDS)).asJsonObject
            assertEquals("android-9", answer["id"].asString)
            assertEquals("root_core_unavailable", answer.getAsJsonObject("error")["code"].asString)
            assertFalse(backend.healthy())
            server.get(5, TimeUnit.SECONDS)
        } finally {
            backend.close()
            listener.close()
            worker.shutdownNow()
        }
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsOversizedFramesBeforeAllocating() {
        RootCoreBackend.readFrame(DataInputStream(ByteArrayInputStream(byteArrayOf(-1, -1, -1, 127))))
    }

    @Test
    fun captureIncludesCellularDnsWithoutReplacingThePreferredUpstream() {
        val listener = ServerSocket(0, 1, InetAddress.getByName("127.0.0.1"))
        val worker = Executors.newSingleThreadExecutor()
        val backend = RootCoreBackend(listener.localPort, "private-token")
        val requests =
            worker.submit<List<String>> {
                listener.accept().use { socket ->
                    socket.soTimeout = 5_000
                    val input = DataInputStream(socket.getInputStream())
                    val output = DataOutputStream(socket.getOutputStream())
                    RootCoreBackend.readFrame(input)
                    RootCoreBackend.writeFrame(output, """{"ready":true}""".toByteArray())
                    List(2) {
                        val frame = RootCoreBackend.readFrame(input).decodeToString()
                        val id = JsonParser.parseString(frame).asJsonObject["id"].asString
                        RootCoreBackend.writeFrame(output, """{"id":"$id","result":true}""".toByteArray())
                        frame
                    }
                }
            }
        try {
            backend.connect()
            backend.updateDNS("192.168.5.168:53")
            backend.updateDnsCapture("192.168.5.168:53,218.2.2.2:53")
            val frames = requests.get(5, TimeUnit.SECONDS).map { JsonParser.parseString(it).asJsonObject }
            assertEquals("updateDns", frames[0]["method"].asString)
            assertEquals("192.168.5.168:53", frames[0]["arguments"].asString)
            assertEquals("__root.dnsCapture", frames[1]["method"].asString)
            assertEquals("192.168.5.168:53,218.2.2.2:53", frames[1]["arguments"].asString)
        } finally {
            backend.close()
            listener.close()
            worker.shutdownNow()
        }
    }
}
