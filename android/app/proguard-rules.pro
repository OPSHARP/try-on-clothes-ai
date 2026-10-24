# Disable aggressive R8 bytecode optimization passes that break reflection
-dontoptimize

# Flutter specific
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.engine.** { *; }

# Google Play Services (used by Google Mobile Ads)
-keep class com.google.android.gms.** { *; }

# Google Mobile Ads (AdMob) & Play Services Ads
-keep public class com.google.android.gms.ads.** {
   public *;
}
-keep public class com.google.ads.** {
   public *;
}
-keep class com.google.android.gms.internal.ads.** { *; }
-dontwarn com.google.android.gms.ads.**
-dontwarn com.google.ads.**

# AndroidX WorkManager (used by Google Mobile Ads)
-keep class androidx.work.** { *; }
-keep class * extends androidx.work.Worker { *; }
-keep class * extends androidx.work.ListenableWorker { *; }
-keep class androidx.work.impl.** { *; }
-keep class androidx.work.impl.WorkDatabase_Impl {
    public <init>();
    *;
}
-keep class androidx.work.impl.WorkDatabase { *; }
-dontwarn androidx.work.**

# AndroidX Room (used by WorkManager)
-keep class androidx.room.** { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class * extends androidx.room.RoomOpenHelper { *; }
-keep class * extends androidx.room.EntityInsertionAdapter { *; }
-keep class * extends androidx.room.SharedSQLiteStatement { *; }
-dontwarn androidx.room.**

# AndroidX SQLite
-keep class androidx.sqlite.** { *; }
-dontwarn androidx.sqlite.**

# AndroidX Startup
-keep class androidx.startup.** { *; }
-keep class * extends androidx.startup.Initializer { *; }
-keep class androidx.work.WorkManagerInitializer { *; }
-dontwarn androidx.startup.**

# AndroidX Lifecycle & Core
-keep class androidx.lifecycle.** { *; }
-dontwarn androidx.lifecycle.**

# Native API Key Provider (JNI bridge)
-keep class com.tryon.clothesai.NativeApiKeyProvider { *; }
-keep class com.tryon.clothesai.MainActivity { *; }

# Keep model classes used with JSON serialization/deserialization
-keep class com.tryon.clothesai.** { *; }

# Keep enum types used in Dart-Flutter bridge
-keepclassmembers enum * { *; }

# Keep annotations
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keepattributes Signature
-keepattributes Exceptions,InnerClasses

# Kotlin
-keep class kotlin.** { *; }

# General rules for apps
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class org.xmlpull.v1.** { *; }
-dontwarn org.xmlpull.v1.**

# Google Play Core (required by Flutter's deferred components)
-keep class com.google.android.play.core.splitcompat.** { *; }
-keep class com.google.android.play.core.splitinstall.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# Google Play In-App Updates
-keep class com.google.android.play.core.appupdate.** { *; }
-keep class com.google.android.play.core.install.** { *; }
-dontwarn com.google.android.play.core.appupdate.**
-dontwarn com.google.android.play.core.install.**

# Google Play Billing Client 8.0+
-keep class com.android.billingclient.** { *; }
-dontwarn com.android.billingclient.**

