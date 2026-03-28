//! Thread-safe tiered buffer pool providing an `std.mem.Allocator` interface.
//! Wraps `smp_allocator` with tier-based caching to eliminate syscall overhead
//! and reduce fragmentation for typical FFI output buffer sizes (64 B -- 4 KB).
const std = @import("std");

/// Number of buffer slots retained per tier.
const slots_per_tier = 8;

/// Header size in bytes prepended to every allocation to record total size.
const header_size = @sizeOf(usize);

/// Tier bucket sizes (inclusive of header).
const tier_sizes = [_]usize{ 64, 256, 1024, 4096 };

/// Backing allocator for cache misses and oversized allocations.
const backing = std.heap.smp_allocator;

/// Returns the tier index for `total` bytes, or `null` if oversized.
fn tierIndex(total: usize) ?usize {
    for (tier_sizes, 0..) |ts, i| {
        if (total <= ts) return i;
    }
    return null;
}

/// Thread-safe tiered buffer pool. Each tier holds up to `slots_per_tier`
/// cached buffers; oversized requests fall through to `smp_allocator`.
pub const BufferPool = struct {
    /// Per-tier free lists protected by a single mutex.
    tiers: [tier_sizes.len][slots_per_tier]?[*]u8 =
        [_][slots_per_tier]?[*]u8{[_]?[*]u8{null} ** slots_per_tier} ** tier_sizes.len,

    /// Number of cached entries per tier.
    counts: [tier_sizes.len]usize = [_]usize{0} ** tier_sizes.len,

    /// Guards all tier state against concurrent access.
    mutex: std.atomic.Mutex = .unlocked,

    /// Returns an `std.mem.Allocator` backed by this pool.
    pub fn allocator(self: *BufferPool) std.mem.Allocator {
        return .{
            .ptr = @ptrCast(self),
            .vtable = &vtable,
        };
    }

    const vtable: std.mem.Allocator.VTable = .{
        .alloc = poolAlloc,
        .resize = poolResize,
        .remap = poolRemap,
        .free = poolFree,
    };

    /// Spins until the mutex is acquired.
    fn lock(self: *BufferPool) void {
        while (!self.mutex.tryLock()) {}
    }

    /// Allocates `len` bytes past an internal header. Serves from cache
    /// when possible; falls through to `smp_allocator` on miss or oversize.
    fn poolAlloc(
        ctx: *anyopaque,
        len: usize,
        alignment: std.mem.Alignment,
        ret_addr: usize,
    ) ?[*]u8 {
        const self: *BufferPool = @ptrCast(@alignCast(ctx));
        const total = header_size + len;

        if (tierIndex(total)) |ti| {
            const tier_size = tier_sizes[ti];
            self.lock();
            const cached = blk: {
                if (self.counts[ti] > 0) {
                    self.counts[ti] -= 1;
                    const ptr = self.tiers[ti][self.counts[ti]];
                    self.tiers[ti][self.counts[ti]] = null;
                    break :blk ptr;
                }
                break :blk null;
            };
            self.mutex.unlock();

            if (cached) |raw| {
                writeHeader(raw, total);
                return raw + header_size;
            }

            const raw = backing.vtable.alloc(backing.ptr, tier_size, alignment, ret_addr) orelse return null;
            writeHeader(raw, total);
            return raw + header_size;
        }

        // Oversized: allocate exact total from backing allocator.
        const raw = backing.vtable.alloc(backing.ptr, total, alignment, ret_addr) orelse return null;
        writeHeader(raw, total);
        return raw + header_size;
    }

    /// Succeeds when `new_len` fits within the existing allocation capacity.
    fn poolResize(
        _: *anyopaque,
        memory: []u8,
        _: std.mem.Alignment,
        new_len: usize,
        _: usize,
    ) bool {
        const raw_addr = @intFromPtr(memory.ptr) - header_size;
        const alloc_total = readHeader(raw_addr);
        return new_len <= (alloc_total - header_size);
    }

    /// Relocation is not supported; always returns `null`.
    fn poolRemap(
        _: *anyopaque,
        _: []u8,
        _: std.mem.Alignment,
        _: usize,
        _: usize,
    ) ?[*]u8 {
        return null;
    }

    /// Returns a buffer to its tier free list when space is available,
    /// otherwise releases it back to the backing allocator.
    fn poolFree(
        ctx: *anyopaque,
        memory: []u8,
        alignment: std.mem.Alignment,
        ret_addr: usize,
    ) void {
        const self: *BufferPool = @ptrCast(@alignCast(ctx));
        const raw_addr = @intFromPtr(memory.ptr) - header_size;
        const alloc_total = readHeader(raw_addr);
        const raw: [*]u8 = @ptrFromInt(raw_addr);

        if (tierIndex(alloc_total)) |ti| {
            const tier_size = tier_sizes[ti];
            self.lock();
            if (self.counts[ti] < slots_per_tier) {
                self.tiers[ti][self.counts[ti]] = raw;
                self.counts[ti] += 1;
                self.mutex.unlock();
                return;
            }
            self.mutex.unlock();
            backing.vtable.free(backing.ptr, raw[0..tier_size], alignment, ret_addr);
        } else {
            backing.vtable.free(backing.ptr, raw[0..alloc_total], alignment, ret_addr);
        }
    }
};

/// Writes the total allocation size into the header region at `raw`.
fn writeHeader(raw: [*]u8, total: usize) void {
    const hdr: *usize = @ptrCast(@alignCast(raw));
    hdr.* = total;
}

/// Reads the total allocation size from the header at `raw_addr`.
fn readHeader(raw_addr: usize) usize {
    const hdr: *const usize = @ptrFromInt(raw_addr);
    return hdr.*;
}

test "alloc and free round-trip" {
    var pool = BufferPool{};
    const a = pool.allocator();
    const buf = try a.alloc(u8, 100);
    @memset(buf, 0xAB);
    a.free(buf);
}

test "pool reuses buffers after free" {
    var pool = BufferPool{};
    const a = pool.allocator();
    const first = try a.alloc(u8, 50);
    const first_ptr = first.ptr;
    a.free(first);
    const second = try a.alloc(u8, 50);
    try std.testing.expectEqual(first_ptr, second.ptr);
    a.free(second);
}

test "oversized allocations work" {
    var pool = BufferPool{};
    const a = pool.allocator();
    const big = try a.alloc(u8, 8192);
    @memset(big, 0xCD);
    a.free(big);
}

test "resize succeeds for shrinking within capacity" {
    var pool = BufferPool{};
    const a = pool.allocator();
    const buf = try a.alloc(u8, 200);
    try std.testing.expect(a.resize(buf, 100));
    const shrunk: []u8 = buf.ptr[0..100];
    a.free(shrunk);
}
