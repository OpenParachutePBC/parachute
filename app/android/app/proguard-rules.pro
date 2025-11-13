# Flutter plugin keep rules
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**

# Keep all plugin classes
-keep class io.flutter.plugins.** { *; }
-keep class dev.flutter.plugins.** { *; }

# Keep path_provider plugin
-keep class io.flutter.plugins.pathprovider.** { *; }
-dontwarn io.flutter.plugins.pathprovider.**

# Keep shared_preferences plugin
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-dontwarn io.flutter.plugins.sharedpreferences.**

# Keep flutter_blue_plus plugin
-keep class com.lib.flutter_blue_plus.** { *; }
-dontwarn com.lib.flutter_blue_plus.**

# Keep MediaPipe classes for flutter_gemma
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# Keep TensorFlow Lite classes
-keep class org.tensorflow.** { *; }
-dontwarn org.tensorflow.**

# Keep Google flatbuffers
-keep class com.google.flatbuffers.** { *; }
-dontwarn com.google.flatbuffers.**

# Keep Opus audio codec
-keep class com.getkeepsafe.relinker.** { *; }
-dontwarn com.getkeepsafe.relinker.**

# Keep all native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep Parcelables
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}
