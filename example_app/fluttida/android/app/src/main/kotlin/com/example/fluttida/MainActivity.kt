package com.example.fluttida

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.CertificatePinner
import java.security.MessageDigest
import android.util.Base64
import java.security.cert.X509Certificate
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit
import org.chromium.net.CronetEngine
import org.chromium.net.UrlRequest
import org.chromium.net.UrlResponseInfo
import org.chromium.net.UploadDataProviders
import org.chromium.net.CronetException
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.Executors
import android.os.Handler
import android.os.Looper
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream

class MainActivity : FlutterActivity() {
	private val CHANNEL = "fluttida/network"

	// Global pinning state
	@Volatile
	private var globalPinningEnabled: Boolean = false
	@Volatile
	private var globalPinningMode: String = "publicKey" // "publicKey" | "certHash"
	@Volatile
	private var globalSpkiPins: List<String> = emptyList()
	@Volatile
	private var globalCertPins: List<String> = emptyList()

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
			when (call.method) {
				"setGlobalPinningConfig" -> {
					val args = call.arguments as? Map<*, *>
					val pin = args?.get("pinning") as? Map<*, *>
					if (pin != null) {
						globalPinningEnabled = (pin["enabled"] as? Boolean) == true
						globalPinningMode = (pin["mode"] as? String) ?: "publicKey"
						globalSpkiPins = (pin["spkiPins"] as? List<*>)?.mapNotNull { it as? String } ?: emptyList()
						globalCertPins = (pin["certSha256Pins"] as? List<*>)?.mapNotNull { it as? String } ?: emptyList()
					}
					result.success(null)
				}
				"isCronetPinningSupported" -> {
					// Cronet public-key pinning support detection: not implemented here
					result.success(false)
				}
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
				"androidCronet" -> {
					val args = call.arguments as? Map<*, *>
					// Cronet request executed asynchronously; we'll call result.success(...) from callback
					Thread {
						handleCronetRequest(args, result)
					}.start()
				}
				"androidNativeCurl" -> {
					val args = call.arguments as? Map<*, *>
					Thread {
						val url = (args?.get("url") as? String) ?: ""
						val method = (args?.get("method") as? String) ?: "GET"
						val headers = (args?.get("headers") as? Map<String, String>)?.toMutableMap() ?: mutableMapOf()
						val body = args?.get("body") as? String
						val timeoutMs = (args?.get("timeoutMs") as? Number)?.toInt() ?: 20000

						// If a bundled CA exists as asset, copy once to cache/files and pass path via pseudo-header
						try {
							val caPath = ensureCaBundle()
							if (caPath != null && headers.keys.none { it.equals("X-Curl-CaInfo", ignoreCase = true) }) {
								headers["X-Curl-CaInfo"] = caPath
							}
						} catch (_: Throwable) { }

						// Pass global pinning to native curl via pseudo-headers (native layer may use them)
						try {
							if (globalPinningEnabled) {
								if (globalPinningMode == "publicKey" && globalSpkiPins.isNotEmpty() && headers.keys.none { it.equals("X-Curl-SpkiPins", ignoreCase = true) }) {
									headers["X-Curl-SpkiPins"] = globalSpkiPins.joinToString(",")
								} else if (globalPinningMode == "certHash" && globalCertPins.isNotEmpty() && headers.keys.none { it.equals("X-Curl-CertPins", ignoreCase = true) }) {
									headers["X-Curl-CertPins"] = globalCertPins.joinToString(",")
								}
							}
						} catch (_: Throwable) { }

						val map = NativeHttp.perform(method, url, headers, body, timeoutMs)
						result.success(map)
					}.start()
				}
				else -> result.notImplemented()
			}
		}
	}

	// Normalize a pin string by removing optional "sha256/" prefix and whitespace
	private fun normalizePin(pin: String): String {
		var p = pin.trim()
		if (p.startsWith("sha256/")) p = p.substring(7)
		return p
	}

	private fun calcSpkiSha256Base64(cert: X509Certificate): String {
		val pub = cert.publicKey.encoded
		val digest = MessageDigest.getInstance("SHA-256").digest(pub)
		return Base64.encodeToString(digest, Base64.NO_WRAP)
	}

	private fun calcCertSha256Base64(cert: X509Certificate): String {
		val der = cert.encoded
		val digest = MessageDigest.getInstance("SHA-256").digest(der)
		return Base64.encodeToString(digest, Base64.NO_WRAP)
	}

	private fun verifyCertPins(cert: X509Certificate): Boolean {
		return try {
			if (!globalPinningEnabled) return true
			if (globalPinningMode == "publicKey") {
				val spki = calcSpkiSha256Base64(cert)
				for (p in globalSpkiPins) if (normalizePin(p) == spki) return true
				false
			} else {
				val ch = calcCertSha256Base64(cert)
				for (p in globalCertPins) if (normalizePin(p) == ch) return true
				false
			}
		} catch (_: Throwable) {
			false
		}
	}

	// Copy assets/cacert.pem to a readable path and return its absolute path, or null if asset missing
	private fun ensureCaBundle(): String? {
		val assetName = "cacert.pem"
		return try {
			// Check if asset exists
			val am = assets
			var input: InputStream? = null
			try {
				input = am.open(assetName)
			} catch (_: Throwable) {
				return null
			}
			input?.use {
				val outFile = File(cacheDir, assetName)
				if (!outFile.exists() || outFile.length() == 0L) {
					FileOutputStream(outFile).use { fos ->
						it.copyTo(fos)
					}
				}
				return outFile.absolutePath
			}
			null
		} catch (_: Throwable) {
			null
		}
	}

	private val cronetExecutor = Executors.newSingleThreadExecutor()

	private val cronetEngine: CronetEngine by lazy {
		CronetEngine.Builder(this).build()
	}

	private fun handleCronetRequest(args: Map<*, *>?, result: MethodChannel.Result) {
		val start = System.currentTimeMillis()
		try {
			val url = (args?.get("url") as? String) ?: throw Exception("no url")
			val method = (args["method"] as? String) ?: "GET"
			val headers = args["headers"] as? Map<*, *>
			val body = args["body"] as? String
			val timeoutMs = (args["timeoutMs"] as? Number)?.toLong() ?: 20000L

			val baos = ByteArrayOutputStream()

			val callback = object : UrlRequest.Callback() {
				override fun onRedirectReceived(request: UrlRequest, info: UrlResponseInfo, newLocationUrl: String) {
					request.followRedirect()
				}

				override fun onResponseStarted(request: UrlRequest, info: UrlResponseInfo) {
					request.read(ByteBuffer.allocateDirect(8192))
				}

				override fun onReadCompleted(request: UrlRequest, info: UrlResponseInfo, byteBuffer: ByteBuffer) {
					byteBuffer.flip()
					val bytes = ByteArray(byteBuffer.remaining())
					byteBuffer.get(bytes)
					baos.write(bytes)
					byteBuffer.clear()
					request.read(byteBuffer)
				}

				override fun onSucceeded(request: UrlRequest, info: UrlResponseInfo) {
					val respBody = baos.toString("UTF-8")
					val status = info.httpStatusCode
					val duration = (System.currentTimeMillis() - start).toInt()
					val map = mapOf("status" to status, "body" to respBody, "durationMs" to duration, "error" to null)
					Handler(Looper.getMainLooper()).post { result.success(map) }
				}

				override fun onFailed(request: UrlRequest, info: UrlResponseInfo?, error: CronetException) {
					val duration = (System.currentTimeMillis() - start).toInt()
					val map = mapOf("status" to null, "body" to "", "durationMs" to duration, "error" to error.toString())
					Handler(Looper.getMainLooper()).post { result.success(map) }
				}

				override fun onCanceled(request: UrlRequest, info: UrlResponseInfo?) {
					val duration = (System.currentTimeMillis() - start).toInt()
					val map = mapOf("status" to null, "body" to "", "durationMs" to duration, "error" to "canceled")
					Handler(Looper.getMainLooper()).post { result.success(map) }
				}
			}

			val requestBuilder = cronetEngine.newUrlRequestBuilder(url, callback, cronetExecutor)
			requestBuilder.setHttpMethod(method)
			headers?.forEach { (k, v) -> if (k is String && v != null) requestBuilder.addHeader(k, v.toString()) }

			if (body != null && method != "GET" && method != "HEAD") {
				val bodyBytes = body.toByteArray(Charsets.UTF_8)
				requestBuilder.setUploadDataProvider(UploadDataProviders.create(bodyBytes), cronetExecutor)
			}

			val request = requestBuilder.build()
			request.start()
		} catch (e: Exception) {
			val duration = (System.currentTimeMillis() - start).toInt()
			val map = mapOf("status" to null, "body" to "", "durationMs" to duration, "error" to e.toString())
			Handler(Looper.getMainLooper()).post { result.success(map) }
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

			// If pinning enabled, and HTTPS, we'll check the peer cert after connect

			headers?.forEach { (k, v) ->
				if (k is String && v != null) conn.setRequestProperty(k, v.toString())
			}

			if (body != null) {
				conn.outputStream.use { os ->
					OutputStreamWriter(os, Charsets.UTF_8).use { it.write(body) }
				}
			}

			val status = conn.responseCode
			// Post-connect pin verification for HTTPS
			try {
				if (globalPinningEnabled && conn is javax.net.ssl.HttpsURLConnection) {
					val certs = conn.serverCertificates
					if (certs != null && certs.isNotEmpty()) {
						val x509 = certs[0] as java.security.cert.X509Certificate
						val ok = verifyCertPins(x509)
						if (!ok) throw Exception("SSL pinning mismatch")
					}
				}
			} catch (e: Exception) {
				conn.disconnect()
				val duration = (System.currentTimeMillis() - start).toInt()
				return mapOf("status" to null, "body" to "", "durationMs" to duration, "error" to e.toString())
			}
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

			val clientBuilder = OkHttpClient.Builder()
				.connectTimeout(timeoutMs, TimeUnit.MILLISECONDS)
				.readTimeout(timeoutMs, TimeUnit.MILLISECONDS)

			// If global pinning enabled and using publicKey mode, configure CertificatePinner
			if (globalPinningEnabled && globalPinningMode == "publicKey") {
				try {
					val host = java.net.URL(url).host
					val cpb = CertificatePinner.Builder()
					for (pin in globalSpkiPins) {
						val p = normalizePin(pin)
						cpb.add(host, "sha256/" + p)
					}
					clientBuilder.certificatePinner(cpb.build())
				} catch (_: Throwable) { }
			}

			val client = clientBuilder.build()

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

				// If pinning enabled and using certHash mode, verify the leaf certificate's SHA-256
				if (globalPinningEnabled && globalPinningMode == "certHash") {
					try {
						val peerCerts = resp.handshake?.peerCertificates
						if (peerCerts != null && peerCerts.isNotEmpty()) {
							val x509 = peerCerts[0] as java.security.cert.X509Certificate
							val ok = verifyCertPins(x509)
							if (!ok) throw Exception("SSL pinning mismatch")
						}
					} catch (e: Exception) {
						throw e
					}
				}

				val duration = (System.currentTimeMillis() - start).toInt()
				return mapOf("status" to status, "body" to respBody, "durationMs" to duration, "error" to null)
			}
		} catch (e: Exception) {
			val duration = (System.currentTimeMillis() - start).toInt()
			return mapOf("status" to null, "body" to "", "durationMs" to duration, "error" to e.toString())
		}
	}
}
