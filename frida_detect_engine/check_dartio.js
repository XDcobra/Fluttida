const libsystem = Process.getModuleByName("libsystem_kernel.dylib");
const connectPtr = libsystem.findExportByName("connect");

Interceptor.attach(connectPtr, {
    onEnter: function (args) {
        var sockaddr = args[1];
        var familyLE = sockaddr.readU16();
        var family = ((familyLE & 0xFF) << 8) | (familyLE >> 8);
        if (family === 2 || family === 30) {
            console.log("[dart:io HttpClient] connect() called");
        }
    }
});
