# libcurl for Android NDK (Fluttida)

To enable the native libcurl stack, provide prebuilt `libcurl.so` for the target ABIs.

## Where to place the libraries

Place the shared objects under:

- `example_app/fluttida/android/app/src/main/jniLibs/arm64-v8a/libcurl.so`
- `example_app/fluttida/android/app/src/main/jniLibs/armeabi-v7a/libcurl.so` (optional if you only ship arm64)

Gradle will automatically package these into the APK.

## TLS backend

libcurl must be built with a TLS backend (OpenSSL/BoringSSL/wolfSSL/mbedTLS). For Frida hooking, OpenSSL/BoringSSL provides common symbols like `SSL_read`/`SSL_write`.

## Verify locally

After placing the `.so` files:

```bash
cd example_app/fluttida
flutter clean
flutter build apk --release
adb shell ls /data/app/*/lib/* | grep curl || true
```

Run the app and select the "Android NDK (libcurl)" stack.

## CI note

If you want CI builds to include libcurl, commit the `.so` files to the repository (or fetch them during the workflow). Without them, the JNI stack will return `libcurl.so not found`.

## Sources/Binaries

- Prebuilt: search for "curl-android" prebuilts or build from source via the Android NDK toolchain.
- Official source: https://github.com/curl/curl
