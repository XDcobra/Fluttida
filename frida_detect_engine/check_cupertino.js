if (ObjC.available) {
    var NSURLSession = ObjC.classes.NSURLSession;
    var delegate = NSURLSession["- dataTaskWithRequest:completionHandler:"];
    Interceptor.attach(delegate.implementation, {
        onEnter: function (args) {
            console.log("[cupertino_http] NSURLSession dataTaskWithRequest called");
        }
    });
}
