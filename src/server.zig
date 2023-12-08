const std = @import("std");
const network = @import("network");

const tls = @cImport({
    @cInclude("tls.h");
});

var run: std.atomic.Value(bool) = std.atomic.Value(bool).init(true);

var global_socket: ?network.Socket = null;
var mutex: std.Thread.Mutex = .{};

fn sigHandle(sig: c_int) callconv(.C) void {
    _ = sig;

    run.store(false, .SeqCst);

    mutex.lock();
    if (global_socket) |socket|
        socket.close();

    network.deinit();
    mutex.unlock();

    std.log.info("Closing server...", .{});
    std.os.exit(0);
}

const c = @cImport(@cInclude("signal.h"));

const TlsContext = struct {
    tls: *tls.tls,
};

fn tlsWrite(context: TlsContext, data: []const u8) anyerror!usize {
    const ret = tls.tls_write(context.tls, @constCast(@ptrCast(data.ptr)), data.len);

    if (ret == -1) {
        return error.TlsWriteError;
    }

    return @intCast(ret);
}

fn tlsRead(context: TlsContext, data: []u8) anyerror!usize {
    const ret = tls.tls_read(context.tls, @ptrCast(data.ptr), data.len);

    if (ret == -1) {
        return error.TlsReadError;
    }

    return @intCast(ret);
}

const TlsWriter = std.io.Writer(TlsContext, anyerror, tlsWrite);
const TlsReader = std.io.Reader(TlsContext, anyerror, tlsRead);

pub fn main() !void {
    _ = c.signal(c.SIGINT, sigHandle);

    try network.init();
    defer network.deinit();

    mutex.lock();
    var sock = try network.Socket.create(.ipv4, .tcp);
    defer sock.close();

    global_socket = sock;
    mutex.unlock();

    const port = 1965;

    try sock.bindToPort(port);

    try sock.listen();

    std.log.info("Listening on port {d}", .{port});

    if (tls.tls_init() != 0) {
        std.log.err("error initializing TLS", .{});
        return error.InitializingTLSFailed;
    }
    std.log.info("TLS Initialized", .{});

    const tls_config = tls.tls_config_new().?;
    defer tls.tls_config_free(tls_config);

    const root_cert_path = "certs/root.pem";

    if (tls.tls_config_set_ca_file(tls_config, root_cert_path) != 0) {
        std.log.err("Error setting root CA file", .{});
        std.log.err("{s}", .{tls.tls_config_error(tls_config)});
        return error.FailedToSetRootCAFile;
    }
    std.log.info("Loaded root cert from path {s}", .{root_cert_path});

    const cert_file_path = "certs/server.crt";
    const key_file_path = "certs/server.key";

    if (tls.tls_config_set_cert_file(tls_config, cert_file_path) != 0) {
        std.log.err("Error setting certificate file", .{});
        std.log.err("{s}", .{tls.tls_config_error(tls_config)});
        return error.FailedToSetCertificate;
    }
    std.log.info("Loaded certificate from path {s}", .{cert_file_path});

    if (tls.tls_config_set_key_file(tls_config, key_file_path) != 0) {
        std.log.err("Error setting key file", .{});
        std.log.err("{s}", .{tls.tls_config_error(tls_config)});
        return error.FailedToSetKey;
    }
    std.log.info("Loaded key from path {s}", .{key_file_path});

    const tls_server = tls.tls_server().?;
    std.log.info("Created TLS server", .{});

    if (tls.tls_configure(tls_server, tls_config) != 0) {
        std.log.err("Error applying config", .{});
        std.log.err("{s}", .{tls.tls_config_error(tls_config)});
        return error.FailedToApplySSLConfig;
    }
    std.log.info("Configured TLS server", .{});

    while (run.load(.SeqCst)) {
        var client = try sock.accept();
        defer client.close();

        var client_tls: ?*tls.tls = undefined;
        if (tls.tls_accept_socket(tls_server, &client_tls, client.internal) != 0 or client_tls == null) {
            std.log.err("Unable to accept TLS socket\n", .{});
            continue;
        }
        defer tls.tls_free(client_tls);

        if (tls.tls_handshake(client_tls) != 0) {
            std.log.err("Full handshake failed", .{});
            continue;
        }
        std.log.info("TLS handshake succeeded", .{});

        std.log.info("Client connected from {}", .{try client.getRemoteEndPoint()});

        const io_context = TlsContext{ .tls = client_tls.? };
        const reader = TlsReader{ .context = io_context };
        const writer = TlsWriter{ .context = io_context };

        var buf: [1024 + 2]u8 = undefined;

        const raw_header = try reader.readUntilDelimiter(&buf, '\n');
        const header = raw_header[0 .. raw_header.len - 1];

        const uri = try std.Uri.parse(header);

        std.log.info("Got request for URL {}", .{uri});

        try std.fmt.format(writer, "20\r\n# HELLO THERE\r\n## MY NAME IS MARKETABLE PLIERS", .{});
    }

    std.log.info("Closing server...", .{});
}
