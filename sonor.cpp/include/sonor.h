#ifndef SONOR_H
#define SONOR_H

#include "ggml.h"
#include "ggml-cpu.h"

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __GNUC__
#    define SONOR_DEPRECATED(func, hint) func __attribute__((deprecated(hint)))
#elif defined(_MSC_VER)
#    define SONOR_DEPRECATED(func, hint) __declspec(deprecated(hint)) func
#else
#    define SONOR_DEPRECATED(func, hint) func
#endif

#ifdef SONOR_SHARED
#    ifdef _WIN32
#        ifdef SONOR_BUILD
#            define SONOR_API __declspec(dllexport)
#        else
#            define SONOR_API __declspec(dllimport)
#        endif
#    else
#        define SONOR_API __attribute__ ((visibility ("default")))
#    endif
#else
#    define SONOR_API
#endif

#define SONOR_SAMPLE_RATE 16000
#define SONOR_N_FFT       400
#define SONOR_HOP_LENGTH  160
#define SONOR_CHUNK_SIZE  30

#ifdef __cplusplus
extern "C" {
#endif

    //
    // C interface
    //
    // The following interface is thread-safe as long as the sample sonor_context is not used by multiple threads
    // concurrently.
    //
    // Basic usage:
    //
    //     #include "sonor.h"
    //
    //     ...
    //
    //     sonor_context_params cparams = sonor_context_default_params();
    //
    //     struct sonor_context * ctx = sonor_init_from_file_with_params("/path/to/ggml-base.en.bin", cparams);
    //
    //     if (sonor_full(ctx, wparams, pcmf32.data(), pcmf32.size()) != 0) {
    //         fprintf(stderr, "failed to process audio\n");
    //         return 7;
    //     }
    //
    //     const int n_segments = sonor_full_n_segments(ctx);
    //     for (int i = 0; i < n_segments; ++i) {
    //         const char * text = sonor_full_get_segment_text(ctx, i);
    //         printf("%s", text);
    //     }
    //
    //     sonor_free(ctx);
    //
    //     ...
    //
    // This is a demonstration of the most straightforward usage of the library.
    // "pcmf32" contains the RAW audio data in 32-bit floating point format.
    //
    // The interface also allows for more fine-grained control over the computation, but it requires a deeper
    // understanding of how the model works.
    //

    struct sonor_context;
    struct sonor_state;
    struct sonor_full_params;

    typedef int32_t sonor_pos;
    typedef int32_t sonor_token;
    typedef int32_t sonor_seq_id;

    enum sonor_alignment_heads_preset {
        SONOR_AHEADS_NONE,
        SONOR_AHEADS_N_TOP_MOST,  // All heads from the N-top-most text-layers
        SONOR_AHEADS_CUSTOM,
        SONOR_AHEADS_TINY_EN,
        SONOR_AHEADS_TINY,
        SONOR_AHEADS_BASE_EN,
        SONOR_AHEADS_BASE,
        SONOR_AHEADS_SMALL_EN,
        SONOR_AHEADS_SMALL,
        SONOR_AHEADS_MEDIUM_EN,
        SONOR_AHEADS_MEDIUM,
        SONOR_AHEADS_LARGE_V1,
        SONOR_AHEADS_LARGE_V2,
        SONOR_AHEADS_LARGE_V3,
        SONOR_AHEADS_LARGE_V3_TURBO,
    };

    typedef struct sonor_ahead {
        int n_text_layer;
        int n_head;
    } sonor_ahead;

    typedef struct sonor_aheads {
        size_t n_heads;
        const sonor_ahead * heads;
    } sonor_aheads;

    struct sonor_context_params {
        bool  use_gpu;
        bool  flash_attn;
        int   gpu_device;  // CUDA device

        // [EXPERIMENTAL] Token-level timestamps with DTW
        bool dtw_token_timestamps;
        enum sonor_alignment_heads_preset dtw_aheads_preset;

        int dtw_n_top;
        struct sonor_aheads dtw_aheads;

        size_t dtw_mem_size; // TODO: remove
    };

    typedef struct sonor_token_data {
        sonor_token id;  // token id
        sonor_token tid; // forced timestamp token id

        float p;           // probability of the token
        float plog;        // log probability of the token
        float pt;          // probability of the timestamp token
        float ptsum;       // sum of probabilities of all timestamp tokens

        // token-level timestamp data
        // do not use if you haven't computed token-level timestamps
        int64_t t0;        // start time of the token
        int64_t t1;        //   end time of the token

        // [EXPERIMENTAL] Token-level timestamps with DTW
        // do not use if you haven't computed token-level timestamps with dtw
        // Roughly corresponds to the moment in audio in which the token was output
        int64_t t_dtw;

        float vlen;        // voice length of the token
    } sonor_token_data;

    typedef struct sonor_model_loader {
        void * context;

        size_t (*read)(void * ctx, void * output, size_t read_size);
        bool    (*eof)(void * ctx);
        void  (*close)(void * ctx);
    } sonor_model_loader;

    // grammar element type
    enum sonor_gretype {
        // end of rule definition
        SONOR_GRETYPE_END            = 0,

        // start of alternate definition for rule
        SONOR_GRETYPE_ALT            = 1,

        // non-terminal element: reference to rule
        SONOR_GRETYPE_RULE_REF       = 2,

        // terminal element: character (code point)
        SONOR_GRETYPE_CHAR           = 3,

        // inverse char(s) ([^a], [^a-b] [^abc])
        SONOR_GRETYPE_CHAR_NOT       = 4,

        // modifies a preceding SONOR_GRETYPE_CHAR or LLAMA_GRETYPE_CHAR_ALT to
        // be an inclusive range ([a-z])
        SONOR_GRETYPE_CHAR_RNG_UPPER = 5,

        // modifies a preceding SONOR_GRETYPE_CHAR or
        // SONOR_GRETYPE_CHAR_RNG_UPPER to add an alternate char to match ([ab], [a-zA])
        SONOR_GRETYPE_CHAR_ALT       = 6,
    };

    typedef struct sonor_grammar_element {
        enum sonor_gretype type;
        uint32_t             value; // Unicode code point or rule ID
    } sonor_grammar_element;

    typedef struct sonor_vad_params {
        float threshold;               // Probability threshold to consider as speech.
        int   min_speech_duration_ms;  // Min duration for a valid speech segment.
        int   min_silence_duration_ms; // Min silence duration to consider speech as ended.
        float max_speech_duration_s;   // Max duration of a speech segment before forcing a new segment.
        int   speech_pad_ms;           // Padding added before and after speech segments.
        float samples_overlap;         // Overlap in seconds when copying audio samples from speech segment.
    } sonor_vad_params;

    SONOR_API const char * sonor_version(void);

    // Various functions for loading a ggml sonor model.
    // Allocate (almost) all memory needed for the model.
    // Return NULL on failure
    SONOR_API struct sonor_context * sonor_init_from_file_with_params  (const char * path_model,              struct sonor_context_params params);
    SONOR_API struct sonor_context * sonor_init_from_buffer_with_params(void * buffer, size_t buffer_size,    struct sonor_context_params params);
    SONOR_API struct sonor_context * sonor_init_with_params            (struct sonor_model_loader * loader, struct sonor_context_params params);

    // These are the same as the above, but the internal state of the context is not allocated automatically
    // It is the responsibility of the caller to allocate the state using sonor_init_state() (#523)
    SONOR_API struct sonor_context * sonor_init_from_file_with_params_no_state  (const char * path_model,              struct sonor_context_params params);
    SONOR_API struct sonor_context * sonor_init_from_buffer_with_params_no_state(void * buffer, size_t buffer_size,    struct sonor_context_params params);
    SONOR_API struct sonor_context * sonor_init_with_params_no_state            (struct sonor_model_loader * loader, struct sonor_context_params params);

    SONOR_DEPRECATED(
        SONOR_API struct sonor_context * sonor_init_from_file(const char * path_model),
        "use sonor_init_from_file_with_params instead"
    );
    SONOR_DEPRECATED(
        SONOR_API struct sonor_context * sonor_init_from_buffer(void * buffer, size_t buffer_size),
        "use sonor_init_from_buffer_with_params instead"
    );
    SONOR_DEPRECATED(
        SONOR_API struct sonor_context * sonor_init(struct sonor_model_loader * loader),
        "use sonor_init_with_params instead"
    );
    SONOR_DEPRECATED(
        SONOR_API struct sonor_context * sonor_init_from_file_no_state(const char * path_model),
        "use sonor_init_from_file_with_params_no_state instead"
    );
    SONOR_DEPRECATED(
        SONOR_API struct sonor_context * sonor_init_from_buffer_no_state(void * buffer, size_t buffer_size),
        "use sonor_init_from_buffer_with_params_no_state instead"
    );
    SONOR_DEPRECATED(
        SONOR_API struct sonor_context * sonor_init_no_state(struct sonor_model_loader * loader),
        "use sonor_init_with_params_no_state instead"
    );

    SONOR_API struct sonor_state * sonor_init_state(struct sonor_context * ctx);

    // Given a context, enable use of OpenVINO for encode inference.
    // model_path: Optional path to OpenVINO encoder IR model. If set to nullptr,
    //                      the path will be generated from the ggml model path that was passed
    //                      in to sonor_init_from_file. For example, if 'path_model' was
    //                      "/path/to/ggml-base.en.bin", then OpenVINO IR model path will be
    //                      assumed to be "/path/to/ggml-base.en-encoder-openvino.xml".
    // device: OpenVINO device to run inference on ("CPU", "GPU", etc.)
    // cache_dir: Optional cache directory that can speed up init time, especially for
    //                     GPU, by caching compiled 'blobs' there.
    //                     Set to nullptr if not used.
    // Returns 0 on success. If OpenVINO is not enabled in build, this simply returns 1.
    SONOR_API int sonor_ctx_init_openvino_encoder_with_state(
        struct sonor_context * ctx,
          struct sonor_state * state,
                    const char * model_path,
                    const char * device,
                    const char * cache_dir);

    SONOR_API int sonor_ctx_init_openvino_encoder(
        struct sonor_context * ctx,
                    const char * model_path,
                    const char * device,
                    const char * cache_dir);

    // Frees all allocated memory
    SONOR_API void sonor_free      (struct sonor_context * ctx);
    SONOR_API void sonor_free_state(struct sonor_state * state);
    SONOR_API void sonor_free_params(struct sonor_full_params * params);
    SONOR_API void sonor_free_context_params(struct sonor_context_params * params);

    // Convert RAW PCM audio to log mel spectrogram.
    // The resulting spectrogram is stored inside the default state of the provided sonor context.
    // Returns 0 on success
    SONOR_API int sonor_pcm_to_mel(
            struct sonor_context * ctx,
                       const float * samples,
                               int   n_samples,
                               int   n_threads);

    SONOR_API int sonor_pcm_to_mel_with_state(
            struct sonor_context * ctx,
              struct sonor_state * state,
                       const float * samples,
                               int   n_samples,
                               int   n_threads);

    // This can be used to set a custom log mel spectrogram inside the default state of the provided sonor context.
    // Use this instead of sonor_pcm_to_mel() if you want to provide your own log mel spectrogram.
    // n_mel must be 80
    // Returns 0 on success
    SONOR_API int sonor_set_mel(
            struct sonor_context * ctx,
                       const float * data,
                               int   n_len,
                               int   n_mel);

    SONOR_API int sonor_set_mel_with_state(
            struct sonor_context * ctx,
              struct sonor_state * state,
                       const float * data,
                               int   n_len,
                               int   n_mel);

    // Run the Sonor encoder on the log mel spectrogram stored inside the default state in the provided sonor context.
    // Make sure to call sonor_pcm_to_mel() or sonor_set_mel() first.
    // offset can be used to specify the offset of the first frame in the spectrogram.
    // Returns 0 on success
    SONOR_API int sonor_encode(
            struct sonor_context * ctx,
                               int   offset,
                               int   n_threads);

    SONOR_API int sonor_encode_with_state(
            struct sonor_context * ctx,
              struct sonor_state * state,
                               int   offset,
                               int   n_threads);

    // Run the Sonor decoder to obtain the logits and probabilities for the next token.
    // Make sure to call sonor_encode() first.
    // tokens + n_tokens is the provided context for the decoder.
    // n_past is the number of tokens to use from previous decoder calls.
    // Returns 0 on success
    // TODO: add support for multiple decoders
    SONOR_API int sonor_decode(
            struct sonor_context * ctx,
               const sonor_token * tokens,
                               int   n_tokens,
                               int   n_past,
                               int   n_threads);

    SONOR_API int sonor_decode_with_state(
            struct sonor_context * ctx,
              struct sonor_state * state,
               const sonor_token * tokens,
                               int   n_tokens,
                               int   n_past,
                               int   n_threads);

    // Convert the provided text into tokens.
    // The tokens pointer must be large enough to hold the resulting tokens.
    // Returns the number of tokens on success, no more than n_max_tokens
    // Returns a negative number on failure - the number of tokens that would have been returned
    // TODO: not sure if correct
    SONOR_API int sonor_tokenize(
            struct sonor_context * ctx,
                        const char * text,
                     sonor_token * tokens,
                               int   n_max_tokens);

    // Return the number of tokens in the provided text
    // Equivalent to: -sonor_tokenize(ctx, text, NULL, 0)
    int sonor_token_count(struct sonor_context * ctx, const char * text);

    // Largest language id (i.e. number of available languages - 1)
    SONOR_API int sonor_lang_max_id(void);

    // Return the id of the specified language, returns -1 if not found
    // Examples:
    //   "de" -> 2
    //   "german" -> 2
    SONOR_API int sonor_lang_id(const char * lang);

    // Return the short string of the specified language id (e.g. 2 -> "de"), returns nullptr if not found
    SONOR_API const char * sonor_lang_str(int id);

    // Return the short string of the specified language name (e.g. 2 -> "german"), returns nullptr if not found
    SONOR_API const char * sonor_lang_str_full(int id);

    // Use mel data at offset_ms to try and auto-detect the spoken language
    // Make sure to call sonor_pcm_to_mel() or sonor_set_mel() first
    // Returns the top language id or negative on failure
    // If not null, fills the lang_probs array with the probabilities of all languages
    // The array must be sonor_lang_max_id() + 1 in size
    // ref: https://github.com/openai/sonor/blob/main/sonor/decoding.py#L18-L69
    SONOR_API int sonor_lang_auto_detect(
            struct sonor_context * ctx,
                               int   offset_ms,
                               int   n_threads,
                             float * lang_probs);

    SONOR_API int sonor_lang_auto_detect_with_state(
            struct sonor_context * ctx,
              struct sonor_state * state,
                               int   offset_ms,
                               int   n_threads,
                             float * lang_probs);

    SONOR_API int sonor_n_len           (struct sonor_context * ctx); // mel length
    SONOR_API int sonor_n_len_from_state(struct sonor_state * state); // mel length
    SONOR_API int sonor_n_vocab         (struct sonor_context * ctx);
    SONOR_API int sonor_n_text_ctx      (struct sonor_context * ctx);
    SONOR_API int sonor_n_audio_ctx     (struct sonor_context * ctx);
    SONOR_API int sonor_is_multilingual (struct sonor_context * ctx);

    SONOR_API int sonor_model_n_vocab      (struct sonor_context * ctx);
    SONOR_API int sonor_model_n_audio_ctx  (struct sonor_context * ctx);
    SONOR_API int sonor_model_n_audio_state(struct sonor_context * ctx);
    SONOR_API int sonor_model_n_audio_head (struct sonor_context * ctx);
    SONOR_API int sonor_model_n_audio_layer(struct sonor_context * ctx);
    SONOR_API int sonor_model_n_text_ctx   (struct sonor_context * ctx);
    SONOR_API int sonor_model_n_text_state (struct sonor_context * ctx);
    SONOR_API int sonor_model_n_text_head  (struct sonor_context * ctx);
    SONOR_API int sonor_model_n_text_layer (struct sonor_context * ctx);
    SONOR_API int sonor_model_n_mels       (struct sonor_context * ctx);
    SONOR_API int sonor_model_ftype        (struct sonor_context * ctx);
    SONOR_API int sonor_model_type         (struct sonor_context * ctx);

    // Token logits obtained from the last call to sonor_decode()
    // The logits for the last token are stored in the last row
    // Rows: n_tokens
    // Cols: n_vocab
    SONOR_API float * sonor_get_logits           (struct sonor_context * ctx);
    SONOR_API float * sonor_get_logits_from_state(struct sonor_state * state);

    // Token Id -> String. Uses the vocabulary in the provided context
    SONOR_API const char * sonor_token_to_str(struct sonor_context * ctx, sonor_token token);
    SONOR_API const char * sonor_model_type_readable(struct sonor_context * ctx);


    // Special tokens
    SONOR_API sonor_token sonor_token_eot (struct sonor_context * ctx);
    SONOR_API sonor_token sonor_token_sot (struct sonor_context * ctx);
    SONOR_API sonor_token sonor_token_solm(struct sonor_context * ctx);
    SONOR_API sonor_token sonor_token_prev(struct sonor_context * ctx);
    SONOR_API sonor_token sonor_token_nosp(struct sonor_context * ctx);
    SONOR_API sonor_token sonor_token_not (struct sonor_context * ctx);
    SONOR_API sonor_token sonor_token_beg (struct sonor_context * ctx);
    SONOR_API sonor_token sonor_token_lang(struct sonor_context * ctx, int lang_id);

    // Task tokens
    SONOR_API sonor_token sonor_token_translate (struct sonor_context * ctx);
    SONOR_API sonor_token sonor_token_transcribe(struct sonor_context * ctx);

    // Performance information from the default state.
    struct sonor_timings {
        float sample_ms;
        float encode_ms;
        float decode_ms;
        float batchd_ms;
        float prompt_ms;
    };
    SONOR_API struct sonor_timings * sonor_get_timings(struct sonor_context * ctx);
    SONOR_API void sonor_print_timings(struct sonor_context * ctx);
    SONOR_API void sonor_reset_timings(struct sonor_context * ctx);

    // Print system information
    SONOR_API const char * sonor_print_system_info(void);

    ////////////////////////////////////////////////////////////////////////////

    // Available sampling strategies
    enum sonor_sampling_strategy {
        SONOR_SAMPLING_GREEDY,      // similar to OpenAI's GreedyDecoder
        SONOR_SAMPLING_BEAM_SEARCH, // similar to OpenAI's BeamSearchDecoder
    };

    // Text segment callback
    // Called on every newly generated text segment
    // Use the sonor_full_...() functions to obtain the text segments
    typedef void (*sonor_new_segment_callback)(struct sonor_context * ctx, struct sonor_state * state, int n_new, void * user_data);

    // Progress callback
    typedef void (*sonor_progress_callback)(struct sonor_context * ctx, struct sonor_state * state, int progress, void * user_data);

    // Encoder begin callback
    // If not NULL, called before the encoder starts
    // If it returns false, the computation is aborted
    typedef bool (*sonor_encoder_begin_callback)(struct sonor_context * ctx, struct sonor_state * state, void * user_data);

    // Logits filter callback
    // Can be used to modify the logits before sampling
    // If not NULL, called after applying temperature to logits
    typedef void (*sonor_logits_filter_callback)(
            struct sonor_context * ctx,
              struct sonor_state * state,
          const sonor_token_data * tokens,
                               int   n_tokens,
                             float * logits,
                              void * user_data);

    // Parameters for the sonor_full() function
    // If you change the order or add new parameters, make sure to update the default values in sonor.cpp:
    // sonor_full_default_params()
    struct sonor_full_params {
        enum sonor_sampling_strategy strategy;

        int n_threads;
        int n_max_text_ctx;     // max tokens to use from past text as prompt for the decoder
        int offset_ms;          // start offset in ms
        int duration_ms;        // audio duration to process in ms

        bool translate;
        bool no_context;        // do not use past transcription (if any) as initial prompt for the decoder
        bool no_timestamps;     // do not generate timestamps
        bool single_segment;    // force single segment output (useful for streaming)
        bool print_special;     // print special tokens (e.g. <SOT>, <EOT>, <BEG>, etc.)
        bool print_progress;    // print progress information
        bool print_realtime;    // print results from within sonor.cpp (avoid it, use callback instead)
        bool print_timestamps;  // print timestamps for each text segment when printing realtime

        // [EXPERIMENTAL] token-level timestamps
        bool  token_timestamps; // enable token-level timestamps
        float thold_pt;         // timestamp token probability threshold (~0.01)
        float thold_ptsum;      // timestamp token sum probability threshold (~0.01)
        int   max_len;          // max segment length in characters
        bool  split_on_word;    // split on word rather than on token (when used with max_len)
        int   max_tokens;       // max tokens per segment (0 = no limit)

        // [EXPERIMENTAL] speed-up techniques
        // note: these can significantly reduce the quality of the output
        bool debug_mode;        // enable debug_mode provides extra info (eg. Dump log_mel)
        int  audio_ctx;         // overwrite the audio context size (0 = use default)

        // [EXPERIMENTAL] [TDRZ] tinydiarize
        bool tdrz_enable;       // enable tinydiarize speaker turn detection

        // A regular expression that matches tokens to suppress
        const char * suppress_regex;

        // tokens to provide to the sonor decoder as initial prompt
        // these are prepended to any existing text context from a previous call
        // use sonor_tokenize() to convert text to tokens
        // maximum of sonor_n_text_ctx()/2 tokens are used (typically 224)
        const char * initial_prompt;
        bool carry_initial_prompt; // if true, always prepend initial_prompt to every decode window (may reduce conditioning on previous text)
        const sonor_token * prompt_tokens;
        int prompt_n_tokens;

        // for auto-detection, set to nullptr, "" or "auto"
        const char * language;
        bool detect_language;

        // common decoding parameters:
        bool suppress_blank; // ref: https://github.com/openai/sonor/blob/f82bc59f5ea234d4b97fb2860842ed38519f7e65/sonor/decoding.py#L89
        bool suppress_nst;   // non-speech tokens, ref: https://github.com/openai/sonor/blob/7858aa9c08d98f75575035ecd6481f462d66ca27/sonor/tokenizer.py#L224-L253

        float temperature;      // initial decoding temperature, ref: https://ai.stackexchange.com/a/32478
        float max_initial_ts;   // ref: https://github.com/openai/sonor/blob/f82bc59f5ea234d4b97fb2860842ed38519f7e65/sonor/decoding.py#L97
        float length_penalty;   // ref: https://github.com/openai/sonor/blob/f82bc59f5ea234d4b97fb2860842ed38519f7e65/sonor/transcribe.py#L267

        // fallback parameters
        // ref: https://github.com/openai/sonor/blob/f82bc59f5ea234d4b97fb2860842ed38519f7e65/sonor/transcribe.py#L274-L278
        float temperature_inc;
        float entropy_thold;    // similar to OpenAI's "compression_ratio_threshold"
        float logprob_thold;
        float no_speech_thold;

        struct {
            int best_of;    // ref: https://github.com/openai/sonor/blob/f82bc59f5ea234d4b97fb2860842ed38519f7e65/sonor/transcribe.py#L264
        } greedy;

        struct {
            int beam_size;  // ref: https://github.com/openai/sonor/blob/f82bc59f5ea234d4b97fb2860842ed38519f7e65/sonor/transcribe.py#L265

            float patience; // TODO: not implemented, ref: https://arxiv.org/pdf/2204.05424.pdf
        } beam_search;

        // called for every newly generated text segment
        sonor_new_segment_callback new_segment_callback;
        void * new_segment_callback_user_data;

        // called on each progress update
        sonor_progress_callback progress_callback;
        void * progress_callback_user_data;

        // called each time before the encoder starts
        sonor_encoder_begin_callback encoder_begin_callback;
        void * encoder_begin_callback_user_data;

        // called each time before ggml computation starts
        ggml_abort_callback abort_callback;
        void * abort_callback_user_data;

        // called by each decoder to filter obtained logits
        sonor_logits_filter_callback logits_filter_callback;
        void * logits_filter_callback_user_data;

        const sonor_grammar_element ** grammar_rules;
        size_t                           n_grammar_rules;
        size_t                           i_start_rule;
        float                            grammar_penalty;

        // Voice Activity Detection (VAD) params
        bool         vad;                         // Enable VAD
        const char * vad_model_path;              // Path to VAD model

        sonor_vad_params vad_params;
    };

    // NOTE: this function allocates memory, and it is the responsibility of the caller to free the pointer - see sonor_free_context_params & sonor_free_params()
    SONOR_API struct sonor_context_params * sonor_context_default_params_by_ref(void);
    SONOR_API struct sonor_context_params   sonor_context_default_params       (void);

    SONOR_API struct sonor_full_params * sonor_full_default_params_by_ref(enum sonor_sampling_strategy strategy);
    SONOR_API struct sonor_full_params   sonor_full_default_params       (enum sonor_sampling_strategy strategy);

    // Run the entire model: PCM -> log mel spectrogram -> encoder -> decoder -> text
    // Not thread safe for same context
    // Uses the specified decoding strategy to obtain the text.
    SONOR_API int sonor_full(
                struct sonor_context * ctx,
            struct sonor_full_params   params,
                           const float * samples,
                                   int   n_samples);

    SONOR_API int sonor_full_with_state(
                struct sonor_context * ctx,
                  struct sonor_state * state,
            struct sonor_full_params   params,
                           const float * samples,
                                   int   n_samples);

    // Split the input audio in chunks and process each chunk separately using sonor_full_with_state()
    // Result is stored in the default state of the context
    // Not thread safe if executed in parallel on the same context.
    // It seems this approach can offer some speedup in some cases.
    // However, the transcription accuracy can be worse at the beginning and end of each chunk.
    SONOR_API int sonor_full_parallel(
                struct sonor_context * ctx,
            struct sonor_full_params   params,
                           const float * samples,
                                   int   n_samples,
                                   int   n_processors);

    // Number of generated text segments
    // A segment can be a few words, a sentence, or even a paragraph.
    SONOR_API int sonor_full_n_segments           (struct sonor_context * ctx);
    SONOR_API int sonor_full_n_segments_from_state(struct sonor_state * state);

    // Language id associated with the context's default state
    SONOR_API int sonor_full_lang_id(struct sonor_context * ctx);

    // Language id associated with the provided state
    SONOR_API int sonor_full_lang_id_from_state(struct sonor_state * state);

    // Get the start and end time of the specified segment
    SONOR_API int64_t sonor_full_get_segment_t0           (struct sonor_context * ctx, int i_segment);
    SONOR_API int64_t sonor_full_get_segment_t0_from_state(struct sonor_state * state, int i_segment);

    SONOR_API int64_t sonor_full_get_segment_t1           (struct sonor_context * ctx, int i_segment);
    SONOR_API int64_t sonor_full_get_segment_t1_from_state(struct sonor_state * state, int i_segment);

    // Get whether the next segment is predicted as a speaker turn
    SONOR_API bool sonor_full_get_segment_speaker_turn_next(struct sonor_context * ctx, int i_segment);
    SONOR_API bool sonor_full_get_segment_speaker_turn_next_from_state(struct sonor_state * state, int i_segment);

    // Get the text of the specified segment
    SONOR_API const char * sonor_full_get_segment_text           (struct sonor_context * ctx, int i_segment);
    SONOR_API const char * sonor_full_get_segment_text_from_state(struct sonor_state * state, int i_segment);

    // Get number of tokens in the specified segment
    SONOR_API int sonor_full_n_tokens           (struct sonor_context * ctx, int i_segment);
    SONOR_API int sonor_full_n_tokens_from_state(struct sonor_state * state, int i_segment);

    // Get the token text of the specified token in the specified segment
    SONOR_API const char * sonor_full_get_token_text           (struct sonor_context * ctx, int i_segment, int i_token);
    SONOR_API const char * sonor_full_get_token_text_from_state(struct sonor_context * ctx, struct sonor_state * state, int i_segment, int i_token);

    SONOR_API sonor_token sonor_full_get_token_id           (struct sonor_context * ctx, int i_segment, int i_token);
    SONOR_API sonor_token sonor_full_get_token_id_from_state(struct sonor_state * state, int i_segment, int i_token);

    // Get token data for the specified token in the specified segment
    // This contains probabilities, timestamps, etc.
    SONOR_API sonor_token_data sonor_full_get_token_data           (struct sonor_context * ctx, int i_segment, int i_token);
    SONOR_API sonor_token_data sonor_full_get_token_data_from_state(struct sonor_state * state, int i_segment, int i_token);

    // Get the probability of the specified token in the specified segment
    SONOR_API float sonor_full_get_token_p           (struct sonor_context * ctx, int i_segment, int i_token);
    SONOR_API float sonor_full_get_token_p_from_state(struct sonor_state * state, int i_segment, int i_token);

    //
    // Voice Activity Detection (VAD)
    //

    struct sonor_vad_context;

    SONOR_API struct sonor_vad_params sonor_vad_default_params(void);

    struct sonor_vad_context_params {
        int   n_threads;  // The number of threads to use for processing.
        bool  use_gpu;
        int   gpu_device; // CUDA device
    };

    SONOR_API struct sonor_vad_context_params sonor_vad_default_context_params(void);

    SONOR_API struct sonor_vad_context * sonor_vad_init_from_file_with_params(const char * path_model,              struct sonor_vad_context_params params);
    SONOR_API struct sonor_vad_context * sonor_vad_init_with_params          (struct sonor_model_loader * loader, struct sonor_vad_context_params params);

    SONOR_API bool sonor_vad_detect_speech(
            struct sonor_vad_context * vctx,
                           const float * samples,
                                   int   n_samples);

    // Like sonor_vad_detect_speech, but does not reset LSTM state.
    // Use for streaming: call sonor_vad_reset_state() between utterances.
    SONOR_API bool sonor_vad_detect_speech_no_reset(
            struct sonor_vad_context * vctx,
                           const float * samples,
                                   int   n_samples);

    // Reset LSTM hidden/cell states to zero.
    SONOR_API void sonor_vad_reset_state(struct sonor_vad_context * vctx);

    SONOR_API int     sonor_vad_n_probs(struct sonor_vad_context * vctx);
    SONOR_API float * sonor_vad_probs  (struct sonor_vad_context * vctx);

    struct sonor_vad_segments;

    SONOR_API struct sonor_vad_segments * sonor_vad_segments_from_probs(
            struct sonor_vad_context * vctx,
            struct sonor_vad_params    params);

    SONOR_API struct sonor_vad_segments * sonor_vad_segments_from_samples(
            struct sonor_vad_context * vctx,
            struct sonor_vad_params    params,
                           const float * samples,
                                   int   n_samples);

    SONOR_API int sonor_vad_segments_n_segments(struct sonor_vad_segments * segments);

    SONOR_API float sonor_vad_segments_get_segment_t0(struct sonor_vad_segments * segments, int i_segment);
    SONOR_API float sonor_vad_segments_get_segment_t1(struct sonor_vad_segments * segments, int i_segment);

    SONOR_API void sonor_vad_free_segments(struct sonor_vad_segments * segments);
    SONOR_API void sonor_vad_free         (struct sonor_vad_context  * ctx);

    ////////////////////////////////////////////////////////////////////////////

    // Temporary helpers needed for exposing ggml interface

    SONOR_API int          sonor_bench_memcpy          (int n_threads);
    SONOR_API const char * sonor_bench_memcpy_str      (int n_threads);
    SONOR_API int          sonor_bench_ggml_mul_mat    (int n_threads);
    SONOR_API const char * sonor_bench_ggml_mul_mat_str(int n_threads);

    // Control logging output; default behavior is to print to stderr

    SONOR_API void sonor_log_set(ggml_log_callback log_callback, void * user_data);

    // Get the no_speech probability for the specified segment
    SONOR_API float sonor_full_get_segment_no_speech_prob           (struct sonor_context * ctx, int i_segment);
    SONOR_API float sonor_full_get_segment_no_speech_prob_from_state(struct sonor_state * state, int i_segment);
#ifdef __cplusplus
}
#endif

#endif
