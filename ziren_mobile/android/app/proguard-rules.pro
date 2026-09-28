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
