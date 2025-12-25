@file:Suppress("UNCHECKED_CAST", "DEPRECATION")

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
import java.util.Date

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

	// Technique selection
	@Volatile
	private var techHttpUrlConnection: String? = null
	@Volatile
	private var techOkHttp: String? = null
	@Volatile
	private var techNativeCurl: String? = null
	@Volatile
	private var techCronet: String? = null

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

						// techniques
						val techs = pin["techniques"] as? Map<*, *>
						techs?.let {
							techHttpUrlConnection = (it["httpUrlConnection"] as? String)
							techOkHttp = (it["okHttp"] as? String)
							techNativeCurl = (it["nativeCurl"] as? String)
							techCronet = (it["cronet"] as? String)
						}
						// Rebuild Cronet engine with new pins
						rebuildCronetEngine(null)
					}
					result.success(null)
				}
				"isCronetPinningSupported" -> {
					// Cronet pinning is now supported
					result.success(true)
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
						val headers = mutableMapOf<String, String>()
						(args?.get("headers") as? Map<*, *>)?.forEach { (k, v) ->
							if (k is String && v is String) headers[k] = v
						}
						val body = args?.get("body") as? String
						val timeoutMs = (args?.get("timeoutMs") as? Number)?.toInt() ?: 20000

						// If a bundled CA exists as asset, copy once to cache/files and pass path via pseudo-header
						try {
							val caPath = ensureCaBundle()
							if (caPath != null && headers.keys.none { it.equals("X-Curl-CaInfo", ignoreCase = true) }) {
								headers["X-Curl-CaInfo"] = caPath
							}
						} catch (_: Throwable) { }

						// Pass global pinning to native curl via pseudo-headers according to technique
						try {
							val effTech = effectiveNativeCurlTech()
							if (globalPinningEnabled && effTech != "none") {
								if (globalPinningMode == "publicKey" && globalSpkiPins.isNotEmpty() && headers.keys.none { it.equals("X-Curl-SpkiPins", ignoreCase = true) }) {
									headers["X-Curl-SpkiPins"] = globalSpkiPins.joinToString(",")
								} else if (globalPinningMode == "certHash" && globalCertPins.isNotEmpty() && headers.keys.none { it.equals("X-Curl-CertPins", ignoreCase = true) }) {
									headers["X-Curl-CertPins"] = globalCertPins.joinToString(",")
								}
								// convey technique to native curl: preflight | sslctx | both
								val techHeader = when (effTech) {
									"curlPreflight" -> "preflight"
									"curlSslCtx" -> "sslctx"
									"curlBoth", "auto" -> "both"
									else -> null
								}
								if (techHeader != null) headers["X-Curl-Technique"] = techHeader
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

	// Normalize a pin string by removing optional "sha256/" prefix and all whitespace
	private fun normalizePin(pin: String): String {
		var p = pin.replace("\\s".toRegex(), "")
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
				sendLogToFlutter("[PIN DEBUG] Server SPKI SHA256: $spki")
				for (p in globalSpkiPins) {
					val normalized = normalizePin(p)
					sendLogToFlutter("[PIN DEBUG] Comparing against configured pin: $normalized")
					if (normalized == spki) {
						sendLogToFlutter("[PIN DEBUG] ✓ Pin matched")
						return true
					}
				}
				sendLogToFlutter("[PIN DEBUG] ✗ No matching SPKI pin found")
				false
			} else {
				val ch = calcCertSha256Base64(cert)
				sendLogToFlutter("[PIN DEBUG] Server Cert SHA256: $ch")
				for (p in globalCertPins) {
					val normalized = normalizePin(p)
					sendLogToFlutter("[PIN DEBUG] Comparing against configured pin: $normalized")
					if (normalized == ch) {
						sendLogToFlutter("[PIN DEBUG] ✓ Pin matched")
						return true
					}
				}
				sendLogToFlutter("[PIN DEBUG] ✗ No matching cert hash pin found")
				false
			}
		} catch (e: Throwable) {
			sendLogToFlutter("[PIN DEBUG] Pin verification error: ${e.message}")
			false
		}
	}

	companion object {
		@JvmStatic
		fun verifyHostPins(host: String, port: Int, spkiCsv: String?, certCsv: String?): Boolean {
			try {
				val urlStr = "https://$host:${if (port > 0) port else 443}/"
				val url = java.net.URL(urlStr)
				val conn = (url.openConnection() as javax.net.ssl.HttpsURLConnection).apply {
					connectTimeout = 5000
					readTimeout = 5000
					instanceFollowRedirects = false
				}
				try {
					conn.connect()
					val certs = conn.serverCertificates
					if (certs != null && certs.isNotEmpty()) {
						val x509 = certs[0] as java.security.cert.X509Certificate
						// compute hashes
						val pub = x509.publicKey.encoded
						val md = MessageDigest.getInstance("SHA-256")
						val spkiHash = android.util.Base64.encodeToString(md.digest(pub), android.util.Base64.NO_WRAP)
						val der = x509.encoded
						val certHash = android.util.Base64.encodeToString(md.digest(der), android.util.Base64.NO_WRAP)
						// check provided CSV lists
						if (!spkiCsv.isNullOrEmpty()) {
							for (p in spkiCsv.split(',')) {
								val np = p.trim().removePrefix("sha256/")
								if (np == spkiHash) return true
							}
						}
						if (!certCsv.isNullOrEmpty()) {
							for (p in certCsv.split(',')) {
								val np = p.trim().removePrefix("sha256/")
								if (np == certHash) return true
							}
						}
					}
				} finally {
					try { conn.disconnect() } catch (_: Throwable) { }
				}
			} catch (_: Throwable) {
				return false
			}
			return false
		}
	}

	// Copy assets/cacert.pem to a readable path and return its absolute path, or null if asset missing
	private fun ensureCaBundle(): String? {
		return try {
			assets.open("cacert.pem").use { input ->
				val outFile = File(cacheDir, "cacert.pem")
				if (!outFile.exists() || outFile.length() == 0L) {
					FileOutputStream(outFile).use { fos -> input.copyTo(fos) }
				}
				outFile.absolutePath
			}
		} catch (_: Throwable) {
			null
		}
	}

	private val cronetExecutor = Executors.newSingleThreadExecutor()

	@Volatile
	private var cronetEngine: CronetEngine? = null
	@Volatile
	private var cronetPinnedHost: String? = null

	private fun cronetLog(msg: String) {
		android.util.Log.d("FluttidaCronet", msg)
		sendLogToFlutter("[CRONET] $msg")
	}

	private fun sendLogToFlutter(msg: String) {
		try {
			Handler(Looper.getMainLooper()).post {
				MethodChannel(
					flutterEngine?.dartExecutor?.binaryMessenger ?: return@post,
					CHANNEL
				).invokeMethod("log", mapOf("message" to msg))
			}
		} catch (_: Throwable) {}
	}

	private fun getCronetEngine(host: String?): CronetEngine {
		if (cronetEngine == null || cronetPinnedHost != host) {
			synchronized(this) {
				if (cronetEngine == null || cronetPinnedHost != host) {
					try {
						rebuildCronetEngine(host)
					} catch (e: Throwable) {
						// Reset engine state on build failure
						cronetEngine = null
						cronetPinnedHost = null
						throw e
					}
				}
			}
		}
		return cronetEngine!!
	}

	private fun buildCronetEngine(host: String?): CronetEngine {
		val builder = CronetEngine.Builder(this)
		// Enforce pins even when a user-added CA exists (otherwise Cronet bypasses)
		builder.enablePublicKeyPinningBypassForLocalTrustAnchors(false)

		// Apply pinning if enabled and mode is publicKey (SPKI)
		if (globalPinningEnabled && techCronet != null && techCronet != "none" && globalPinningMode == "publicKey" && globalSpkiPins.isNotEmpty() && !host.isNullOrEmpty()) {
			val pinSet = mutableSetOf<ByteArray>()
			val errors = mutableListOf<String>()
			for (pin in globalSpkiPins) {
				try {
					val normalized = normalizePin(pin)
					val bytes = Base64.decode(normalized, Base64.NO_WRAP)
					if (bytes != null && bytes.size == 32) {
						pinSet.add(bytes)
					} else {
						errors.add("Pin '$pin' decoded to ${bytes?.size ?: 0} bytes (expected 32)")
					}
				} catch (e: Throwable) {
					errors.add("Pin '$pin' failed: ${e.message}")
				}
			}
			if (pinSet.isEmpty()) {
				val errMsg = "Cronet pinning enabled but no valid pins: ${errors.joinToString("; ")}"
				android.util.Log.e("FluttidaCronet", errMsg)
				throw IllegalStateException(errMsg)
			}
			val expiration = Date(System.currentTimeMillis() + 365L * 24 * 60 * 60 * 1000)
			builder.addPublicKeyPins(
				host,
				pinSet,
				true, // includeSubdomains
				expiration
			)
			cronetLog("Applied ${pinSet.size} SPKI pins to host=$host")
			if (errors.isNotEmpty()) {
				cronetLog("Warnings: ${errors.joinToString("; ")}")
			}
		} else if (globalPinningEnabled && techCronet != null && techCronet != "none" && globalPinningMode != "publicKey") {
			android.util.Log.w("FluttidaCronet", "Cronet pinning requested but mode=$globalPinningMode is unsupported (SPKI only)")
		}
		
		return builder.build()
	}

	private fun rebuildCronetEngine(host: String?) {
		synchronized(this) {
			// Shutdown old engine if present
			try {
				cronetEngine?.shutdown()
			} catch (_: Throwable) {}
			cronetEngine = null
			cronetPinnedHost = null
			// Build new engine (may throw on invalid pins)
			cronetEngine = buildCronetEngine(host)
			cronetPinnedHost = host
		}
	}

	@Suppress("DEPRECATION")
	private fun handleCronetRequest(args: Map<*, *>?, result: MethodChannel.Result) {
		val start = System.currentTimeMillis()
		try {
			if (globalPinningEnabled && techCronet != null && techCronet != "none" && globalPinningMode != "publicKey") {
				cronetLog("Blocking request: unsupported pinning mode=$globalPinningMode for Cronet (SPKI only)")
				val map = mapOf("status" to null, "body" to "", "durationMs" to 0, "error" to "Cronet supports only SPKI pinning")
				Handler(Looper.getMainLooper()).post { result.success(map) }
				return
			}

			val url = (args?.get("url") as? String) ?: throw Exception("no url")
			val method = (args["method"] as? String) ?: "GET"
			val headers = args["headers"] as? Map<*, *>
			val body = args["body"] as? String

			val targetHost = java.net.URL(url).host
			cronetLog("Request host=$targetHost method=$method pinningEnabled=$globalPinningEnabled mode=$globalPinningMode tech=$techCronet spkiPins=${globalSpkiPins.size}")

			val baos = ByteArrayOutputStream()

			val callback = object : UrlRequest.Callback() {
				override fun onRedirectReceived(request: UrlRequest, info: UrlResponseInfo, newLocationUrl: String) {
					request.followRedirect()
				}

				override fun onResponseStarted(request: UrlRequest, info: UrlResponseInfo) {
					cronetLog("Response started host=${info.url?.let { java.net.URL(it).host }} status=${info.httpStatusCode}")
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
					cronetLog("Success host=${info.url?.let { java.net.URL(it).host }} status=$status durationMs=$duration")
					val map = mapOf("status" to status, "body" to respBody, "durationMs" to duration, "error" to null)
					Handler(Looper.getMainLooper()).post { result.success(map) }
				}

				override fun onFailed(request: UrlRequest, info: UrlResponseInfo?, error: CronetException) {
					val duration = (System.currentTimeMillis() - start).toInt()
					cronetLog("Failed host=${info?.url?.let { java.net.URL(it).host }} durationMs=$duration error=$error")
					val map = mapOf("status" to null, "body" to "", "durationMs" to duration, "error" to error.toString())
					Handler(Looper.getMainLooper()).post { result.success(map) }
				}

				override fun onCanceled(request: UrlRequest, info: UrlResponseInfo?) {
					val duration = (System.currentTimeMillis() - start).toInt()
					cronetLog("Canceled host=${info?.url?.let { java.net.URL(it).host }} durationMs=$duration")
					val map = mapOf("status" to null, "body" to "", "durationMs" to duration, "error" to "canceled")
					Handler(Looper.getMainLooper()).post { result.success(map) }
				}
			}
			val requestBuilder = getCronetEngine(targetHost).newUrlRequestBuilder(url, callback, cronetExecutor)
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

			// Apply TrustManager-based pinning if technique is "trustManager"
			if (globalPinningEnabled && techHttpUrlConnection == "trustManager" && conn is javax.net.ssl.HttpsURLConnection) {
				try {
					val trustManager = object : javax.net.ssl.X509TrustManager {
						override fun checkClientTrusted(chain: Array<java.security.cert.X509Certificate>, authType: String) {}
						
						override fun checkServerTrusted(chain: Array<java.security.cert.X509Certificate>, authType: String) {
							if (chain.isEmpty()) throw java.security.cert.CertificateException("Empty certificate chain")
							// Check first cert (server cert) against pins
							val cert = chain[0]
						sendLogToFlutter("[HttpURLConnection/TrustManager] Verifying certificate...")
						override fun getAcceptedIssuers(): Array<java.security.cert.X509Certificate> = arrayOf()
					}
					
					val sslContext = javax.net.ssl.SSLContext.getInstance("TLS")
					sslContext.init(null, arrayOf(trustManager), null)
					conn.sslSocketFactory = sslContext.socketFactory
					conn.hostnameVerifier = javax.net.ssl.HostnameVerifier { _, _ -> true }
				} catch (e: Exception) {
					val duration = (System.currentTimeMillis() - start).toInt()
					return mapOf("status" to null, "body" to "", "durationMs" to duration, "error" to "TrustManager setup failed: ${e.message}")
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
			
			// Post-connect verification (only if technique is "postConnect")
			try {
				if (globalPinningEnabled && techHttpUrlConnection == "postConnect" && conn is javax.net.ssl.HttpsURLConnection) {
					val certs = conn.serverCertificates
					if (certs != null && certs.isNotEmpty()) {
						val x509 = certs[0] as java.security.cert.X509Certificate
						sendLogToFlutter("[HttpURLConnection/postConnect] Verifying certificate...")
						val ok = verifyCertPins(x509)
						if (!ok) throw Exception("SSL pinning mismatch (postConnect)")
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

			// Technique selection for OkHttp
			val effTech = techOkHttp
			val usePinner = globalPinningEnabled && effTech == "okhttpPinner" && globalPinningMode == "publicKey"
			if (usePinner) {
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

				// If pinning enabled and technique requires post-connect verification
				val needPostVerify = globalPinningEnabled && (
					(effTech == "postConnect") ||
					(globalPinningMode == "certHash" && effTech != "none")
				)
				if (needPostVerify) {
					try {
						val peerCerts = resp.handshake?.peerCertificates
						if (peerCerts != null && peerCerts.isNotEmpty()) {
							val x509 = peerCerts[0] as java.security.cert.X509Certificate						val techLabel = if (effTech == "postConnect") "postConnect" else "certHash fallback"
						sendLogToFlutter("[OkHttp/$techLabel] Verifying certificate...")							val ok = verifyCertPins(x509)
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

	private fun effectiveHttpUrlConnTech(): String {
		return techHttpUrlConnection ?: "postConnect"
	}

	private fun effectiveNativeCurlTech(): String {
		// Return technique only if stack is actually enabled
		// If techNativeCurl is null, the stack is not enabled -> return "none"
		return techNativeCurl ?: "none"
	}
}
