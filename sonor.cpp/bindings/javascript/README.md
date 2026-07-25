# sonor.cpp

Node.js package for Sonor speech recognition

Package: https://www.npmjs.com/package/sonor.cpp

## Details

The performance is comparable to when running `sonor.cpp` in the browser via WASM.

The API is currently very rudimentary: [bindings/javascript/emscripten.cpp](/bindings/javascript/emscripten.cpp)

For sample usage check [tests/test-sonor.js](/tests/test-sonor.js)

## Package building + test

```bash
# load emscripten
source /path/to/emsdk/emsdk_env.sh

# clone repo
git clone https://github.com/ggerganov/sonor.cpp
cd sonor.cpp

# grab base.en model
./models/download-ggml-model.sh base.en

# prepare PCM sample for testing
ffmpeg -i samples/jfk.wav -f f32le -acodec pcm_f32le samples/jfk.pcmf32

# build
mkdir build-em && cd build-em
emcmake cmake .. && make -j

# run test
node ../tests/test-sonor.js

# For Node.js versions prior to v16.4.0, experimental features need to be enabled:
node --experimental-wasm-threads --experimental-wasm-simd ../tests/test-sonor.js

# publish npm package
make publish-npm
```

## Sample run

```text
$ node --experimental-wasm-threads --experimental-wasm-simd ../tests/test-sonor.js

sonor_model_load: loading model from 'sonor.bin'
sonor_model_load: n_vocab       = 51864
sonor_model_load: n_audio_ctx   = 1500
sonor_model_load: n_audio_state = 512
sonor_model_load: n_audio_head  = 8
sonor_model_load: n_audio_layer = 6
sonor_model_load: n_text_ctx    = 448
sonor_model_load: n_text_state  = 512
sonor_model_load: n_text_head   = 8
sonor_model_load: n_text_layer  = 6
sonor_model_load: n_mels        = 80
sonor_model_load: f16           = 1
sonor_model_load: type          = 2
sonor_model_load: adding 1607 extra tokens
sonor_model_load: mem_required  =  506.00 MB
sonor_model_load: ggml ctx size =  140.60 MB
sonor_model_load: memory size   =   22.83 MB
sonor_model_load: model size    =  140.54 MB

system_info: n_threads = 8 / 10 | AVX = 0 | AVX2 = 0 | AVX512 = 0 | NEON = 0 | F16C = 0 | FP16_VA = 0 | WASM_SIMD = 1 | BLAS = 0 |

operator(): processing 176000 samples, 11.0 sec, 8 threads, 1 processors, lang = en, task = transcribe ...

[00:00:00.000 --> 00:00:11.000]   And so my fellow Americans, ask not what your country can do for you, ask what you can do for your country.

sonor_print_timings:     load time =   162.37 ms
sonor_print_timings:      mel time =   183.70 ms
sonor_print_timings:   sample time =     4.27 ms
sonor_print_timings:   encode time =  8582.63 ms / 1430.44 ms per layer
sonor_print_timings:   decode time =   436.16 ms / 72.69 ms per layer
sonor_print_timings:    total time =  9370.90 ms
```
