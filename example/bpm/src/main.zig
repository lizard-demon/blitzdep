const std = @import("std");
const Graph = @import("blitzdep").Graph;

const Def = struct { name: []const u8, script: []const u8, deps: []const []const u8 };
const REPO = [_]Def{
    .{ .name = "tcc", .script = "mkdir -p $out/bin; echo 'compiler' > $out/bin/cc; chmod +x $out/bin/cc", .deps = &.{} },
    .{ .name = "musl", .script = "mkdir -p $out/lib; echo 'libc' > $out/lib/libc.a", .deps = &.{"tcc"} },
    .{ .name = "ssl", .script = "mkdir -p $out/lib; echo 'ssl' > $out/lib/libssl.a", .deps = &.{"tcc", "musl"} },
    .{ .name = "git", .script = "mkdir -p $out/bin; echo 'git' > $out/bin/git; chmod +x $out/bin/git", .deps = &.{"tcc", "musl", "ssl"} },
    .{ .name = "app", .script = "mkdir -p $out/bin; ln -s $GIT_ROOT/bin/git $out/bin/app", .deps = &.{"git"} },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const a = gpa.allocator();
    const root = try std.fs.selfExeDirPathAlloc(a);
    defer a.free(root);
    var dir = try std.fs.openDirAbsolute(root, .{}); 
    defer dir.close();

    var idx = std.StringHashMap(u32).init(a);
    defer idx.deinit();
    for (REPO, 0..) |r, i| try idx.put(r.name, @intCast(i));

    const g = try a.create(Graph(u32, 2000, 10000)); 
    defer a.destroy(g);
    g.* = .{};
    for (REPO, 0..) |r, i| {
        for (r.deps) |d| _ = g.add(@intCast(i), .{idx.get(d).?});
    }

    var want = try std.DynamicBitSet.initEmpty(a, REPO.len);
    defer want.deinit();
    const pkgs = dir.readFileAlloc(a, "packages", 1e5) catch return;
    defer a.free(pkgs);
    var it = std.mem.tokenizeAny(u8, pkgs, "\n ");
    while (it.next()) |n| if (idx.get(n)) |id| mark(g, &want, id);

    const hash = try a.alloc(u64, REPO.len);
    defer a.free(hash);
    var keep = std.StringHashMap(void).init(a);
    defer keep.deinit();
    var path = std.ArrayList(u8){};
    defer path.deinit(a);
    try dir.makePath(".store");

    var i = (try g.resolve()).len;
    while (i > 0) {
        i -= 1; const id = (try g.resolve())[i];
        if (!want.isSet(id)) continue;

        var h = std.hash.Wyhash.init(0); h.update(REPO[id].name); h.update(REPO[id].script);
        var edge = g.node[id]; while (edge) |x| { h.update(std.mem.asBytes(&hash[g.edge[x]])); edge = g.next[x]; }
        hash[id] = h.final();

        const name = try std.fmt.allocPrint(a, "{x:0>16}-{s}", .{hash[id], REPO[id].name});
        try keep.put(name, {});

        path.clearRetainingCapacity();
        try path.writer(a).print(".store/{s}", .{name});
        if (dir.access(path.items, .{})) |_| continue else |_| {}

        std.debug.print("{s}...", .{REPO[id].name});
        var env = try std.process.getEnvMap(a);
        try env.put("out", try std.fmt.allocPrint(a, "{s}/{s}", .{root, path.items}));

        var bins = std.ArrayList(u8){};
        defer bins.deinit(a);
        try bins.appendSlice(a, "/bin:/usr/bin");
        edge = g.node[id]; while (edge) |x| {
            const did = g.edge[x];
            const dn = try std.fmt.allocPrint(a, "{x:0>16}-{s}", .{hash[did], REPO[did].name});
            const dp = try std.fmt.allocPrint(a, "{s}/.store/{s}", .{root, dn});
            try bins.writer(a).print(":{s}/bin", .{dp});
            const k = try std.ascii.allocUpperString(a, REPO[did].name);
            try env.put(try std.fmt.allocPrint(a, "{s}_ROOT", .{k}), dp);
            edge = g.next[x];
        }
        try env.put("PATH", bins.items);

        try dir.makePath(path.items);
        var child = std.process.Child.init(&.{"sh", "-c", REPO[id].script}, a);
        child.env_map = &env; child.stdout_behavior = .Ignore; child.stderr_behavior = .Ignore;
        const term = try child.spawnAndWait();
        if (term != .Exited or term.Exited != 0) {
            std.debug.print(" err\n", .{});
            return error.BuildFailed;
        }
        std.debug.print(" ok\n", .{});
    }

    var store = try dir.openDir(".store", .{.iterate = true}); defer store.close();
    var scan = store.iterate();
    while (try scan.next()) |entry| if (!keep.contains(entry.name)) {
        std.debug.print("rm {s}\n", .{entry.name});
        try store.deleteTree(entry.name);
    };
}

fn mark(g: *Graph(u32, 2000, 10000), set: *std.DynamicBitSet, id: u32) void {
    if (set.isSet(id)) return;
    set.set(id);
    var edge = g.node[id]; while (edge) |x| { mark(g, set, g.edge[x]); edge = g.next[x]; }
}
