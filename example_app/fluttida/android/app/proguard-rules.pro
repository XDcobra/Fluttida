## ProGuard / R8 rules to avoid removing optional TLS provider references
## and to suppress warnings about missing provider classes (BouncyCastle, Conscrypt, OpenJSSE).

# Keep OkHttp internals that reflectively reference optional TLS providers
-keep class okhttp3.internal.platform.** { *; }

# If provider classes are absent at runtime, suppress warnings from R8
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**

# Keep provider classes if they are bundled (safe if not present)
-keep class org.bouncycastle.** { *; }
-keep class org.conscrypt.** { *; }
-keep class org.openjsse.** { *; }

# Keep JSSE provider/service definitions if bundled
-keep class org.bouncycastle.jcajce.provider.** { *; }

# Fallback: keep common javax/net/ssl interfaces
-keep class javax.net.ssl.** { *; }

# You can also merge the generated missing_rules.txt contents here if available
# (see build/app/outputs/mapping/release/missing_rules.txt) for more specific rules.