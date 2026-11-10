// JNI bridge to whisper.cpp for Breeze-ASR-26 GGML, mirroring
// ios/Breeze/BreezeRecognizer.swift. Calls must be serialized by the caller.
#include <jni.h>

#include <string>

#include "whisper.h"

extern "C" JNIEXPORT jlong JNICALL
Java_com_example_an_1xin_1ban_WhisperNative_load(JNIEnv *env, jobject, jstring path) {
  const char *model = env->GetStringUTFChars(path, nullptr);
  whisper_context_params params = whisper_context_default_params();
  params.use_gpu = false;
  whisper_context *ctx = whisper_init_from_file_with_params(model, params);
  env->ReleaseStringUTFChars(path, model);
  return reinterpret_cast<jlong>(ctx);
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_an_1xin_1ban_WhisperNative_free(JNIEnv *, jobject, jlong handle) {
  whisper_free(reinterpret_cast<whisper_context *>(handle));
}

// Returns the UTF-8 transcript of 16 kHz mono samples, or null on failure.
// Bytes rather than a String: JNI's NewStringUTF rejects 4-byte UTF-8.
extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_example_an_1xin_1ban_WhisperNative_transcribe(
    JNIEnv *env, jobject, jlong handle, jfloatArray samples, jint threads) {
  auto *ctx = reinterpret_cast<whisper_context *>(handle);
  whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
  params.language = "zh";
  params.n_threads = threads;
  params.no_context = true;
  params.no_timestamps = true;
  params.translate = false;
  params.print_progress = false;
  params.print_realtime = false;
  params.print_special = false;
  params.print_timestamps = false;

  const jsize count = env->GetArrayLength(samples);
  jfloat *pcm = env->GetFloatArrayElements(samples, nullptr);
  const int status = whisper_full(ctx, params, pcm, count);
  env->ReleaseFloatArrayElements(samples, pcm, JNI_ABORT);
  if (status != 0) return nullptr;

  std::string text;
  const int segments = whisper_full_n_segments(ctx);
  for (int i = 0; i < segments; ++i) {
    if (const char *part = whisper_full_get_segment_text(ctx, i)) text += part;
  }
  jbyteArray out = env->NewByteArray(static_cast<jsize>(text.size()));
  env->SetByteArrayRegion(out, 0, static_cast<jsize>(text.size()),
                          reinterpret_cast<const jbyte *>(text.data()));
  return out;
}
