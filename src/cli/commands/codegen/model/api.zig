//! Shared typed API contract model used by codegen parsing/discovery/renderers.

pub const ApiType = union(enum) {
    string,
    int,
    bool,
    void,
    user_struct: []const u8,
    user_enum: []const u8,
};

pub const StructField = struct {
    name: []const u8,
    field_type: ApiType,
};

pub const UserStruct = struct {
    name: []const u8,
    fields: []const StructField,
};

pub const UserEnum = struct {
    name: []const u8,
    variants: []const []const u8,
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
    methods: []const ApiMethod,
    events: []const ApiEvent,
    structs: []const UserStruct = &.{},
    enums: []const UserEnum = &.{},
};
