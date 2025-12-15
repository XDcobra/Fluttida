const libsystem = Process.getModuleByName("libsystem_kernel.dylib");
const connectPtr = libsystem.findExportByName("connect");

Interceptor.attach(connectPtr, {
    onEnter: function (args) {
        var sockaddr = args[1];
        var familyLE = sockaddr.readU16();
        var family = ((familyLE & 0xFF) << 8) | (familyLE >> 8);

        if (family === 2) { // AF_INET (IPv4)
            var port = sockaddr.add(2).readU16();
            var ip = [
                sockaddr.add(4).readU8(),
                sockaddr.add(5).readU8(),
                sockaddr.add(6).readU8(),
                sockaddr.add(7).readU8()
            ].join(".");
            var hostPort = ((port & 0xFF) << 8) | (port >> 8);

            console.log("[dart:io HttpClient] connect --> " + ip + ":" + hostPort);

            // Redirect to proxy (IPv4)
            var proxyHost = "192.168.1.5";    // TODO Replace with your proxy IP
            var proxyPort = 8889;             // TODO Replace with your proxy port
            sockaddr.writeU8(2); // AF_INET
            sockaddr.add(2).writeU16((proxyPort >> 8) | ((proxyPort & 0xFF) << 8)); // htons
            var parts = proxyHost.split(".");
            sockaddr.add(4).writeU8(parseInt(parts[0]));
            sockaddr.add(5).writeU8(parseInt(parts[1]));
            sockaddr.add(6).writeU8(parseInt(parts[2]));
            sockaddr.add(7).writeU8(parseInt(parts[3]));

            console.log("[dart:io HttpClient] Redirected to proxy (IPv4) " + proxyHost + ":" + proxyPort);
        }

        else if (family === 30) { // AF_INET6 (IPv6)
            var port = sockaddr.add(2).readU16();
            var hostPort = ((port & 0xFF) << 8) | (port >> 8);

            // IPv6 address is 16 bytes starting at offset 8
            var ip6 = [];
            for (var i = 0; i < 16; i += 2) {
                var segment = (sockaddr.add(8 + i).readU8() << 8) | sockaddr.add(8 + i + 1).readU8();
                ip6.push(segment.toString(16));
            }
            console.log("[dart:io HttpClient] connect --> [" + ip6.join(":") + "]:" + hostPort);

            // Redirect to proxy (IPv6 loopback → mapped to IPv4 proxy)
            var proxyPort = 8889;           // TODO Replace with your proxy port
            sockaddr.writeU8(30); // AF_INET6
            sockaddr.add(2).writeU16((proxyPort >> 8) | ((proxyPort & 0xFF) << 8)); // htons

            // ::ffff:192.168.1.5 (IPv4-mapped IPv6)
            var ipv4 = [192, 168, 1, 5];    // TODO Replace with your proxy IPv4 parts
            // Write ::ffff:192.168.1.5 into sockaddr
            for (var i = 0; i < 10; i++) sockaddr.add(8 + i).writeU8(0x00); // leading zeros
            sockaddr.add(18).writeU8(0xff);
            sockaddr.add(19).writeU8(0xff);
            sockaddr.add(20).writeU8(ipv4[0]);
            sockaddr.add(21).writeU8(ipv4[1]);
            sockaddr.add(22).writeU8(ipv4[2]);
            sockaddr.add(23).writeU8(ipv4[3]);

            console.log("[dart:io HttpClient] Redirected to proxy (IPv6) ::ffff:192.168.1.5:" + proxyPort);
        }
    }
});
