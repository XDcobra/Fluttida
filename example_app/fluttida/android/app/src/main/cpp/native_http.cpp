#include <jni.h>
#include <string>
#include <sstream>
#include <vector>
#include <android/log.h>
#include <dlfcn.h>
#include <chrono>
#include <cstring>

#define LOG_TAG "FluttidaNativeHttp"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

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
