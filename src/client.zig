const std = @import("std");
const network = @import("network");

const tls = std.crypto.tls;

const TlsContext = struct {
    client: *tls.Client,
    stream: std.net.Stream,
};

const TlsWriter = std.io.Writer(TlsContext, anyerror, tlsWrite);

fn tlsWrite(context: TlsContext, data: []const u8) anyerror!usize {
    return try context.client.write(context.stream, data);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("MEMORY LEAK SHIT FUCK OW");

    const allocator = gpa.allocator();

    try network.init();
    defer network.deinit();

    const uri = comptime try std.Uri.parse("gemini://localhost");

    const sock = try network.connectToHost(allocator, uri.host.?, 1965, .tcp);
    defer sock.close();

    const stream = std.net.Stream{
        .handle = sock.internal,
    };
    var cert_bundle = std.crypto.Certificate.Bundle{};
    defer cert_bundle.deinit(allocator);

    try cert_bundle.addCertsFromFile(allocator, try std.fs.cwd().openFile("certs/client.crt", .{}));
    var client = try tls.Client.init(stream, cert_bundle, uri.host.?);
    client.allow_truncation_attacks = true;

    const writer = TlsWriter{ .context = .{
        .stream = stream,
        .client = &client,
    } };
    try std.fmt.format(writer, "{}\r\n", .{uri});

    var buf: [1024]u8 = undefined;
    while (blk: {
        const read = try client.read(stream, &buf);

        if (read == 0) break :blk null;
        break :blk read;
    }) |read| {
        const read_buf = buf[0..read];

        std.debug.print("{s}", .{read_buf});
    }
    std.debug.print("\n", .{});
}
