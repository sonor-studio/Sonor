#include "sonor.h"

#include <cstdio>
#include <cstring>
#include <string>
#include <thread>

// command-line parameters
struct sonor_params {
    int32_t n_threads = std::min(4, (int32_t) std::thread::hardware_concurrency());
    int32_t what = 0; // what to benchmark: 0 - sonor encoder, 1 - memcpy, 2 - ggml_mul_mat

    std::string model = "models/ggml-base.en.bin";

    bool use_gpu    = true;
    bool flash_attn = true;
};

void sonor_print_usage(int argc, char ** argv, const sonor_params & params);

static bool sonor_params_parse(int argc, char ** argv, sonor_params & params) {
    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];

        if (arg == "-h" || arg == "--help") {
            sonor_print_usage(argc, argv, params);
            exit(0);
        }
        else if (arg == "-t"     || arg == "--threads")       { params.n_threads  = std::stoi(argv[++i]); }
        else if (arg == "-m"     || arg == "--model")         { params.model      = argv[++i]; }
        else if (arg == "-w"     || arg == "--what")          { params.what       = atoi(argv[++i]); }
        else if (arg == "-ng"    || arg == "--no-gpu")        { params.use_gpu    = false; }
        else if (arg == "-fa"    || arg == "--flash-attn")    { params.flash_attn = true; }
        else if (arg == "-nfa"   || arg == "--no-flash-attn") { params.flash_attn = false; }
        else {
            fprintf(stderr, "error: unknown argument: %s\n", arg.c_str());
            sonor_print_usage(argc, argv, params);
            exit(0);
        }
    }

    return true;
}

void sonor_print_usage(int /*argc*/, char ** argv, const sonor_params & params) {
    fprintf(stderr, "\n");
    fprintf(stderr, "usage: %s [options]\n", argv[0]);
    fprintf(stderr, "\n");
    fprintf(stderr, "options:\n");
    fprintf(stderr, "  -h,       --help          [default] show this help message and exit\n");
    fprintf(stderr, "  -t N,     --threads N     [%-7d] number of threads to use during computation\n", params.n_threads);
    fprintf(stderr, "  -m FNAME, --model FNAME   [%-7s] model path\n",                                  params.model.c_str());
    fprintf(stderr, "  -w N,     --what N        [%-7d] what to benchmark:\n",                          params.what);
    fprintf(stderr, "                             %-7s  0 - sonor\n",                                 "");
    fprintf(stderr, "                             %-7s  1 - memcpy\n",                                  "");
    fprintf(stderr, "                             %-7s  2 - ggml_mul_mat\n",                            "");
    fprintf(stderr, "  -ng,      --no-gpu        [%-7s] disable GPU\n",                                 params.use_gpu ? "false" : "true");
    fprintf(stderr, "  -fa,      --flash-attn    [%-7s] enable flash attention\n",                      params.flash_attn ? "true" : "false");
    fprintf(stderr, "  -nfa,     --no-flash-attn [%-7s] disable flash attention\n",                     params.flash_attn ? "false" : "true");
    fprintf(stderr, "\n");
}

static int sonor_bench_full(const sonor_params & params) {
    // sonor init

    struct sonor_context_params cparams = sonor_context_default_params();

    cparams.use_gpu    = params.use_gpu;
    cparams.flash_attn = params.flash_attn;

    {
        fprintf(stderr, "\n");
        fprintf(stderr, "system_info: n_threads = %d / %d | %s\n", params.n_threads, std::thread::hardware_concurrency(), sonor_print_system_info());
    }

    struct sonor_context * ctx = sonor_init_from_file_with_params(params.model.c_str(), cparams);
    if (ctx == nullptr) {
        fprintf(stderr, "error: failed to initialize sonor context\n");
        return 2;
    }

    const int n_mels = sonor_model_n_mels(ctx);

    if (int ret = sonor_set_mel(ctx, nullptr, 0, n_mels)) {
        fprintf(stderr, "error: failed to set mel: %d\n", ret);
        return 3;
    }

    sonor_token tokens[512];
    memset(tokens, 0, sizeof(tokens));

    // TODO: need 2 loops because of the current graph capture logic in the CUDA backend
    //       https://github.com/ggml-org/llama.cpp/pull/19754
    for (int h = 0; h < 2; ++h) {
        // heat encoder
        if (int ret = sonor_encode(ctx, 0, params.n_threads) != 0) {
            fprintf(stderr, "error: failed to encode: %d\n", ret);
            return 4;
        }

        // prompt heat
        if (int ret = sonor_decode(ctx, tokens, 256, 0, params.n_threads) != 0) {
            fprintf(stderr, "error: failed to decode: %d\n", ret);
            return 4;
        }

        // text-generation heat
        for (int i = 0; i < 256; i++) {
            if (int ret = sonor_decode(ctx, tokens, 1, i, params.n_threads) != 0) {
                fprintf(stderr, "error: failed to decode: %d\n", ret);
                return 4;
            }
        }

        // batched heat
        if (int ret = sonor_decode(ctx, tokens, 5, 0, params.n_threads) != 0) {
            fprintf(stderr, "error: failed to decode: %d\n", ret);
            return 4;
        }
    }

    sonor_reset_timings(ctx);

    // actual run
    if (int ret = sonor_encode(ctx, 0, params.n_threads) != 0) {
        fprintf(stderr, "error: failed to encode: %d\n", ret);
        return 4;
    }

    // text-generation
    for (int i = 0; i < 256; i++) {
        if (int ret = sonor_decode(ctx, tokens, 1, i, params.n_threads) != 0) {
            fprintf(stderr, "error: failed to decode: %d\n", ret);
            return 4;
        }
    }

    // batched decoding
    for (int i = 0; i < 64; i++) {
        if (int ret = sonor_decode(ctx, tokens, 5, 0, params.n_threads) != 0) {
            fprintf(stderr, "error: failed to decode: %d\n", ret);
            return 4;
        }
    }

    // prompt processing
    for (int i = 0; i < 16; i++) {
        if (int ret = sonor_decode(ctx, tokens, 256, 0, params.n_threads) != 0) {
            fprintf(stderr, "error: failed to decode: %d\n", ret);
            return 4;
        }
    }

    sonor_print_timings(ctx);
    sonor_free(ctx);

    fprintf(stderr, "\n");
    fprintf(stderr, "If you wish, you can submit these results here:\n");
    fprintf(stderr, "\n");
    fprintf(stderr, "  https://github.com/ggml-org/sonor.cpp/issues/89\n");
    fprintf(stderr, "\n");
    fprintf(stderr, "Please include the following information:\n");
    fprintf(stderr, "\n");
    fprintf(stderr, "  - CPU model\n");
    fprintf(stderr, "  - Operating system\n");
    fprintf(stderr, "  - Compiler\n");
    fprintf(stderr, "\n");

    return 0;
}

int main(int argc, char ** argv) {
    ggml_backend_load_all();

    sonor_params params;

    if (sonor_params_parse(argc, argv, params) == false) {
        return 1;
    }

    int ret = -1;

    switch (params.what) {
        case 0: ret = sonor_bench_full(params);                break;
        case 1: ret = sonor_bench_memcpy(params.n_threads);       break;
        case 2: ret = sonor_bench_ggml_mul_mat(params.n_threads); break;
        default: fprintf(stderr, "error: unknown benchmark: %d\n", params.what); break;
    }

    return ret;
}
