if (ObjC.available) {
    var WKWebView = ObjC.classes.WKWebView;
    var loadReq = WKWebView["- loadRequest:"];
    Interceptor.attach(loadReq.implementation, {
        onEnter: function (args) {
            console.log("[WKWebView] loadRequest called");
        }
    });
}
