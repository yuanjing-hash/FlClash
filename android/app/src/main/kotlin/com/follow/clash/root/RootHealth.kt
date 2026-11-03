package com.follow.clash.root

import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.ThreadLocalRandom

internal object RootHealth {
    const val PROBE_DOMAIN = "flclash-root-health.invalid"
    const val PROBE_ADDRESS = "198.18.0.2"

    data class DnsProbe(val udp: String, val tcp: String) {
        val success: Boolean get() = udp == "ok" && tcp == "ok"
        val details: String get() = "udp=$udp tcp=$tcp"
    }

    // The tunnel's DNS address also works when the UI disables hijacking of arbitrary DNS servers.
    fun dns(
        target: InetAddress = InetAddress.getByName(PROBE_ADDRESS),
        port: Int = 53,
        timeoutMs: Int = 1_000,
    ): DnsProbe {
        val id = ThreadLocalRandom.current().nextInt(65536)
        val labels = PROBE_DOMAIN.split('.').flatMap { listOf(it.length.toByte()) + it.toByteArray().toList() }
        val question =
            byteArrayOf((id shr 8).toByte(), id.toByte(), 1, 0, 0, 1, 0, 0, 0, 0, 0, 0) +
                labels.toByteArray() + byteArrayOf(0, 0, 1, 0, 1)
        val udp = probe {
            DatagramSocket().use { socket ->
                socket.soTimeout = timeoutMs
                socket.connect(target, port)
                socket.send(DatagramPacket(question, question.size))
                val response = DatagramPacket(ByteArray(4096), 4096)
                socket.receive(response)
                validResponse(response.data.copyOf(response.length), id)
            }
        }
        val tcp = probe {
            Socket().use { socket ->
                socket.connect(InetSocketAddress(target, port), timeoutMs)
                socket.soTimeout = timeoutMs
                DataOutputStream(socket.getOutputStream()).apply {
                    writeShort(question.size)
                    write(question)
                    flush()
                }
                val input = DataInputStream(socket.getInputStream())
                val size = input.readUnsignedShort()
                if (size !in 12..4096) return@use false
                val response = ByteArray(size)
                input.readFully(response)
                validResponse(response, id)
            }
        }
        return DnsProbe(udp, tcp)
    }

    private fun probe(check: () -> Boolean): String =
        try {
            if (check()) "ok" else "invalid-response"
        } catch (error: Exception) {
            "${error.javaClass.simpleName}: ${error.message.orEmpty().take(160)}"
        }

    internal fun validResponse(
        response: ByteArray,
        id: Int,
    ): Boolean =
        response.size >= 12 &&
            ((response[0].toInt() and 255) shl 8 or (response[1].toInt() and 255)) == id &&
            response[2].toInt() and 128 != 0 && response[2].toInt() and 2 == 0 && response[3].toInt() and 15 == 0
}
