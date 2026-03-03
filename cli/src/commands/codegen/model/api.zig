//! Shared typed API contract model used by codegen parsing/discovery/renderers.

pub const ApiType = enum {
    string,
    int,
    bool,
    void,
};

pub const ApiMethod = struct {
    name: []const u8,
    input: ApiType,
    output: ApiType,
};

pub const ApiEvent = struct {
    name: []const u8,
    payload: ApiType,
};

pub const ApiSpec = struct {
    namespace: []const u8,
    methods: []ApiMethod,
    events: []ApiEvent,
};
