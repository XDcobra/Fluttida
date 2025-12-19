# libcurl for Android NDK (Fluttida)

To enable the native libcurl stack, provide prebuilt `libcurl.so` for the target ABIs.

## Where to place the libraries

Place the shared objects under:

- `example_app/fluttida/android/app/src/main/jniLibs/arm64-v8a/libcurl.so`
- `example_app/fluttida/android/app/src/main/jniLibs/armeabi-v7a/libcurl.so` (optional if you only ship arm64)

Gradle will automatically package these into the APK.

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

After placing the `.so` files:

```bash
cd example_app/fluttida
flutter clean
flutter build apk --release
adb shell ls /data/app/*/lib/* | grep curl || true
```

Run the app and select the "Android NDK (libcurl)" stack. For TLS errors like `rc=60` (peer verification), ensure `cacert.pem` is present as described above.

## CI note

If you want CI builds to include libcurl, commit the `.so` files to the repository (or fetch them during the workflow). Without them, the JNI stack will return `libcurl.so not found`.

## Sources/Binaries

- Prebuilt: search for "curl-android" prebuilts or build from source via the Android NDK toolchain.
- Official source: https://github.com/curl/curl
