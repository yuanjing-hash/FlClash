package com.follow.clash.root

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class RootHealthTest {
    @Test
    fun rejectsTruncationWrongTransactionAndQueries() {
        val response = byteArrayOf(0x46, 0x43, 0x81.toByte(), 0x80.toByte(), 0, 1, 0, 1, 0, 0, 0, 0)
        assertTrue(RootHealth.validResponse(response, 0x4643))
        assertFalse(RootHealth.validResponse(response, 0x4644))
        assertFalse(RootHealth.validResponse(response.copyOf(11), 0x4643))
        response[2] = 0x83.toByte()
        assertFalse(RootHealth.validResponse(response, 0x4643))
        response[2] = 0x81.toByte()
        response[3] = 3
        assertFalse(RootHealth.validResponse(response, 0x4643))
        response[3] = 0
        response[2] = 1
        assertFalse(RootHealth.validResponse(response, 0x4643))
    }

    @Test
    fun udpAndTcpProbeExchangeCompleteDnsFrames() {
        withDnsServer { port ->
            val result = RootHealth.dns(InetAddress.getLoopbackAddress(), port)
            assertTrue(result.details, result.success)
        }
    }

    @Test
    fun udpTimeoutStillProbesTcpAndRetainsItsOwnFailure() {
        withDnsServer(udpResponse = { null }) { port ->
            val result = RootHealth.dns(InetAddress.getLoopbackAddress(), port, 200)
            assertFalse(result.success)
            assertTrue(result.details, result.udp.startsWith("SocketTimeoutException"))
            assertEquals("ok", result.tcp)
        }
    }

    @Test
    fun invalidUdpTransactionDoesNotPreventTcpProbe() {
        withDnsServer(udpResponse = { request -> reply(request).also { it[0] = (it[0].toInt() xor 1).toByte() } }) { port ->
            val result = RootHealth.dns(InetAddress.getLoopbackAddress(), port)
            assertEquals("invalid-response", result.udp)
            assertEquals("ok", result.tcp)
            assertFalse(result.success)
        }
    }

    @Test
    fun tcpFailureCannotBeMaskedBySuccessfulUdp() {
        withDnsServer(tcpResponse = { request -> reply(request).also { it[3] = 5 } }) { port ->
            val result = RootHealth.dns(InetAddress.getLoopbackAddress(), port)
            assertEquals("ok", result.udp)
            assertEquals("invalid-response", result.tcp)
            assertFalse(result.success)
        }
    }

    private fun reply(request: ByteArray): ByteArray = request.copyOf().also { it[2] = (it[2].toInt() or 128).toByte() }

    private fun withDnsServer(
        udpResponse: (ByteArray) -> ByteArray? = ::reply,
        tcpResponse: (ByteArray) -> ByteArray = ::reply,
        test: (Int) -> Unit,
    ) {
        val address = InetAddress.getLoopbackAddress()
        ServerSocket(0, 1, address).use { tcp ->
            DatagramSocket(InetSocketAddress(address, tcp.localPort)).use { udp ->
                tcp.soTimeout = 3_000
                udp.soTimeout = 3_000
                val executor = Executors.newFixedThreadPool(2)
                try {
                    val udpTask = executor.submit {
                        val packet = DatagramPacket(ByteArray(4096), 4096)
                        udp.receive(packet)
                        udpResponse(packet.data.copyOf(packet.length))?.let { bytes ->
                            udp.send(DatagramPacket(bytes, bytes.size, packet.socketAddress))
                        }
                    }
                    val tcpTask = executor.submit {
                        tcp.accept().use { socket ->
                            socket.soTimeout = 3_000
                            val input = DataInputStream(socket.getInputStream())
                            val request = ByteArray(input.readUnsignedShort())
                            input.readFully(request)
                            val response = tcpResponse(request)
                            DataOutputStream(socket.getOutputStream()).apply {
                                writeShort(response.size)
                                write(response)
                                flush()
                            }
                        }
                    }
                    test(tcp.localPort)
                    udpTask.get(4, TimeUnit.SECONDS)
                    tcpTask.get(4, TimeUnit.SECONDS)
                } finally {
                    executor.shutdownNow()
                }
            }
        }
    }

    @Test
    fun prerequisiteFailureAndWireEnumsFollowContract() {
        val error = failure(RootCode.ROOT_NOT_FOUND, "detectRoot")["error"] as Map<*, *>
        assertFalse(error["retryable"] as Boolean)
        assertTrue(TunState.fromWire("awaitingAuth") == TunState.AWAITING_AUTH)
    }
}
