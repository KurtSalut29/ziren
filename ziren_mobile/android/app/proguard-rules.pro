# google_mlkit_text_recognition ships recognizers for Chinese, Devanagari,
# Japanese, and Korean as optional, separately-published artifacts. This app
# only depends on the Latin recognizer, so those classes are never on the
# classpath — R8 can't verify them and fails the release build without these
# rules (see build/app/outputs/mapping/release/missing_rules.txt, generated
# by the first `flutter build apk --release` run on 2026-09-14).
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions

# flutter_local_notifications keeps its notification cache with Gson, which
# reads generic types through TypeToken subclasses. R8 strips the generic
# signatures, and every cancel() then throws "TypeToken must be created with a
# type argument" - in RELEASE builds only (on-device check 2026-10-06). That
# silently broke cancelling notifications: a responder's insistent dispatch
# alarm could not be stopped by answering it, and the closed-app alert
# (cancel-then-show) was never shown. Debug builds are not shrunk, which is why
# every debug test passed.
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.dexterous.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
