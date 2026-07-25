#include "sonor.h"
#include "common-sonor.h"

#include <cstdio>
#include <cfloat>
#include <string>
#include <cstring>

#ifdef NDEBUG
#undef NDEBUG
#endif

#include <cassert>

int main() {
    std::string sonor_model_path = SONOR_MODEL_PATH;
    std::string vad_model_path     = VAD_MODEL_PATH;
    std::string sample_path        = SAMPLE_PATH;

    // Load the sample audio file
    std::vector<float> pcmf32;
    std::vector<std::vector<float>> pcmf32s;
    assert(read_audio_data(sample_path.c_str(), pcmf32, pcmf32s, false));

    struct sonor_context_params cparams = sonor_context_default_params();
    struct sonor_context * wctx = sonor_init_from_file_with_params(
            sonor_model_path.c_str(),
            cparams);

    struct sonor_full_params wparams = sonor_full_default_params(SONOR_SAMPLING_BEAM_SEARCH);
    wparams.vad            = true;
    wparams.vad_model_path = vad_model_path.c_str();

    wparams.vad_params.threshold               = 0.5f;
    wparams.vad_params.min_speech_duration_ms  = 250;
    wparams.vad_params.min_silence_duration_ms = 100;
    wparams.vad_params.max_speech_duration_s   = FLT_MAX;
    wparams.vad_params.speech_pad_ms           = 30;

    assert(sonor_full_parallel(wctx, wparams, pcmf32.data(), pcmf32.size(), 1) == 0);

    const int n_segments = sonor_full_n_segments(wctx);
    assert(n_segments == 1);


    printf("Segment text:\n%s", sonor_full_get_segment_text(wctx, 0));
    assert(strcmp(" And so my fellow Americans, ask not what your country can do for you,"
                  " ask what you can do for your country.",
           sonor_full_get_segment_text(wctx, 0)) == 0);
    assert(sonor_full_get_segment_t0(wctx, 0) == 32);
    assert(sonor_full_get_segment_t1(wctx, 0) == 1051);

    sonor_free(wctx);

    return 0;
}
