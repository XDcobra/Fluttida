package com.example.fluttida

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
	private val CHANNEL = "fluttida/network"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
			when (call.method) {
				"androidHttpURLConnection" -> {
					val args = call.arguments as? Map<*, *>
					Thread {
						result.success(handleHttpUrlConnection(args))
					}.start()
				}
				"androidOkHttp" -> {
					val args = call.arguments as? Map<*, *>
					Thread {
						result.success(handleOkHttp(args))
					}.start()
				}
				else -> result.notImplemented()
			}
		}
	}

	private fun handleHttpUrlConnection(args: Map<*, *>?): Map<String, Any?> {
		val start = System.currentTimeMillis()
		try {
			val url = URL((args?.get("url") as? String) ?: throw Exception("no url"))
			val method = (args["method"] as? String) ?: "GET"
			val headers = args["headers"] as? Map<*, *>
			val body = args["body"] as? String
			val timeoutMs = (args["timeoutMs"] as? Number)?.toInt() ?: 20000

			val conn = (url.openConnection() as HttpURLConnection).apply {
				requestMethod = method
				connectTimeout = timeoutMs
				readTimeout = timeoutMs
				doInput = true
				if (method != "GET" && method != "HEAD") {
					doOutput = true
				}
			}

			headers?.forEach { (k, v) ->
				if (k is String && v != null) conn.setRequestProperty(k, v.toString())
			}

			if (body != null) {
				conn.outputStream.use { os ->
					OutputStreamWriter(os, Charsets.UTF_8).use { it.write(body) }
				}
			}

			val status = conn.responseCode
			val input = try { conn.inputStream } catch (e: Exception) { conn.errorStream }
			val bytes = input?.readBytes() ?: ByteArray(0)
			val respBody = bytes.toString(Charsets.UTF_8)
			val duration = (System.currentTimeMillis() - start).toInt()

			conn.disconnect()

			return mapOf("status" to status, "body" to respBody, "durationMs" to duration, "error" to null)
		} catch (e: Exception) {
			val duration = (System.currentTimeMillis() - start).toInt()
			return mapOf("status" to null, "body" to "", "durationMs" to duration, "error" to e.toString())
		}
	}

	private fun handleOkHttp(args: Map<*, *>?): Map<String, Any?> {
		val start = System.currentTimeMillis()
		try {
			val url = (args?.get("url") as? String) ?: throw Exception("no url")
			val method = (args["method"] as? String) ?: "GET"
			val headers = args["headers"] as? Map<*, *>
			val body = args["body"] as? String
			val timeoutMs = (args["timeoutMs"] as? Number)?.toLong() ?: 20000L

			val client = OkHttpClient.Builder()
				.connectTimeout(timeoutMs, TimeUnit.MILLISECONDS)
				.readTimeout(timeoutMs, TimeUnit.MILLISECONDS)
				.build()

			val builder = Request.Builder().url(url)
			headers?.forEach { (k, v) ->
				if (k is String && v != null) builder.addHeader(k, v.toString())
			}

			val request = if (body != null && method != "GET" && method != "HEAD") {
				val media = "text/plain; charset=utf-8".toMediaTypeOrNull()
				val rb = body.toRequestBody(media)
				builder.method(method, rb).build()
			} else {
				builder.method(method, null).build()
			}

			client.newCall(request).execute().use { resp ->
				val respBody = resp.body?.string() ?: ""
				val status = resp.code
				val duration = (System.currentTimeMillis() - start).toInt()
				return mapOf("status" to status, "body" to respBody, "durationMs" to duration, "error" to null)
			}
		} catch (e: Exception) {
			val duration = (System.currentTimeMillis() - start).toInt()
			return mapOf("status" to null, "body" to "", "durationMs" to duration, "error" to e.toString())
		}
	}
}
