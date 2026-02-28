#ifndef ZIGGY_FFI_H
#define ZIGGY_FFI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ZiggyRuntimeHandle ZiggyRuntimeHandle;

typedef enum ZiggyStatus {
  ZIGGY_STATUS_OK = 0,
  ZIGGY_STATUS_NULL_ARGUMENT = 1,
  ZIGGY_STATUS_OUT_OF_MEMORY = 2,
  ZIGGY_STATUS_INVALID_ARGUMENT = 3,
  ZIGGY_STATUS_INTERNAL_ERROR = 255,
} ZiggyStatus;

int32_t ziggy_runtime_new(const uint8_t* app_name_ptr,
                         size_t app_name_len,
                         ZiggyRuntimeHandle** out_handle);

void ziggy_runtime_free(ZiggyRuntimeHandle* handle);

int32_t ziggy_runtime_echo(ZiggyRuntimeHandle* handle,
                          const uint8_t* input_ptr,
                          size_t input_len,
                          uint8_t** out_ptr,
                          size_t* out_len);

void ziggy_bytes_free(uint8_t* ptr, size_t len);

#ifdef __cplusplus
}
#endif

#endif
