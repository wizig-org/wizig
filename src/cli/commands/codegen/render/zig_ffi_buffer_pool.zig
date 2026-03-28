//! Emits the generated FFI output buffer pool implementation.
//!
//! The generated FFI root keeps this inline so `wizig_bytes_free` can return
//! buffers without any extra handle parameter while still reusing common sizes.

const std = @import("std");

/// Appends the tiered buffer-pool implementation used by generated FFI roots.
pub fn appendBufferPool(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
    try out.appendSlice(arena,
        \\const BufferPool = struct {
        \\    const slots_per_tier = 8;
        \\    const header_size = @sizeOf(usize);
        \\    const tier_sizes = [_]usize{ 64, 256, 1024, 4096 };
        \\    const backing = std.heap.smp_allocator;
        \\
        \\    tiers: [tier_sizes.len][slots_per_tier]?[*]u8 =
        \\        [_][slots_per_tier]?[*]u8{[_]?[*]u8{null} ** slots_per_tier} ** tier_sizes.len,
        \\    counts: [tier_sizes.len]usize = [_]usize{0} ** tier_sizes.len,
        \\    mutex: std.atomic.Mutex = .unlocked,
        \\
        \\    fn tierIndex(total: usize) ?usize {
        \\        for (tier_sizes, 0..) |tier_size, index| {
        \\            if (total <= tier_size) return index;
        \\        }
        \\        return null;
        \\    }
        \\
        \\    fn allocator(self: *BufferPool) std.mem.Allocator {
        \\        return .{ .ptr = @ptrCast(self), .vtable = &vtable };
        \\    }
        \\
        \\    const vtable: std.mem.Allocator.VTable = .{
        \\        .alloc = alloc,
        \\        .resize = resize,
        \\        .remap = remap,
        \\        .free = free,
        \\    };
        \\
        \\    fn lock(self: *BufferPool) void {
        \\        while (!self.mutex.tryLock()) {}
        \\    }
        \\
        \\    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        \\        const self: *BufferPool = @ptrCast(@alignCast(ctx));
        \\        const total = header_size + len;
        \\        if (tierIndex(total)) |tier_index| {
        \\            const tier_size = tier_sizes[tier_index];
        \\            self.lock();
        \\            const cached = blk: {
        \\                if (self.counts[tier_index] > 0) {
        \\                    self.counts[tier_index] -= 1;
        \\                    const ptr = self.tiers[tier_index][self.counts[tier_index]];
        \\                    self.tiers[tier_index][self.counts[tier_index]] = null;
        \\                    break :blk ptr;
        \\                }
        \\                break :blk null;
        \\            };
        \\            self.mutex.unlock();
        \\            if (cached) |raw| {
        \\                writeHeader(raw, total);
        \\                return raw + header_size;
        \\            }
        \\            const raw = backing.vtable.alloc(backing.ptr, tier_size, alignment, ret_addr) orelse return null;
        \\            writeHeader(raw, total);
        \\            return raw + header_size;
        \\        }
        \\        const raw = backing.vtable.alloc(backing.ptr, total, alignment, ret_addr) orelse return null;
        \\        writeHeader(raw, total);
        \\        return raw + header_size;
        \\    }
        \\
        \\    fn resize(_: *anyopaque, memory: []u8, _: std.mem.Alignment, new_len: usize, _: usize) bool {
        \\        const raw_addr = @intFromPtr(memory.ptr) - header_size;
        \\        return new_len <= readHeader(raw_addr) - header_size;
        \\    }
        \\
        \\    fn remap(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) ?[*]u8 {
        \\        return null;
        \\    }
        \\
        \\    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        \\        const self: *BufferPool = @ptrCast(@alignCast(ctx));
        \\        const raw_addr = @intFromPtr(memory.ptr) - header_size;
        \\        const alloc_total = readHeader(raw_addr);
        \\        const raw: [*]u8 = @ptrFromInt(raw_addr);
        \\        if (tierIndex(alloc_total)) |tier_index| {
        \\            const tier_size = tier_sizes[tier_index];
        \\            self.lock();
        \\            if (self.counts[tier_index] < slots_per_tier) {
        \\                self.tiers[tier_index][self.counts[tier_index]] = raw;
        \\                self.counts[tier_index] += 1;
        \\                self.mutex.unlock();
        \\                return;
        \\            }
        \\            self.mutex.unlock();
        \\            backing.vtable.free(backing.ptr, raw[0..tier_size], alignment, ret_addr);
        \\            return;
        \\        }
        \\        backing.vtable.free(backing.ptr, raw[0..alloc_total], alignment, ret_addr);
        \\    }
        \\};
        \\
        \\fn writeHeader(raw: [*]u8, total: usize) void {
        \\    const header: *usize = @ptrCast(@alignCast(raw));
        \\    header.* = total;
        \\}
        \\
        \\fn readHeader(raw_addr: usize) usize {
        \\    const header: *const usize = @ptrFromInt(raw_addr);
        \\    return header.*;
        \\}
        \\
        \\var ffi_pool = BufferPool{};
        \\const ffi_output_allocator = ffi_pool.allocator();
        \\
    );
}
