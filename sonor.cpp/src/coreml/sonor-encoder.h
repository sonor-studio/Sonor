// Wrapper of the Core ML Sonor Encoder model
//
// Code is derived from the work of Github user @wangchou
// ref: https://github.com/wangchou/callCoreMLFromCpp

#include <stdint.h>

#if __cplusplus
extern "C" {
#endif

struct sonor_coreml_context;

struct sonor_coreml_context * sonor_coreml_init(const char * path_model);
void sonor_coreml_free(struct sonor_coreml_context * ctx);

void sonor_coreml_encode(
        const sonor_coreml_context * ctx,
                             int64_t   n_ctx,
                             int64_t   n_mel,
                               float * mel,
                               float * out);

#if __cplusplus
}
#endif
