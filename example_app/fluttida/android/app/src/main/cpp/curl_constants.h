// curl_constants.h – numeric values for libcurl option/info codes.
//
// These values match the libcurl 8.x public ABI. When upgrading the pinned
// libcurl version (see config/android-libs.versions), cross-check each
// constant against curl/curl.h in the new release and update here if needed.
//
// Source reference: https://curl.se/libcurl/c/curl_easy_setopt.html
//                   https://curl.se/libcurl/c/curl_easy_getinfo.html
#pragma once

// ── curl_easy_setopt options ──────────────────────────────────────────────
static const int CURLOPT_WRITEDATA         = 10001;
static const int CURLOPT_URL               = 10002;
static const int CURLOPT_POSTFIELDS        = 10015;
static const int CURLOPT_HTTPHEADER        = 10023;
static const int CURLOPT_CUSTOMREQUEST     = 10036;
static const int CURLOPT_POSTFIELDSIZE     = 60;
static const int CURLOPT_SSL_VERIFYPEER    = 64;
static const int CURLOPT_SSL_VERIFYHOST    = 81;
static const int CURLOPT_TIMEOUT_MS        = 155;
static const int CURLOPT_CONNECTTIMEOUT_MS = 156;
static const int CURLOPT_WRITEFUNCTION     = 20011;
static const int CURLOPT_CAINFO            = 10065; // path to CA bundle file
static const int CURLOPT_SSL_CTX_FUNCTION  = 20108;
static const int CURLOPT_SSL_CTX_DATA      = 10109;

// ── curl_easy_getinfo codes ───────────────────────────────────────────────
static const int CURLINFO_RESPONSE_CODE    = 2097154;
