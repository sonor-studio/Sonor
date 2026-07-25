#ifndef RUBY_SONOR_H
#define RUBY_SONOR_H

#include <ruby.h>
#include <ruby/util.h>
#include <ruby/memory_view.h>
#include "sonor.h"

typedef struct {
  VALUE *context;
  VALUE user_data;
  VALUE callback;
  VALUE callbacks;
} ruby_sonor_callback_container;

typedef struct {
  struct sonor_context *context;
} ruby_sonor;

typedef struct ruby_sonor_context_params {
  struct sonor_context_params params;
} ruby_sonor_context_params;

typedef struct {
  struct sonor_full_params params;
  bool diarize;
  ruby_sonor_callback_container *new_segment_callback_container;
  ruby_sonor_callback_container *progress_callback_container;
  ruby_sonor_callback_container *encoder_begin_callback_container;
  ruby_sonor_callback_container *abort_callback_container;
  VALUE vad_params;
} ruby_sonor_params;

typedef struct {
  struct sonor_vad_params params;
} ruby_sonor_vad_params;

typedef struct {
  VALUE context;
  int index;
} ruby_sonor_segment;

typedef struct {
  sonor_token_data *token_data;
  VALUE text;
} ruby_sonor_token;

typedef struct {
  VALUE context;
} ruby_sonor_model;

typedef struct {
  struct sonor_vad_segments *segments;
} ruby_sonor_vad_segments;

typedef struct {
  VALUE segments;
  int index;
} ruby_sonor_vad_segment;

typedef struct {
  struct sonor_vad_context *context;
} ruby_sonor_vad_context;

typedef struct parsed_samples_t {
  float *samples;
  int n_samples;
  rb_memory_view_t memview;
  bool memview_exported;
} parsed_samples_t;

#define GetContext(obj, rw) do { \
  TypedData_Get_Struct((obj), ruby_sonor, &ruby_sonor_type, (rw)); \
  if ((rw)->context == NULL) { \
    rb_raise(rb_eRuntimeError, "Not initialized"); \
  } \
} while (0)

#define GetContextParams(obj, rwcp) do { \
  TypedData_Get_Struct((obj), ruby_sonor_context_params, &ruby_sonor_context_params_type, (rwcp)); \
} while (0)

#define GetToken(obj, rwt) do { \
  TypedData_Get_Struct((obj), ruby_sonor_token, &ruby_sonor_token_type, (rwt)); \
  if ((rwt)->token_data == NULL) { \
    rb_raise(rb_eRuntimeError, "Not initialized"); \
  } \
} while (0)

#define GetVADContext(obj, rwvc) do { \
    TypedData_Get_Struct((obj), ruby_sonor_vad_context, &ruby_sonor_vad_context_type, (rwvc)); \
    if ((rwvc)->context == NULL) { \
      rb_raise(rb_eRuntimeError, "Not initialized"); \
    } \
} while (0)

#define GetVADParams(obj, rwvp) do { \
  TypedData_Get_Struct((obj), ruby_sonor_vad_params, &ruby_sonor_vad_params_type, (rwvp)); \
} while (0)

#define GetVADSegments(obj, rwvss) do { \
  TypedData_Get_Struct((obj), ruby_sonor_vad_segments, &ruby_sonor_vad_segments_type, (rwvss)); \
  if ((rwvss)->segments == NULL) { \
    rb_raise(rb_eRuntimeError, "Not initialized"); \
  } \
} while (0)

#endif
