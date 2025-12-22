#include <jni.h>
#include <string>
#include <sstream>
#include <vector>
#include <android/log.h>
#include <dlfcn.h>
#include <chrono>
#include <cstring>
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <cstdio>
#include <cstdlib>
#include <cctype>
#include <errno.h>

#define LOG_TAG "FluttidaNativeHttp"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Globals for CURLOPT_SSL_CTX_FUNCTION verify callback
static std::string g_spkiPinsCsv_global;
static std::string g_certPinsCsv_global;

// Minimal base64 encoder for 32-byte input
static std::string base64_encode_32(const unsigned char in[32]) {
    static const char b64[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    char out[48];
    int outlen = 0;
    unsigned int val = 0;
    int valb = -6;
    for (int i = 0; i < 32; ++i) {
        val = (val << 8) + in[i];
        valb += 8;
        while (valb >= 0) {
            out[outlen++] = b64[(val >> valb) & 0x3F];
            valb -= 6;
        }
    }
    if (valb > -6) out[outlen++] = b64[((val << 8) >> (valb + 8)) & 0x3F];
    while (outlen % 4) out[outlen++] = '=';
    return std::string(out, outlen);
}

// Forward declarations for dlsym-resolved OpenSSL functions we will call from verify callback
typedef unsigned char* (*SHA256_fn_t)(const unsigned char*, size_t, unsigned char*);
typedef int (*i2d_X509_t)(void*, unsigned char**);
typedef int (*i2d_PUBKEY_t)(void*, unsigned char**);
typedef void* (*X509_get_pubkey_t)(void*);
typedef void (*EVP_PKEY_free_t)(void*);
typedef void (*X509_free_t)(void*);
typedef void* (*X509_STORE_CTX_get_current_cert_t)(void*);

// The actual verify callback called by OpenSSL during chain verification
static int openssl_verify_callback(int /*preverify_ok*/, void* x509_ctx) {
    // Resolve needed symbols from libcrypto at runtime
    void* libcrypto = dlopen("libcrypto.so", RTLD_LAZY);
    if (!libcrypto) return 0; // fail closed

    X509_STORE_CTX_get_current_cert_t fp_get_current = (X509_STORE_CTX_get_current_cert_t)dlsym(libcrypto, "X509_STORE_CTX_get_current_cert");
    i2d_X509_t fp_i2d_X509 = (i2d_X509_t)dlsym(libcrypto, "i2d_X509");
    X509_get_pubkey_t fp_X509_get_pubkey = (X509_get_pubkey_t)dlsym(libcrypto, "X509_get_pubkey");
    i2d_PUBKEY_t fp_i2d_PUBKEY = (i2d_PUBKEY_t)dlsym(libcrypto, "i2d_PUBKEY");
    EVP_PKEY_free_t fp_EVP_PKEY_free = (EVP_PKEY_free_t)dlsym(libcrypto, "EVP_PKEY_free");
    X509_free_t fp_X509_free = (X509_free_t)dlsym(libcrypto, "X509_free");
    SHA256_fn_t fp_SHA256 = (SHA256_fn_t)dlsym(libcrypto, "SHA256");

    if (!fp_get_current || !fp_i2d_X509 || !fp_X509_get_pubkey || !fp_i2d_PUBKEY || !fp_EVP_PKEY_free || !fp_X509_free || !fp_SHA256) {
        dlclose(libcrypto);
        return 0;
    }

    void* cert = fp_get_current(x509_ctx);
    if (!cert) { dlclose(libcrypto); return 0; }

    unsigned char* certbuf = nullptr;
    int certlen = fp_i2d_X509(cert, &certbuf);
    bool ok = false;
    if (certlen > 0 && certbuf) {
        unsigned char digest[32];
        fp_SHA256(certbuf, certlen, digest);
        std::string certB64 = base64_encode_32(digest);
        // compare to CSV
        if (!g_certPinsCsv_global.empty()) {
            std::istringstream iss(g_certPinsCsv_global);
            std::string tok;
            while (std::getline(iss, tok, ',')) {
                size_t p = tok.find("sha256/");
                std::string np = (p==std::string::npos) ? tok : tok.substr(p+7);
                // trim
                while (!np.empty() && isspace((unsigned char)np.front())) np.erase(np.begin());
                while (!np.empty() && isspace((unsigned char)np.back())) np.pop_back();
                if (np == certB64) { ok = true; break; }
            }
        }
        free(certbuf);
    }

    if (!ok && !g_spkiPinsCsv_global.empty()) {
        void* pkey = fp_X509_get_pubkey(cert);
        if (pkey) {
            unsigned char* pkbuf = nullptr;
            int pklen = fp_i2d_PUBKEY(pkey, &pkbuf);
            if (pklen > 0 && pkbuf) {
                unsigned char pdigest[32];
                fp_SHA256(pkbuf, pklen, pdigest);
                std::string pkB64 = base64_encode_32(pdigest);
                std::istringstream iss2(g_spkiPinsCsv_global);
                std::string tok2;
                while (std::getline(iss2, tok2, ',')) {
                    size_t p = tok2.find("sha256/");
                    std::string np = (p==std::string::npos) ? tok2 : tok2.substr(p+7);
                    while (!np.empty() && isspace((unsigned char)np.front())) np.erase(np.begin());
                    while (!np.empty() && isspace((unsigned char)np.back())) np.pop_back();
                    if (np == pkB64) { ok = true; break; }
                }
                free(pkbuf);
            }
            fp_EVP_PKEY_free(pkey);
        }
    }

    dlclose(libcrypto);
    return ok ? 1 : 0; // 1 = verification success
}

// Callback set via CURLOPT_SSL_CTX_FUNCTION; receives SSL_CTX* as second argument
static int ssl_ctx_callback_stub(void* /*curl*/, void* ssl_ctx, void* /*userptr*/) {
    // Resolve OpenSSL function SSL_CTX_set_verify from libssl
    void* libssl = dlopen("libssl.so", RTLD_LAZY);
    if (!libssl) return 1; // can't set, allow
    typedef void (*SSL_CTX_set_verify_t)(void*, int, int(*)(int, void*));
    SSL_CTX_set_verify_t fp_SSL_CTX_set_verify = (SSL_CTX_set_verify_t)dlsym(libssl, "SSL_CTX_set_verify");
    if (!fp_SSL_CTX_set_verify) { dlclose(libssl); return 1; }
    // register our verify callback
    fp_SSL_CTX_set_verify(ssl_ctx, 1 /*SSL_VERIFY_PEER*/, (int(*)(int, void*))openssl_verify_callback);
    dlclose(libssl);
    return 0; // success
}

// write callback for libcurl: append received bytes into std::string
static size_t write_cb_fn(void* ptr, size_t size, size_t nmemb, void* userdata) {
    size_t total = size * nmemb;
    if (userdata) {
        try { ((std::string*)userdata)->append((char*)ptr, total); } catch (...) {}
    }
    return total;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_fluttida_NativeHttp_nativeHttpRequest(
        JNIEnv *env,
        jobject /* this */,
        jstring jmethod,
        jstring jurl,
        jobject jheadersMap,
        jstring jbody,
        jint jtimeoutMs) {
    auto start = std::chrono::steady_clock::now();

    const char* method_c = jmethod ? env->GetStringUTFChars(jmethod, nullptr) : "GET";
    const char* url_c = jurl ? env->GetStringUTFChars(jurl, nullptr) : nullptr;
    const char* body_c = jbody ? env->GetStringUTFChars(jbody, nullptr) : nullptr;

    if (!url_c) {
        std::string err = R"({"status":null,"body":"","durationMs":0,"error":"no url"})";
        return env->NewStringUTF(err.c_str());
    }

    // Convert headers Map<String,String> to vector of strings "Key: Value"
    std::vector<std::string> headers;
    bool insecure = false; // allow overriding TLS verification via pseudo header: X-Curl-Insecure:true
    std::string caInfoPath; // allow overriding CA bundle path via X-Curl-CaInfo: /path/to/cacert.pem
    std::string spkiPinsCsv; // optional pseudo-header X-Curl-SpkiPins: comma-separated base64 pins
    std::string certPinsCsv; // optional pseudo-header X-Curl-CertPins: comma-separated base64 pins
    std::string curlTechnique; // optional pseudo-header X-Curl-Technique: preflight|sslctx|both
    if (jheadersMap) {
        jclass mapCls = env->GetObjectClass(jheadersMap);
        jmethodID entrySetMid = env->GetMethodID(mapCls, "entrySet", "()Ljava/util/Set;");
        jobject entrySetObj = env->CallObjectMethod(jheadersMap, entrySetMid);
        jclass setCls = env->FindClass("java/util/Set");
        jmethodID iteratorMid = env->GetMethodID(setCls, "iterator", "()Ljava/util/Iterator;");
        jobject iterObj = env->CallObjectMethod(entrySetObj, iteratorMid);
        jclass iterCls = env->FindClass("java/util/Iterator");
        jmethodID hasNextMid = env->GetMethodID(iterCls, "hasNext", "()Z");
        jmethodID nextMid = env->GetMethodID(iterCls, "next", "()Ljava/lang/Object;");
        jclass entryCls = env->FindClass("java/util/Map$Entry");
        jmethodID getKeyMid = env->GetMethodID(entryCls, "getKey", "()Ljava/lang/Object;");
        jmethodID getValMid = env->GetMethodID(entryCls, "getValue", "()Ljava/lang/Object;");
        jclass strCls = env->FindClass("java/lang/String");
        while (env->CallBooleanMethod(iterObj, hasNextMid)) {
            jobject entry = env->CallObjectMethod(iterObj, nextMid);
            jstring k = (jstring)env->CallObjectMethod(entry, getKeyMid);
            jstring v = (jstring)env->CallObjectMethod(entry, getValMid);
            const char* kc = k ? env->GetStringUTFChars(k, nullptr) : "";
            const char* vc = v ? env->GetStringUTFChars(v, nullptr) : "";
            // special pseudo header to control TLS verification without changing JNI signature
            if (kc && (std::string(kc) == "X-Curl-Insecure")) {
                insecure = (std::string(vc) == "true" || std::string(vc) == "1" || std::string(vc) == "TRUE");
            } else if (kc && (std::string(kc) == "X-Curl-CaInfo")) {
                caInfoPath = vc ? std::string(vc) : std::string();
            } else if (kc && (std::string(kc) == "X-Curl-SpkiPins")) {
                spkiPinsCsv = vc ? std::string(vc) : std::string();
            } else if (kc && (std::string(kc) == "X-Curl-CertPins")) {
                certPinsCsv = vc ? std::string(vc) : std::string();
            } else if (kc && (std::string(kc) == "X-Curl-Technique")) {
                curlTechnique = vc ? std::string(vc) : std::string();
            } else {
                headers.emplace_back(std::string(kc) + ": " + std::string(vc));
            }
            if (k) env->ReleaseStringUTFChars(k, kc);
            if (v) env->ReleaseStringUTFChars(v, vc);
            env->DeleteLocalRef(entry);
        }
        env->DeleteLocalRef(entrySetObj);
        env->DeleteLocalRef(iterObj);
        env->DeleteLocalRef(mapCls);
        env->DeleteLocalRef(setCls);
        env->DeleteLocalRef(iterCls);
        env->DeleteLocalRef(entryCls);
        env->DeleteLocalRef(strCls);
    }

    // Dynamically load libcurl
    void* lib = dlopen("libcurl.so", RTLD_NOW);
    if (!lib) {
        auto ms = (int)std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start).count();
        const char* dlerr = dlerror();
        std::string err = std::string("{\"status\":null,\"body\":\"\",\"durationMs\":") + std::to_string(ms) +
                          ",\"error\":\"libcurl.so not found: ";
        if (dlerr) err += dlerr;
        err += "\"}";
        if (jmethod) env->ReleaseStringUTFChars(jmethod, method_c);
        if (jurl) env->ReleaseStringUTFChars(jurl, url_c);
        if (jbody) env->ReleaseStringUTFChars(jbody, body_c);
        return env->NewStringUTF(err.c_str());
    }

    typedef void* (*curl_easy_init_t)();
    typedef int (*curl_easy_setopt_t)(void*, int, ...);
    typedef int (*curl_easy_perform_t)(void*);
    typedef void (*curl_easy_cleanup_t)(void*);
    typedef void* (*curl_slist_append_t)(void*, const char*);
    typedef void (*curl_slist_free_all_t)(void*);
    typedef int (*curl_easy_getinfo_t)(void*, int, ...);
    typedef const char* (*curl_easy_strerror_t)(int);

    auto curl_easy_init = (curl_easy_init_t)dlsym(lib, "curl_easy_init");
    auto curl_easy_setopt = (curl_easy_setopt_t)dlsym(lib, "curl_easy_setopt");
    auto curl_easy_perform = (curl_easy_perform_t)dlsym(lib, "curl_easy_perform");
    auto curl_easy_cleanup = (curl_easy_cleanup_t)dlsym(lib, "curl_easy_cleanup");
    auto curl_slist_append = (curl_slist_append_t)dlsym(lib, "curl_slist_append");
    auto curl_slist_free_all = (curl_slist_free_all_t)dlsym(lib, "curl_slist_free_all");
    auto curl_easy_getinfo = (curl_easy_getinfo_t)dlsym(lib, "curl_easy_getinfo");
    auto curl_easy_strerror = (curl_easy_strerror_t)dlsym(lib, "curl_easy_strerror");

    if (!curl_easy_init || !curl_easy_setopt || !curl_easy_perform || !curl_easy_cleanup ||
        !curl_slist_append || !curl_slist_free_all || !curl_easy_getinfo) {
        auto ms = (int)std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start).count();
        std::string err = std::string("{\"status\":null,\"body\":\"\",\"durationMs\":") + std::to_string(ms) +
                          ",\"error\":\"libcurl symbols missing\"}";
        // dlclose(lib); // Keep loaded to avoid OpenSSL TLS destructor crash
        if (jmethod) env->ReleaseStringUTFChars(jmethod, method_c);
        if (jurl) env->ReleaseStringUTFChars(jurl, url_c);
        if (jbody) env->ReleaseStringUTFChars(jbody, body_c);
        return env->NewStringUTF(err.c_str());
    }

    void* curl = curl_easy_init();
    if (!curl) {
        auto ms = (int)std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start).count();
        std::string err = std::string("{\"status\":null,\"body\":\"\",\"durationMs\":") + std::to_string(ms) +
                          ",\"error\":\"curl_easy_init failed\"}";
        // dlclose(lib); // Keep loaded to avoid OpenSSL TLS destructor crash
        if (jmethod) env->ReleaseStringUTFChars(jmethod, method_c);
        if (jurl) env->ReleaseStringUTFChars(jurl, url_c);
        if (jbody) env->ReleaseStringUTFChars(jbody, body_c);
        return env->NewStringUTF(err.c_str());
    }

    std::string resp;

    // CURLOPT codes (from curl/curl.h); using literal ints to avoid including headers
    const int CURLOPT_URL = 10002;
    const int CURLOPT_WRITEFUNCTION = 20011;
    const int CURLOPT_WRITEDATA = 10001;
    const int CURLOPT_HTTPHEADER = 10023;
    const int CURLOPT_POSTFIELDS = 10015;
    const int CURLOPT_POSTFIELDSIZE = 60;
    const int CURLOPT_CUSTOMREQUEST = 10036;
    const int CURLOPT_CONNECTTIMEOUT_MS = 156;
    const int CURLOPT_TIMEOUT_MS = 155;
    const int CURLOPT_SSL_VERIFYPEER = 64;
    const int CURLOPT_SSL_VERIFYHOST = 81;
    const int CURLOPT_CAINFO = 10065; // string: path to CA bundle file

    const int CURLINFO_RESPONSE_CODE = 2097154;

    curl_easy_setopt(curl, CURLOPT_URL, url_c);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_cb_fn);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &resp);

    // method and body
    std::string method(method_c);
    if (method != "GET" && method != "HEAD") {
        if (body_c) {
            curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body_c);
            curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, (long)strlen(body_c));
        } else {
            // for non-GET without body, still set custom method
            curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, method_c);
        }
    } else if (method == "HEAD") {
        curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "HEAD");
    }

    // headers
    void* header_list = nullptr;
    for (const auto& h : headers) {
        header_list = curl_slist_append(header_list, h.c_str());
    }
    if (header_list) curl_easy_setopt(curl, CURLOPT_HTTPHEADER, header_list);

    // timeouts
    if (jtimeoutMs > 0) {
        curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS, (long)jtimeoutMs);
        curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, (long)jtimeoutMs);
    }

    // TLS verification (on by default; can be disabled via X-Curl-Insecure:true)
    if (insecure) {
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0L);
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 0L);
    } else {
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 2L);
    }

    // Optional CA bundle override
    if (!caInfoPath.empty()) {
        curl_easy_setopt(curl, CURLOPT_CAINFO, caInfoPath.c_str());
    }

    // Decide technique toggles
    bool want_preflight = false;
    bool want_sslctx = false;
    if (!curlTechnique.empty()) {
        if (curlTechnique == "preflight") want_preflight = true;
        else if (curlTechnique == "sslctx") want_sslctx = true;
        else /*both or unknown*/ { want_preflight = true; want_sslctx = true; }
    } else {
        // default when pins present and no explicit technique: both
        want_preflight = true; want_sslctx = true;
    }

    // If pin pseudo-headers provided and sslctx desired, register SSL_CTX callback with libcurl
    if ((!spkiPinsCsv.empty() || !certPinsCsv.empty()) && want_sslctx) {
        g_spkiPinsCsv_global = spkiPinsCsv;
        g_certPinsCsv_global = certPinsCsv;
        // CURLOPT_SSL_CTX_FUNCTION = 352, CURLOPT_SSL_CTX_DATA = 353
        curl_easy_setopt(curl, 352, (void*)ssl_ctx_callback_stub);
        curl_easy_setopt(curl, 353, nullptr);
    }

    // If pinning pseudo-headers present and preflight desired, perform native pre-flight verification
    bool pin_ok = true;
    if ((!spkiPinsCsv.empty() || !certPinsCsv.empty()) && want_preflight) {
        // parse host and port
        std::string urlstr(url_c);
        std::string host;
        int port = 443;
        size_t pos = urlstr.find("://");
        size_t start = (pos==std::string::npos) ? 0 : pos+3;
        size_t slash = urlstr.find_first_of("/", start);
        std::string authority = (slash==std::string::npos) ? urlstr.substr(start) : urlstr.substr(start, slash-start);
        size_t colon = authority.find(':');
        if (colon!=std::string::npos) {
            host = authority.substr(0, colon);
            try { port = std::stoi(authority.substr(colon+1)); } catch(...) { port = 443; }
        } else {
            host = authority;
        }

        if (urlstr.rfind("https://", 0) == 0) {
            // Try to load libssl and libcrypto
            void* libssl = dlopen("libssl.so", RTLD_LAZY);
            void* libcrypto = dlopen("libcrypto.so", RTLD_LAZY);
            if (!libssl || !libcrypto) {
                // Fallback: call Java verifier (existing method) if OpenSSL not available
                jclass cls = env->FindClass("com/example/fluttida/MainActivity");
                if (cls) {
                    jmethodID mid = env->GetStaticMethodID(cls, "verifyHostPins", "(Ljava/lang/String;ILjava/lang/String;Ljava/lang/String;)Z");
                    if (mid) {
                        jstring jhost = env->NewStringUTF(host.c_str());
                        jstring jspki = env->NewStringUTF(spkiPinsCsv.c_str());
                        jstring jcerts = env->NewStringUTF(certPinsCsv.c_str());
                        jboolean res = env->CallStaticBooleanMethod(cls, mid, jhost, (jint)port, jspki, jcerts);
                        pin_ok = (res == JNI_TRUE);
                        env->DeleteLocalRef(jhost);
                        env->DeleteLocalRef(jspki);
                        env->DeleteLocalRef(jcerts);
                    }
                    env->DeleteLocalRef(cls);
                }
                if (libssl) dlclose(libssl);
                if (libcrypto) dlclose(libcrypto);
            } else {
                // Resolve required OpenSSL symbols via dlsym
                typedef const void* (*TLS_client_method_t)();
                typedef void* (*SSL_CTX_new_t)(const void*);
                typedef void* (*SSL_new_t)(void*);
                typedef int (*SSL_set_tlsext_host_name_t)(void*, const char*);
                typedef int (*SSL_set_fd_t)(void*, int);
                typedef int (*SSL_connect_t)(void*);
                typedef void (*SSL_free_t)(void*);
                typedef void (*SSL_CTX_free_t)(void*);
                typedef void* (*SSL_get_peer_certificate_t)(void*);
                typedef void* (*X509_get_pubkey_t)(void*);
                typedef int (*i2d_X509_t)(void*, unsigned char**);
                typedef int (*i2d_PUBKEY_t)(void*, unsigned char**);
                typedef void (*X509_free_t)(void*);
                typedef void (*EVP_PKEY_free_t)(void*);
                typedef unsigned char* (*SHA256_t)(const unsigned char*, size_t, unsigned char*);

                TLS_client_method_t TLS_client_method = (TLS_client_method_t)dlsym(libssl, "TLS_client_method");
                SSL_CTX_new_t SSL_CTX_new = (SSL_CTX_new_t)dlsym(libssl, "SSL_CTX_new");
                SSL_new_t SSL_new = (SSL_new_t)dlsym(libssl, "SSL_new");
                SSL_set_tlsext_host_name_t SSL_set_tlsext_host_name = (SSL_set_tlsext_host_name_t)dlsym(libssl, "SSL_set_tlsext_host_name");
                SSL_set_fd_t SSL_set_fd = (SSL_set_fd_t)dlsym(libssl, "SSL_set_fd");
                SSL_connect_t SSL_connect = (SSL_connect_t)dlsym(libssl, "SSL_connect");
                SSL_free_t SSL_free = (SSL_free_t)dlsym(libssl, "SSL_free");
                SSL_CTX_free_t SSL_CTX_free = (SSL_CTX_free_t)dlsym(libssl, "SSL_CTX_free");
                SSL_get_peer_certificate_t SSL_get_peer_certificate = (SSL_get_peer_certificate_t)dlsym(libssl, "SSL_get_peer_certificate");

                i2d_X509_t i2d_X509 = (i2d_X509_t)dlsym(libcrypto, "i2d_X509");
                X509_get_pubkey_t X509_get_pubkey = (X509_get_pubkey_t)dlsym(libcrypto, "X509_get_pubkey");
                i2d_PUBKEY_t i2d_PUBKEY = (i2d_PUBKEY_t)dlsym(libcrypto, "i2d_PUBKEY");
                X509_free_t X509_free = (X509_free_t)dlsym(libcrypto, "X509_free");
                EVP_PKEY_free_t EVP_PKEY_free = (EVP_PKEY_free_t)dlsym(libcrypto, "EVP_PKEY_free");
                SHA256_t SHA256_fn = (SHA256_t)dlsym(libcrypto, "SHA256");

                bool have_all = TLS_client_method && SSL_CTX_new && SSL_new && SSL_set_tlsext_host_name && SSL_set_fd && SSL_connect && SSL_free && SSL_CTX_free && SSL_get_peer_certificate && i2d_X509 && X509_get_pubkey && i2d_PUBKEY && X509_free && EVP_PKEY_free && SHA256_fn;
                if (!have_all) {
                    // Fallback to Java verifier if any symbol missing
                    jclass cls = env->FindClass("com/example/fluttida/MainActivity");
                    if (cls) {
                        jmethodID mid = env->GetStaticMethodID(cls, "verifyHostPins", "(Ljava/lang/String;ILjava/lang/String;Ljava/lang/String;)Z");
                        if (mid) {
                            jstring jhost = env->NewStringUTF(host.c_str());
                            jstring jspki = env->NewStringUTF(spkiPinsCsv.c_str());
                            jstring jcerts = env->NewStringUTF(certPinsCsv.c_str());
                            jboolean res = env->CallStaticBooleanMethod(cls, mid, jhost, (jint)port, jspki, jcerts);
                            pin_ok = (res == JNI_TRUE);
                            env->DeleteLocalRef(jhost);
                            env->DeleteLocalRef(jspki);
                            env->DeleteLocalRef(jcerts);
                        }
                        env->DeleteLocalRef(cls);
                    }
                } else {
                    // TCP connect
                    int sock = -1;
                    struct addrinfo hints{};
                    struct addrinfo* res0 = nullptr;
                    hints.ai_family = AF_UNSPEC;
                    hints.ai_socktype = SOCK_STREAM;
                    char portbuf[8];
                    snprintf(portbuf, sizeof(portbuf), "%d", port);
                    if (getaddrinfo(host.c_str(), portbuf, &hints, &res0) == 0) {
                        for (struct addrinfo* rp = res0; rp != nullptr; rp = rp->ai_next) {
                            sock = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
                            if (sock < 0) continue;
                            if (connect(sock, rp->ai_addr, rp->ai_addrlen) == 0) break;
                            close(sock);
                            sock = -1;
                        }
                        freeaddrinfo(res0);
                    }

                    if (sock >= 0) {
                        // SSL handshake
                        const void* method = TLS_client_method();
                        void* ctx = SSL_CTX_new(method);
                        if (ctx) {
                            void* ssl = SSL_new(ctx);
                            if (ssl) {
                                SSL_set_tlsext_host_name(ssl, host.c_str());
                                SSL_set_fd(ssl, sock);
                                if (SSL_connect(ssl) == 1) {
                                    void* peer = SSL_get_peer_certificate(ssl);
                                    if (peer) {
                                        // cert DER
                                        unsigned char* certbuf = nullptr;
                                        int certlen = i2d_X509(peer, &certbuf);
                                        if (certlen > 0 && certbuf) {
                                            unsigned char digest[32];
                                            SHA256_fn(certbuf, certlen, digest);
                                            // base64 encode
                                            static const char b64[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
                                            char b64out[48];
                                            int outlen = 0;
                                            unsigned int val = 0;
                                            int valb = -6;
                                            for (int i = 0; i < 32; ++i) {
                                                val = (val << 8) + digest[i];
                                                valb += 8;
                                                while (valb >= 0) {
                                                    b64out[outlen++] = b64[(val >> valb) & 0x3F];
                                                    valb -= 6;
                                                }
                                            }
                                            if (valb > -6) b64out[outlen++] = b64[((val << 8) >> (valb + 8)) & 0x3F];
                                            while (outlen % 4) b64out[outlen++] = '=';
                                            b64out[outlen] = '\0';
                                            std::string certB64(b64out, outlen);

                                            // compare to provided cert pins
                                            bool match = false;
                                            if (!certPinsCsv.empty()) {
                                                std::istringstream iss(certPinsCsv);
                                                std::string token;
                                                while (std::getline(iss, token, ',')) {
                                                    // normalize
                                                    size_t pos = token.find("sha256/");
                                                    std::string np = (pos==std::string::npos) ? token : token.substr(pos+7);
                                                    // trim
                                                    while (!np.empty() && isspace((unsigned char)np.front())) np.erase(np.begin());
                                                    while (!np.empty() && isspace((unsigned char)np.back())) np.pop_back();
                                                    if (np == certB64) { match = true; break; }
                                                }
                                            }

                                            // SPKI check
                                            if (!match && !spkiPinsCsv.empty()) {
                                                void* pkey = X509_get_pubkey(peer);
                                                if (pkey) {
                                                    unsigned char* pkbuf = nullptr;
                                                    int pklen = i2d_PUBKEY(pkey, &pkbuf);
                                                    if (pklen > 0 && pkbuf) {
                                                        unsigned char pdigest[32];
                                                        SHA256_fn(pkbuf, pklen, pdigest);
                                                        char b64pk[48];
                                                        int outlen2 = 0;
                                                        unsigned int val2 = 0;
                                                        int valb2 = -6;
                                                        for (int i = 0; i < 32; ++i) {
                                                            val2 = (val2 << 8) + pdigest[i];
                                                            valb2 += 8;
                                                            while (valb2 >= 0) {
                                                                b64pk[outlen2++] = b64[(val2 >> valb2) & 0x3F];
                                                                valb2 -= 6;
                                                            }
                                                        }
                                                        if (valb2 > -6) b64pk[outlen2++] = b64[((val2 << 8) >> (valb2 + 8)) & 0x3F];
                                                        while (outlen2 % 4) b64pk[outlen2++] = '=';
                                                        b64pk[outlen2] = '\0';
                                                        std::string pkB64(b64pk, outlen2);
                                                        std::istringstream iss2(spkiPinsCsv);
                                                        std::string token2;
                                                        while (std::getline(iss2, token2, ',')) {
                                                            size_t pos = token2.find("sha256/");
                                                            std::string np = (pos==std::string::npos) ? token2 : token2.substr(pos+7);
                                                            while (!np.empty() && isspace((unsigned char)np.front())) np.erase(np.begin());
                                                            while (!np.empty() && isspace((unsigned char)np.back())) np.pop_back();
                                                            if (np == pkB64) { match = true; break; }
                                                        }
                                                        if (pkbuf) free(pkbuf);
                                                    }
                                                    EVP_PKEY_free(pkey);
                                                }
                                            }

                                            if (!match) pin_ok = false;

                                            if (certbuf) free(certbuf);
                                        }
                                        X509_free(peer);
                                    }
                                }
                                SSL_free(ssl);
                            }
                            SSL_CTX_free(ctx);
                        }
                        close(sock);
                    }
                }

                if (libssl) dlclose(libssl);
                if (libcrypto) dlclose(libcrypto);
            }
        }
    }

    if (!pin_ok) {
        if (header_list) curl_slist_free_all(header_list);
        curl_easy_cleanup(curl);
        int durationMs = (int)std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start).count();
        std::ostringstream out;
        out << "{\"status\":null,\"body\":\"\",\"durationMs\":" << durationMs << ",\"error\":\"SSL pinning mismatch\"}";
        if (jmethod) env->ReleaseStringUTFChars(jmethod, method_c);
        if (jurl) env->ReleaseStringUTFChars(jurl, url_c);
        if (jbody) env->ReleaseStringUTFChars(jbody, body_c);
        std::string json = out.str();
        return env->NewStringUTF(json.c_str());
    }

    int rc = curl_easy_perform(curl);
    long status = -1;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status);

    if (header_list) curl_slist_free_all(header_list);
    curl_easy_cleanup(curl);
    // dlclose(lib); // Keep loaded to avoid OpenSSL TLS destructor crash

    int durationMs = (int)std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start).count();

    std::ostringstream out;
    if (rc == 0) {
        out << "{\"status\":" << status << ",\"body\":";
        // JSON-escape resp minimal
        out << "\"";
        for (char c : resp) {
            switch (c) {
                case '\\': out << "\\\\"; break;
                case '"': out << "\\\""; break;
                case '\n': out << "\\n"; break;
                case '\r': out << "\\r"; break;
                case '\t': out << "\\t"; break;
                default: out << c; break;
            }
        }
        out << "\",";
        out << "\"durationMs\":" << durationMs << ",\"error\":null}";
    } else {
        out << "{\"status\":null,\"body\":\"\",\"durationMs\":" << durationMs << ",\"error\":\"curl_easy_perform rc=" << rc;
        if (curl_easy_strerror) {
            const char* es = curl_easy_strerror(rc);
            if (es) {
                out << " (";
                // minimal JSON escape for the error string
                for (const char* p = es; *p; ++p) {
                    char c = *p;
                    switch (c) {
                        case '\\': out << "\\\\"; break;
                        case '"': out << "\\\""; break;
                        case '\n': out << "\\n"; break;
                        case '\r': out << "\\r"; break;
                        case '\t': out << "\\t"; break;
                        default: out << c; break;
                    }
                }
                out << ")";
            }
        }
        out << "\"}";
    }

    if (jmethod) env->ReleaseStringUTFChars(jmethod, method_c);
    if (jurl) env->ReleaseStringUTFChars(jurl, url_c);
    if (jbody) env->ReleaseStringUTFChars(jbody, body_c);

    std::string json = out.str();
    return env->NewStringUTF(json.c_str());
}
