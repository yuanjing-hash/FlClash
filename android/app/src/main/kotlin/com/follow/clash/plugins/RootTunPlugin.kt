package com.follow.clash.plugins

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import androidx.core.content.FileProvider
import com.follow.clash.ServiceState
import com.follow.clash.common.Components
import com.follow.clash.root.success
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class RootTunPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware {
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private lateinit var scope: CoroutineScope
    private var activity: Activity? = null
    private val backend get() = ServiceState.rootTun

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        methods = MethodChannel(binding.binaryMessenger, "${Components.PACKAGE_NAME}/root_tun")
        events = EventChannel(binding.binaryMessenger, "${Components.PACKAGE_NAME}/root_tun/events")
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        backend.unsubscribe()
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        scope.cancel()
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        scope.launch {
            try {
                val args = call.arguments as? Map<*, *> ?: throw IllegalArgumentException("Arguments must be a map")
                val response =
                    when (call.method) {
                        "getState" -> success(backend.snapshot.toMap())
                        "detectRoot" -> backend.detect()
                        "start", "stop", "requestAuth", "recheckRoot", "cleanupResidue" -> backend.command(call.method, args)
                        "cleanup" -> backend.command("cleanupResidue", args)
                        "getLogs" -> {
                            require(args["cursor"] == null || args["cursor"] is String) { "cursor must be a string or null" }
                            val limit = args["limit"] ?: 200
                            require(limit is Int) { "limit must be an integer" }
                            success(backend.getLogs(args["cursor"] as? String, limit))
                        }
                        "exportDiagnostics" -> {
                            val file = backend.exportDiagnostics()
                            val host = checkNotNull(activity) { "An activity is required to share diagnostics" }
                            val uri = FileProvider.getUriForFile(host, "${host.packageName}.root-tun.diagnostics", file)
                            val send =
                                Intent(Intent.ACTION_SEND).apply {
                                    type = "application/zip"
                                    putExtra(Intent.EXTRA_STREAM, uri)
                                    clipData = ClipData.newRawUri("Root TUN diagnostics", uri)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                            withContext(Dispatchers.Main) { host.startActivity(Intent.createChooser(send, null)) }
                            success(mapOf("uri" to uri.toString(), "mimeType" to "application/zip", "shared" to true))
                        }
                        else -> {
                            result.notImplemented()
                            return@launch
                        }
                    }
                result.success(response)
            } catch (error: IllegalArgumentException) {
                result.error("INVALID_ARGUMENT", error.message, null)
            } catch (_: Exception) {
                result.error("CORE_ERROR", "Root TUN operation could not complete", mapOf("phase" to call.method))
            }
        }
    }

    override fun onListen(
        arguments: Any?,
        sink: EventChannel.EventSink,
    ) {
        val args = arguments as? Map<*, *>
        val afterSeq = args?.get("afterSeq") as? Number
        if (args?.get("schemaVersion") != 1 || (afterSeq !is Int && afterSeq !is Long) || afterSeq.toLong() < 0 ||
            (args["epoch"] != null && args["epoch"] !is String)
        ) {
            sink.error("INVALID_ARGUMENT", "Expected schemaVersion=1, epoch and nonnegative afterSeq", null)
            return
        }
        backend.subscribe(args["epoch"] as? String, afterSeq.toLong(), sink::success)
    }

    override fun onCancel(arguments: Any?) = backend.unsubscribe()

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
}
