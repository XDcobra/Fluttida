Plan: Android-wide SSL Pinning Toggle

Centralize a single global pinning config (on/off + pins) in Dart, pass it into all Android HTTP stacks (HttpURLConnection, OkHttp, Cronet, JNI libcurl) via MethodChannel, and enforce per stack with native hooks while keeping existing TLS verification defaults.

Steps
1) Add pinning config model + global toggle in example_app/fluttida/lib/lab_screen.dart and plumb through request config to StacksImpl. Support both SPKI (public-key) and full cert SHA-256 pins (base64) in the config and UI.
2) Extend MethodChannel payloads in example_app/fluttida/lib/stacks for androidHttpURLConnection, androidOkHttp, androidCronet, androidNativeCurl to include pinning on/off and pin lists.
3) Implement pin checks in example_app/fluttida/android/app/src/main/kotlin/com/fingersdirt/fluttida/MainActivity.kt: custom TrustManager/HostnameVerifier for HttpURLConnection; OkHttp CertificatePinner with sha256/SPKI pins; Cronet apply pins only if API available, else warn and skip; forward pins to the native curl bridge.
4) Add pin enforcement in example_app/fluttida/android/app/src/main/cpp/native_http.cpp using libcurl options (e.g., CURLOPT_PINNEDPUBLICKEY) while keeping existing CA/insecure flags.
5) Document usage and toggle behavior in example_app/fluttida/README.md, including supported pin formats, global toggle semantics, stack-specific behavior, and the Cronet warning when pinning is unsupported. Note that iOS support will follow the same global config.

Further Considerations
1) Pin storage: base64 SHA-256 for SPKI and full cert hash; clarify encoding in the UI.
2) No per-stack overrides—only the global toggle/config applies across stacks.
3) Cronet: warn and skip pinning if the build lacks public-key pin APIs (do not fail closed); add a future hook to enable once available.
