# libcurl for Android NDK (Fluttida)

Fluttida now uses the prebuilt Maven artifact `com.xdcobra.libcurl:libcurl-openssl`.
The old manual `jniLibs` copy flow is no longer required.

## Version pinning

The pinned Android libcurl version is defined in:

- `example_app/fluttida/config/android-libs.versions`

Current key:

- `libcurl_openssl_version=<version>`

`android/app/build.gradle.kts` reads this file and resolves the AAR dependency automatically.

## Native libraries

`libcurl.so` is pulled from Maven via the AAR and packaged by Gradle for supported ABIs.
Do not manually copy `libcurl.so`, `libssl.so`, or `libcrypto.so` into `android/app/src/main/jniLibs`.

## curl headers for JNI build

The C++ JNI module still compiles against vendored curl headers in:

- `android/app/src/main/cpp/third_party/curl/include/...`

These are treated as source headers for compile-time only. Runtime libraries come from Maven.

## TLS backend

libcurl must be built with a TLS backend (OpenSSL/BoringSSL/wolfSSL/mbedTLS). For Frida hooking, OpenSSL/BoringSSL provides common symbols like `SSL_read`/`SSL_write`.

### CA bundle (recommended)

libcurl+OpenSSL on Android does not automatically use the Java/Android trust store. You should ship a CA bundle and keep certificate verification enabled:

- Place `cacert.pem` (Mozilla bundle, e.g. https://curl.se/ca/cacert.pem) at
	`example_app/fluttida/android/app/src/main/assets/cacert.pem`.
- On startup, the app copies this file to the cache folder and passes the path to the native curl layer via `CURLOPT_CAINFO` automatically.
- You can override the path yourself by setting the header `X-Curl-CaInfo: /full/path/to/cacert.pem`.
- For debugging only, there is the header `X-Curl-Insecure: true` which disables certificate verification (never for production).

## Verify locally

Build Android as usual:

```bash
cd example_app/fluttida
flutter clean
flutter build apk --release
```

Run the app and select the "Android NDK (libcurl)" stack. For TLS errors like `rc=60` (peer verification), ensure `cacert.pem` is present as described above.

## Sources/Binaries

- Prebuilt: search for "curl-android" prebuilts or build from source via the Android NDK toolchain.
- Official source: https://github.com/curl/curl
