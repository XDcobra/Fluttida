if (ObjC.available) {
    // Hook NSURLSession delegate method didReceiveChallenge
    var NSURLSession = ObjC.classes.NSURLSession;
    var NSURLSessionDelegate = ObjC.protocols.NSURLSessionDelegate;

    var NSURLSessionAuthChallengeDisposition = {
        UseCredential: 0,
        PerformDefaultHandling: 1,
        CancelAuthenticationChallenge: 2,
        RejectProtectionSpace: 3
    };

    var NSURLCredential = ObjC.classes.NSURLCredential;

    // Hook NSURLSession:didReceiveChallenge:completionHandler:
    var method = ObjC.classes.NSURLSession["- URLSession:didReceiveChallenge:completionHandler:"];
    if (method) {
        Interceptor.attach(method.implementation, {
            onEnter: function (args) {
                var challenge = new ObjC.Object(args[3]);
                var protectionSpace = challenge.protectionSpace();
                var host = protectionSpace.host().toString();

                console.log("[*] SSL challenge for host: " + host);

                // Create a credential that accepts any certificate
                var credential = NSURLCredential.credentialForTrust_(protectionSpace.serverTrust());
                var block = new ObjC.Block(args[4]);

                block.implementation = function (disposition, credentialArg) {
                    console.log("[*] Overriding SSL pinning, accepting all certs");
                    disposition = NSURLSessionAuthChallengeDisposition.UseCredential;
                    credentialArg = credential;
                    return;
                };
            }
        });
    }

    // Alternative: SecTrustEvaluate hook
    // Hook SecTrustEvaluate via Process.getModuleByName
    const sec = Process.getModuleByName("Security");
    const addrEvaluate = sec.findExportByName("SecTrustEvaluate");
    console.log("SecTrustEvaluate @", addrEvaluate);

    Interceptor.replace(addrEvaluate, new NativeCallback(function (trust, resultPtr) {
		console.log("[*] SecTrustEvaluate called, forcing success");

		// resultPtr is a NativePointer --> here we write the value 0 (kSecTrustResultProceed)
		resultPtr.writeU32(0);  // kSecTrustResultProceed

		return 0; // errSecSuccess
	}, 'int', ['pointer', 'pointer']));
	
	const addrEvaluateWithError = sec.findExportByName("SecTrustEvaluateWithError");
		Interceptor.replace(addrEvaluateWithError, new NativeCallback(function (trust, errorPtr) {
			console.log("[*] SecTrustEvaluateWithError called, forcing success");
			return 1; // true → Zertifikat akzeptiert
		}, 'bool', ['pointer', 'pointer']));
} else {
    console.log("Objective-C runtime not available!");
}
