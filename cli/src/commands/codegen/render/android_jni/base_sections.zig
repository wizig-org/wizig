//! Shared C/JNI sections emitted before method-specific JNI bridge exports.

const std = @import("std");
const api = @import("../../model/api.zig");
const helpers = @import("../helpers.zig");

pub fn appendBaseSections(
    out: *std.ArrayList(u8),
    arena: std.mem.Allocator,
    methods: []const api.ApiMethod,
) !void {
    try out.appendSlice(arena, "#if defined(__ANDROID__)\n");
    try out.appendSlice(arena, "static pthread_once_t wizig_stdio_forward_once = PTHREAD_ONCE_INIT;\n\n");
    try out.appendSlice(arena, "static void* wizig_android_stdio_forward_loop(void* ctx) {\n");
    try out.appendSlice(arena, "    int read_fd = *(int*)ctx;\n");
    try out.appendSlice(arena, "    free(ctx);\n");
    try out.appendSlice(arena, "    char buffer[1024];\n");
    try out.appendSlice(arena, "    while (true) {\n");
    try out.appendSlice(arena, "        ssize_t read_count = read(read_fd, buffer, sizeof(buffer) - 1);\n");
    try out.appendSlice(arena, "        if (read_count <= 0) break;\n");
    try out.appendSlice(arena, "        buffer[(size_t)read_count] = '\\0';\n");
    try out.appendSlice(arena, "        __android_log_write(ANDROID_LOG_INFO, \"WizigZig\", buffer);\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "    close(read_fd);\n");
    try out.appendSlice(arena, "    return NULL;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "static void wizig_android_setup_stdio_forwarder(void) {\n");
    try out.appendSlice(arena, "    int pipe_fds[2];\n");
    try out.appendSlice(arena, "    if (pipe(pipe_fds) != 0) return;\n");
    try out.appendSlice(arena, "    const int read_fd = pipe_fds[0];\n");
    try out.appendSlice(arena, "    const int write_fd = pipe_fds[1];\n\n");
    try out.appendSlice(arena, "    if (dup2(write_fd, STDOUT_FILENO) < 0 || dup2(write_fd, STDERR_FILENO) < 0) {\n");
    try out.appendSlice(arena, "        close(read_fd);\n");
    try out.appendSlice(arena, "        close(write_fd);\n");
    try out.appendSlice(arena, "        return;\n");
    try out.appendSlice(arena, "    }\n\n");
    try out.appendSlice(arena, "    close(write_fd);\n");
    try out.appendSlice(arena, "    setvbuf(stdout, NULL, _IONBF, 0);\n");
    try out.appendSlice(arena, "    setvbuf(stderr, NULL, _IONBF, 0);\n\n");
    try out.appendSlice(arena, "    int* thread_fd = (int*)malloc(sizeof(int));\n");
    try out.appendSlice(arena, "    if (thread_fd == NULL) {\n");
    try out.appendSlice(arena, "        close(read_fd);\n");
    try out.appendSlice(arena, "        return;\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "    *thread_fd = read_fd;\n\n");
    try out.appendSlice(arena, "    pthread_t thread;\n");
    try out.appendSlice(arena, "    if (pthread_create(&thread, NULL, wizig_android_stdio_forward_loop, thread_fd) != 0) {\n");
    try out.appendSlice(arena, "        free(thread_fd);\n");
    try out.appendSlice(arena, "        close(read_fd);\n");
    try out.appendSlice(arena, "        return;\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "    pthread_detach(thread);\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "static void wizig_forward_stdio_to_logcat_once(void) {\n");
    try out.appendSlice(arena, "    pthread_once(&wizig_stdio_forward_once, wizig_android_setup_stdio_forwarder);\n");
    try out.appendSlice(arena, "}\n");
    try out.appendSlice(arena, "#else\n");
    try out.appendSlice(arena, "static void wizig_forward_stdio_to_logcat_once(void) {\n");
    try out.appendSlice(arena, "}\n");
    try out.appendSlice(arena, "#endif\n\n");

    try out.appendSlice(arena, "static void copy_slice_to_buffer(const uint8_t* ptr, size_t len, char* out, size_t cap) {\n");
    try out.appendSlice(arena, "    if (cap == 0) return;\n");
    try out.appendSlice(arena, "    if (ptr == NULL || len == 0) {\n");
    try out.appendSlice(arena, "        out[0] = '\\0';\n");
    try out.appendSlice(arena, "        return;\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "    size_t n = len < (cap - 1) ? len : (cap - 1);\n");
    try out.appendSlice(arena, "    memcpy(out, ptr, n);\n");
    try out.appendSlice(arena, "    out[n] = '\\0';\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "static void throw_structured_error(JNIEnv* env, const char* domain, int32_t code, const char* message) {\n");
    try out.appendSlice(arena, "    jclass structured_cls = (*env)->FindClass(env, \"dev/wizig/WizigGeneratedFfiException\");\n");
    try out.appendSlice(arena, "    if (structured_cls != NULL) {\n");
    try out.appendSlice(arena, "        jmethodID ctor = (*env)->GetMethodID(env, structured_cls, \"<init>\", \"(Ljava/lang/String;ILjava/lang/String;)V\");\n");
    try out.appendSlice(arena, "        if (ctor != NULL) {\n");
    try out.appendSlice(arena, "            jstring j_domain = (*env)->NewStringUTF(env, domain != NULL ? domain : \"wizig.runtime\");\n");
    try out.appendSlice(arena, "            jstring j_message = (*env)->NewStringUTF(env, message != NULL ? message : \"wizig ffi error\");\n");
    try out.appendSlice(arena, "            if (j_domain != NULL && j_message != NULL) {\n");
    try out.appendSlice(arena, "                jobject ex = (*env)->NewObject(env, structured_cls, ctor, j_domain, (jint)code, j_message);\n");
    try out.appendSlice(arena, "                if (ex != NULL) {\n");
    try out.appendSlice(arena, "                    (*env)->Throw(env, (jthrowable)ex);\n");
    try out.appendSlice(arena, "                }\n");
    try out.appendSlice(arena, "                (*env)->DeleteLocalRef(env, ex);\n");
    try out.appendSlice(arena, "            }\n");
    try out.appendSlice(arena, "            (*env)->DeleteLocalRef(env, j_domain);\n");
    try out.appendSlice(arena, "            (*env)->DeleteLocalRef(env, j_message);\n");
    try out.appendSlice(arena, "            return;\n");
    try out.appendSlice(arena, "        }\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "    jclass fallback_cls = (*env)->FindClass(env, \"java/lang/IllegalStateException\");\n");
    try out.appendSlice(arena, "    if (fallback_cls == NULL) return;\n");
    try out.appendSlice(arena, "    char buffer[320];\n");
    try out.appendSlice(arena, "    snprintf(buffer, sizeof(buffer), \"%s[%d]: %s\", domain != NULL ? domain : \"wizig.runtime\", (int)code, message != NULL ? message : \"wizig ffi error\");\n");
    try out.appendSlice(arena, "    (*env)->ThrowNew(env, fallback_cls, buffer);\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "static void throw_status_error(JNIEnv* env, const char* function_name, int32_t status) {\n");
    try out.appendSlice(arena, "    const uint8_t* domain_ptr = wizig_ffi_last_error_domain_ptr();\n");
    try out.appendSlice(arena, "    size_t domain_len = wizig_ffi_last_error_domain_len();\n");
    try out.appendSlice(arena, "    int32_t code = wizig_ffi_last_error_code();\n");
    try out.appendSlice(arena, "    const uint8_t* message_ptr = wizig_ffi_last_error_message_ptr();\n");
    try out.appendSlice(arena, "    size_t message_len = wizig_ffi_last_error_message_len();\n");
    try out.appendSlice(arena, "    char domain[96];\n");
    try out.appendSlice(arena, "    char message[256];\n");
    try out.appendSlice(arena, "    copy_slice_to_buffer(domain_ptr, domain_len, domain, sizeof(domain));\n");
    try out.appendSlice(arena, "    copy_slice_to_buffer(message_ptr, message_len, message, sizeof(message));\n");
    try out.appendSlice(arena, "    if (domain[0] == '\\0') snprintf(domain, sizeof(domain), \"%s\", \"wizig.runtime\");\n");
    try out.appendSlice(arena, "    if (message[0] == '\\0') snprintf(message, sizeof(message), \"%s failed with status %d\", function_name, (int)status);\n");
    try out.appendSlice(arena, "    throw_structured_error(env, domain, code == 0 ? status : code, message);\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "static jstring new_jstring_from_bytes(JNIEnv* env, const uint8_t* bytes, size_t len) {\n");
    try out.appendSlice(arena, "    char* tmp = (char*)malloc(len + 1);\n");
    try out.appendSlice(arena, "    if (tmp == NULL) {\n");
    try out.appendSlice(arena, "        throw_structured_error(env, \"wizig.memory\", 2, \"wizig generated bridge out of memory\");\n");
    try out.appendSlice(arena, "        return NULL;\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "    if (len > 0) memcpy(tmp, bytes, len);\n");
    try out.appendSlice(arena, "    tmp[len] = '\\0';\n");
    try out.appendSlice(arena, "    jstring result = (*env)->NewStringUTF(env, tmp);\n");
    try out.appendSlice(arena, "    free(tmp);\n");
    try out.appendSlice(arena, "    return result;\n");
    try out.appendSlice(arena, "}\n\n");

    try out.appendSlice(arena, "static int ensure_symbol(JNIEnv* env, const char* symbol_name) {\n");
    try out.appendSlice(arena, "    void* symbol = dlsym(RTLD_DEFAULT, symbol_name);\n");
    try out.appendSlice(arena, "    if (symbol != NULL) return 1;\n");
    try out.appendSlice(arena, "    char message[256];\n");
    try out.appendSlice(arena, "    snprintf(message, sizeof(message), \"missing Wizig FFI symbol: %s\", symbol_name);\n");
    try out.appendSlice(arena, "    throw_structured_error(env, \"wizig.compatibility\", 1001, message);\n");
    try out.appendSlice(arena, "    return 0;\n");
    try out.appendSlice(arena, "}\n\n");

    const validate_jni_name = try helpers.jniEscape(arena, "wizig_validate_bindings");
    try helpers.appendFmt(
        out,
        arena,
        "JNIEXPORT void JNICALL Java_dev_wizig_WizigGeneratedNativeBridge_{s}(JNIEnv* env, jclass clazz) {{\n",
        .{validate_jni_name},
    );
    try out.appendSlice(arena, "    (void)clazz;\n");
    try out.appendSlice(arena, "    wizig_forward_stdio_to_logcat_once();\n");
    try out.appendSlice(arena, "    if (!ensure_symbol(env, \"wizig_bytes_free\")) return;\n");
    try out.appendSlice(arena, "    if (!ensure_symbol(env, \"wizig_ffi_abi_version\")) return;\n");
    try out.appendSlice(arena, "    if (!ensure_symbol(env, \"wizig_ffi_contract_hash_ptr\")) return;\n");
    try out.appendSlice(arena, "    if (!ensure_symbol(env, \"wizig_ffi_contract_hash_len\")) return;\n");
    try out.appendSlice(arena, "    if (!ensure_symbol(env, \"wizig_ffi_last_error_domain_ptr\")) return;\n");
    try out.appendSlice(arena, "    if (!ensure_symbol(env, \"wizig_ffi_last_error_domain_len\")) return;\n");
    try out.appendSlice(arena, "    if (!ensure_symbol(env, \"wizig_ffi_last_error_code\")) return;\n");
    try out.appendSlice(arena, "    if (!ensure_symbol(env, \"wizig_ffi_last_error_message_ptr\")) return;\n");
    try out.appendSlice(arena, "    if (!ensure_symbol(env, \"wizig_ffi_last_error_message_len\")) return;\n");
    for (methods) |method| {
        try helpers.appendFmt(out, arena, "    if (!ensure_symbol(env, \"wizig_api_{s}\")) return;\n", .{method.name});
    }
    try out.appendSlice(arena, "    uint32_t actual_abi = wizig_ffi_abi_version();\n");
    try out.appendSlice(arena, "    const uint8_t* actual_hash_ptr = wizig_ffi_contract_hash_ptr();\n");
    try out.appendSlice(arena, "    size_t actual_hash_len = wizig_ffi_contract_hash_len();\n");
    try out.appendSlice(arena, "    char actual_hash[96];\n");
    try out.appendSlice(arena, "    copy_slice_to_buffer(actual_hash_ptr, actual_hash_len, actual_hash, sizeof(actual_hash));\n");
    try out.appendSlice(arena, "    if (actual_abi != WIZIG_EXPECTED_ABI_VERSION || strcmp(actual_hash, WIZIG_EXPECTED_CONTRACT_HASH) != 0) {\n");
    try out.appendSlice(arena, "        char message[320];\n");
    try out.appendSlice(arena, "        snprintf(message, sizeof(message), \"ffi compatibility mismatch: expected abi=%u hash=%s got abi=%u hash=%s\", (unsigned)WIZIG_EXPECTED_ABI_VERSION, WIZIG_EXPECTED_CONTRACT_HASH, (unsigned)actual_abi, actual_hash);\n");
    try out.appendSlice(arena, "        throw_structured_error(env, \"wizig.compatibility\", 1002, message);\n");
    try out.appendSlice(arena, "        return;\n");
    try out.appendSlice(arena, "    }\n");
    try out.appendSlice(arena, "}\n\n");
}
