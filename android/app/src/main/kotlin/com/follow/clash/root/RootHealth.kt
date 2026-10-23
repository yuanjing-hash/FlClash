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
    fun dns(): Boolean =
        runCatching {
            val id = ThreadLocalRandom.current().nextInt(65536)
            val question =
                byteArrayOf((id shr 8).toByte(), id.toByte(), 1, 0, 0, 1, 0, 0, 0, 0, 0, 0) +
                    byteArrayOf(7) + "example".toByteArray() + byteArrayOf(3) + "com".toByteArray() + byteArrayOf(0, 0, 1, 0, 1)
            val target = InetAddress.getByName("198.18.0.2")
            val udp =
                DatagramSocket().use { socket ->
                    socket.soTimeout = 500
                    socket.connect(target, 53)
                    socket.send(DatagramPacket(question, question.size))
                    val response = DatagramPacket(ByteArray(4096), 4096)
                    socket.receive(response)
                    validResponse(response.data.copyOf(response.length), id)
                }
            val tcp =
                Socket().use { socket ->
                    socket.connect(InetSocketAddress(target, 53), 500)
                    socket.soTimeout = 500
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
            udp && tcp
        }.getOrDefault(false)

    internal fun validResponse(
        response: ByteArray,
        id: Int,
    ): Boolean =
        response.size >= 12 &&
            ((response[0].toInt() and 255) shl 8 or (response[1].toInt() and 255)) == id &&
            response[2].toInt() and 128 != 0 && response[3].toInt() and 15 in setOf(0, 3)
}
