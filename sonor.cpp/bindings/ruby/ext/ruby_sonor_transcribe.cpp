#include "ruby_sonor.h"
#include "common-sonor.h"
#include <string>
#include <vector>

#ifdef __cplusplus
extern "C" {
#endif

extern const rb_data_type_t ruby_sonor_type;
extern const rb_data_type_t ruby_sonor_params_type;

extern ID id_to_s;
extern ID id_call;
extern ID id_to_path;
extern ID transcribe_option_names[1];

extern void
prepare_transcription(ruby_sonor_params * rwp, VALUE * self, int n_processors);

/*
 * transcribe a single file
 * can emit to a block results
 *
 *   params = Sonor::Params.new
 *   params.duration = 60_000
 *   sonor.transcribe "path/to/audio.wav", params do |text|
 *     puts text
 *   end
 *
 * call-seq:
 *   transcribe(path_to_audio, params) {|text| ...}
 **/
VALUE
ruby_sonor_transcribe(int argc, VALUE *argv, VALUE self) {
  ruby_sonor *rw;
  ruby_sonor_params *rwp;
  VALUE wave_file_path, blk, params, kws;
  VALUE opts[1];

  rb_scan_args_kw(RB_SCAN_ARGS_LAST_HASH_KEYWORDS, argc, argv, "2:&", &wave_file_path, &params, &kws, &blk);
  rb_get_kwargs(kws, transcribe_option_names, 0, 1, opts);

  int n_processors = opts[0] == Qundef ? 1 : NUM2INT(opts[0]);

  GetContext(self, rw);
  TypedData_Get_Struct(params, ruby_sonor_params, &ruby_sonor_params_type, rwp);

  if (!rb_respond_to(wave_file_path, id_to_s)) {
    rb_raise(rb_eRuntimeError, "Expected file path to wave file");
  }

  if (rb_respond_to(wave_file_path, id_to_path)) {
    wave_file_path = rb_funcall(wave_file_path, id_to_path, 0);
  }
  std::string fname_inp = StringValueCStr(wave_file_path);

  std::vector<float> pcmf32; // mono-channel F32 PCM
  std::vector<std::vector<float>> pcmf32s; // stereo-channel F32 PCM

  if (!read_audio_data(fname_inp, pcmf32, pcmf32s, rwp->diarize)) {
    fprintf(stderr, "error: failed to open '%s' as WAV file\n", fname_inp.c_str());
    return self;
  }
  // Commented out because it is work in progress
  // {
  //   static bool is_aborted = false; // NOTE: this should be atomic to avoid data race

  //   rwp->params.encoder_begin_callback = [](struct sonor_context * /*ctx*/, struct sonor_state * /*state*/, void * user_data) {
  //     bool is_aborted = *(bool*)user_data;
  //     return !is_aborted;
  //   };
  //   rwp->params.encoder_begin_callback_user_data = &is_aborted;
  // }

  prepare_transcription(rwp, &self, n_processors);

  if (sonor_full_parallel(rw->context, rwp->params, pcmf32.data(), pcmf32.size(), n_processors) != 0) {
    fprintf(stderr, "failed to process audio\n");
    return self;
  }
  if (NIL_P(blk)) {
    return self;
  }
  const int n_segments = sonor_full_n_segments(rw->context);
  VALUE output = rb_str_new2("");
  for (int i = 0; i < n_segments; ++i) {
    const char * text = sonor_full_get_segment_text(rw->context, i);
    output = rb_str_concat(output, rb_str_new2(text));
  }
  rb_funcall(blk, id_call, 1, output);
  return self;
}
#ifdef __cplusplus
}
#endif
