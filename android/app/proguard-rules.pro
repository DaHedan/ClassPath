# R8 全量模式下，缺失类会直接让 release 构建失败。
# google_mlkit_text_recognition 插件里对「天城文 / 日文 / 韩文」识别器仍有引用，
# 但本项目只打包了中文模型（见 app/build.gradle.kts 的 text-recognition-chinese），
# 这些类本来就不存在，也不会走到对应分支，忽略即可。
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
