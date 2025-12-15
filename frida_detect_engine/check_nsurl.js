// NSURLConnection
if (ObjC.available) {
    var NSURLConnection = ObjC.classes.NSURLConnection;
    var sendRequest = NSURLConnection["+ sendSynchronousRequest:returningResponse:error:"];
    Interceptor.attach(sendRequest.implementation, {
        onEnter: function (args) {
            console.log("[NSURLConnection] sendSynchronousRequest called");
        }
    });
}

// CFURLConnection
const cfConn = Module.findExportByName("CFNetwork", "CFURLConnectionCreateWithRequest");
if (cfConn) {
    Interceptor.attach(cfConn, {
        onEnter: function (args) {
            console.log("[CFURLConnection] CFURLConnectionCreateWithRequest called");
        }
    });
}
