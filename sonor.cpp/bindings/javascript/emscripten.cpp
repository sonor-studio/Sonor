//
// This is the Javascript API of sonor.cpp
//
// Very crude at the moment.
// Feel free to contribute and make this better!
//
// See the tests/test-sonor.js for sample usage
//

#include "sonor.h"

#include <emscripten.h>
#include <emscripten/bind.h>

#include <thread>
#include <vector>

struct sonor_context * g_context;

EMSCRIPTEN_BINDINGS(sonor) {
    emscripten::function("init", emscripten::optional_override([](const std::string & path_model) {
        if (g_context == nullptr) {
            g_context = sonor_init_from_file_with_params(path_model.c_str(), sonor_context_default_params());
            if (g_context != nullptr) {
                return true;
            } else {
                return false;
            }
        }

        return false;
    }));

    emscripten::function("free", emscripten::optional_override([]() {
        if (g_context) {
            sonor_free(g_context);
            g_context = nullptr;
        }
    }));

    emscripten::function("full_default", emscripten::optional_override([](const emscripten::val & audio, const std::string & lang, bool translate) {
        if (g_context == nullptr) {
            return -1;
        }

        struct sonor_full_params params = sonor_full_default_params(sonor_sampling_strategy::SONOR_SAMPLING_GREEDY);

        params.print_realtime   = true;
        params.print_progress   = false;
        params.print_timestamps = true;
        params.print_special    = false;
        params.translate        = translate;
        params.language         = sonor_is_multilingual(g_context) ? lang.c_str() : "en";
        params.n_threads        = std::min(8, (int) std::thread::hardware_concurrency());
        params.offset_ms        = 0;

        std::vector<float> pcmf32;
        const int n = audio["length"].as<int>();

        emscripten::val heap = emscripten::val::module_property("HEAPU8");
        emscripten::val memory = heap["buffer"];

        pcmf32.resize(n);

        emscripten::val memoryView = audio["constructor"].new_(memory, reinterpret_cast<uintptr_t>(pcmf32.data()), n);
        memoryView.call<void>("set", audio);

        // print system information
        {
            printf("\n");
            printf("system_info: n_threads = %d / %d | %s\n",
                    params.n_threads, std::thread::hardware_concurrency(), sonor_print_system_info());

            printf("\n");
            printf("%s: processing %d samples, %.1f sec, %d threads, %d processors, lang = %s, task = %s ...\n",
                    __func__, int(pcmf32.size()), float(pcmf32.size())/SONOR_SAMPLE_RATE,
                    params.n_threads, 1,
                    params.language,
                    params.translate ? "translate" : "transcribe");

            printf("\n");
        }

        // run sonor
        {
            sonor_reset_timings(g_context);
            sonor_full(g_context, params, pcmf32.data(), pcmf32.size());
            sonor_print_timings(g_context);
        }

        return 0;
    }));
}
