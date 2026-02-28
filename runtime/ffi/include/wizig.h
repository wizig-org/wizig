#ifndef WIZIG_FFI_H
#define WIZIG_FFI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct WizigRuntimeHandle WizigRuntimeHandle;

typedef enum WizigStatus {
  WIZIG_STATUS_OK = 0,
  WIZIG_STATUS_NULL_ARGUMENT = 1,
  WIZIG_STATUS_OUT_OF_MEMORY = 2,
  WIZIG_STATUS_INVALID_ARGUMENT = 3,
  WIZIG_STATUS_INTERNAL_ERROR = 255,
} WizigStatus;

int32_t wizig_runtime_new(const uint8_t* app_name_ptr,
                         size_t app_name_len,
                         WizigRuntimeHandle** out_handle);

void wizig_runtime_free(WizigRuntimeHandle* handle);

int32_t wizig_runtime_echo(WizigRuntimeHandle* handle,
                          const uint8_t* input_ptr,
                          size_t input_len,
                          uint8_t** out_ptr,
                          size_t* out_len);

void wizig_bytes_free(uint8_t* ptr, size_t len);

#ifdef __cplusplus
}
#endif

#endif
