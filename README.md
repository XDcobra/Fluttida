# Fluttida – Intercepting Flutter App Traffic with Frida
This repository provides tools and Frida scripts to analyze, intercept and forward network traffic from Flutter applications via Frida. Because Flutter often bypasses system proxy settings and uses custom networking stacks, standard proxy interception fails. The scripts here help identify which client (e.g. `dart:io`, `NSURLSession`, `NSURLConnection`, or `WKWebView`) is in use and redirect traffic through a proxy for effective reverse engineering.

<div align="center">
  <img src="docs/fluttida-banner.png" alt="Fluttida - Proxy Interception for Flutter Apps via Frida" width=60%" />

  <p>
    <img src="https://img.shields.io/badge/Flutter-3.x-blue?style=flat&logo=flutter" alt="Flutter Version" />
    <img src="https://img.shields.io/badge/Frida-17.x-red?style=flat&logo=frida" alt="Frida Version" />
    <img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey" alt="Platform" />
    <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License" />
    <img src="https://img.shields.io/badge/proxy-support%20via%20Frida-blue" alt="Proxy Support via Frida" />
  </p>
</div>


## Quick Start

1. **Install mitmproxy or Burp Suite** on your analysis machine.  
2. **Export and install the proxy’s CA certificate** on your iOS device, then enable full trust under *Settings --> General --> About --> Certificate Trust Settings*.  
3. **Configure your iPhone’s Wi‑Fi proxy manually** to point to your machine’s IP and chosen port (e.g. `192.168.1.5:8889`).  
4. **Run the proxy** in standard mode (`mitmproxy -p 8889`) or Burp with an “Invisible Proxy” listener.  
5. **Use Frida hooks** to redirect Dart’s `connect()` calls to the proxy (e.g. `frida -n YourApp -l intercept_dartio.js`)
6. **Refresh the app** and watch requests appear in your proxy.  
7. If traffic is still missing, check which networking stack the app uses by running any of the scripts within the [frida_detect_engine](frida_detect_engine) folder ([Dart:io](frida_detect_engine/check_dartio.js), [Cupertino/NSURLSession](frida_detect_engine/check_cupertino.js), [NSURLConnection](frida_detect_engine/check_nsurl.js), [WKWebView](frida_detect_engine/check_webview.js)) and apply the corresponding hook.

---

## Why Flutter Apps Cannot Be Intercepted with a Standard Proxy

Flutter simplifies cross‑platform development, but when it comes to network traffic, it introduces complexities that make traditional proxy interception unreliable. This document explains in detail why Flutter apps often bypass normal proxy setups, the technical background behind it, and what approaches can still work.

---

### Overview

Flutter apps can use different networking stacks depending on the code path. The most common is the Dart‑based `dart:io` HttpClient. Unlike native iOS/Android clients, `dart:io` often ignores system proxy settings and does not perform the expected proxy handshake, which breaks standard interception with tools like Burp or mitmproxy.

- **Core issue:** Many Flutter apps connect directly to target hosts without sending a CONNECT request to the proxy.  
- **Result:** Proxies see no traffic, TLS connections fail, or only raw socket streams appear without host context.  
- **Workarounds:** Transparent interception (NAT/pf/iptables), manual proxy configuration plus hooks, installing custom CA certificates, and bypassing certificate pinning.


This repo includes several scripts to make reverse engineering of flutter APIs easier.
| Engine    | Check what Engine Scripts                                     | Intercept Script                             |
|-----------|---------------------------------------------------------------|----------------------------------------------|
| Dart:io   | [check_dartio.js](frida_detect_engine/check_dartio.js)        | [intercept_dartio.js](intercept_dartio.js)   |
| Cupertino | [check_cupertino.js](frida_detect_engine/check_cupertino.js)  | Coming soon!                                 |
| NSURL     | [check_nsurl.js](frida_detect_engine/check_nsurl.js)          | Coming soon!                                 |
| WebView   | [check_webview.js](frida_detect_engine/check_webview.js)      | Coming soon!                                 |

---

### Technical Background

#### Dart:io HttpClient vs. Standard Proxy Usage
- No CONNECT handshake unless explicitly configured.  
- System proxy often ignored.  
- Direct socket calls bypass proxy‑aware APIs.

#### Alternative Stacks
- **Cupertino HTTP (NSURLSession)** – may respect system proxy, but often configured to bypass.  
- **WebView (WKWebView)** – traffic depends on WebKit and system settings.  
- **Native bridges** – custom ObjC/Swift/Java networking stacks may ignore proxy.

#### TLS, HTTP/2, Certificates, and Pinning
- Direct TLS connections cannot be intercepted by a standard proxy.  
- HTTP/2 and ALPN negotiation requires proper TLS termination.  
- ATS and certificate pinning block interception unless bypassed.  
- IPv6 and QUIC/HTTP/3 introduce additional challenges.

---

### Symptoms in Practice
- Proxy shows no traffic.  
- mitmproxy transparent mode errors (“cannot resolve original destination”).  
- TLS handshake failures.  
- Partial visibility (only WebView traffic intercepted).

---

### Working Approaches

#### System Proxy + Hooks
- Manual proxy in Wi‑Fi settings.  
- Frida hook on `connect()` to force Dart traffic through proxy.  
- Install and trust proxy CA.  
- Bypass certificate pinning.

#### Transparent Interception (Linux/macOS)
- Use `pf` or `iptables` to redirect traffic.  
- Run mitmproxy in transparent mode.  
- On Windows, use WSL or Burp Invisible Proxy mode.

---

### Detecting Which Stack Is Used
- **Dart:io:** Hook `connect()` in `libsystem_kernel.dylib`.  
- **Cupertino/NSURLSession:** Hook `-[NSURLSession dataTaskWithRequest:completionHandler:]`.  
- **NSURLConnection/CFNetwork:** Hook `+[NSURLConnection sendSynchronousRequest:returningResponse:error:]` or `CFURLConnectionCreateWithRequest`.  
- **WebView:** Hook `-[WKWebView loadRequest:]`.

---

### Best Practices
- Choose the right proxy mode.  
- Support IPv6.  
- Trust CA certificates.  
- Plan for pinning bypass.  
- Account for Windows limitations.
