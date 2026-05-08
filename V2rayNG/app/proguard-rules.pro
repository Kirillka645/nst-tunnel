# =============================================================================
#  NST Tunnel ProGuard / R8 rules
#
#  These rules let the release build run with `isMinifyEnabled = true` and
#  `isShrinkResources = true` without breaking JNI bridges or JSON
#  serialization.
#
#  Categories:
#    1. Stack trace readability
#    2. Kotlin / coroutines
#    3. Gson reflection-based serialization
#    4. MMKV (Tencent native KV store)
#    5. libv2ray / AndroidLibXrayLite (gomobile-generated bindings)
#    6. WorkManager + Tasker plugin reflection
#    7. AndroidX / Material defaults are already in default-android-optimize.pro
# =============================================================================

# ---- 1. Stack traces -------------------------------------------------------
# Keep file:line info so crash reports remain useful after minification.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Generic attributes broadly needed by reflection / Kotlin metadata.
-keepattributes Signature,*Annotation*,EnclosingMethod,InnerClasses,Exceptions

# ---- 2. Kotlin -------------------------------------------------------------
-dontwarn kotlin.**
-dontwarn kotlinx.coroutines.debug.**
-keep class kotlin.Metadata { *; }

# Coroutines: the debug agent class isn't shipped, just silence the warning.
-dontwarn kotlinx.coroutines.flow.**

# ---- 3. Gson ---------------------------------------------------------------
# Gson uses reflection on serialised model classes. Keep DTOs and any class
# annotated with @SerializedName as well as their fields.
-keepattributes RuntimeVisibleAnnotations,RuntimeVisibleParameterAnnotations
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
    @com.google.gson.annotations.Expose <fields>;
}
-keep class com.v2ray.ang.dto.** { *; }
-keep class com.v2ray.ang.fmt.** { *; }
-keep class com.v2ray.ang.AppConfig$** { *; }

# Gson internals
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }
-keep class com.google.gson.examples.android.model.** { *; }

# ---- 4. MMKV ---------------------------------------------------------------
# MMKV registers native methods on its core class.
-keep class com.tencent.mmkv.** { *; }
-keepclassmembers class com.tencent.mmkv.** {
    native <methods>;
}

# ---- 5. libv2ray / Go bindings --------------------------------------------
# AndroidLibXrayLite ships a gomobile-generated AAR whose package layout is
# `libv2ray.*` / `go.*`. JNI lookups depend on the original package & class
# names being preserved.
-keep class libv2ray.** { *; }
-keep class go.** { *; }
-keep class com.v2ray.ang.helper.** { *; }
-dontwarn libv2ray.**
-dontwarn go.**

# Service classes referenced from manifest must stay reachable by name.
-keep class com.v2ray.ang.service.** { *; }
-keep class com.v2ray.ang.receiver.** { *; }

# ---- 6. WorkManager + Tasker ----------------------------------------------
-keep class androidx.work.impl.** { *; }
-keepclassmembers class * extends androidx.work.Worker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}
-keepclassmembers class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}

# Tasker plugin event/action classes are looked up reflectively.
-keep class com.v2ray.ang.ui.TaskerActivity { *; }

# ---- 7. OkHttp / okio ------------------------------------------------------
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# ---- 8. EditorKit (Blacksquircle) -----------------------------------------
-keep class com.blacksquircle.ui.** { *; }
-dontwarn com.blacksquircle.ui.**

# ---- 9. Toasty / ZXing -----------------------------------------------------
-keep class es.dmoral.toasty.** { *; }
-dontwarn com.google.zxing.**
