# ─────────────────────────────────────────────────────────────────────────────
# Property Pulse — ProGuard / R8 rules
# ─────────────────────────────────────────────────────────────────────────────

# ── Flutter engine ────────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }

# ── gRPC (used by Firestore, Auth, and all Firebase SDKs) ────────────────────
#
# CRITICAL: Without these rules R8 strips the gRPC ServiceLoader registrations
# for DnsNameResolverProvider and OkHttpChannelProvider, which causes:
#   ManagedChannelImpl: [{0}] Failed to resolve name. status={1}
# and breaks all Firestore / Firebase real-time connections in release builds.
#
-keep class io.grpc.** { *; }
-keep interface io.grpc.** { *; }
-dontwarn io.grpc.**

# ServiceLoader SPI — R8 must not strip these or gRPC cannot boot its channel.
-keep class io.grpc.internal.DnsNameResolverProvider { *; }
-keep class io.grpc.internal.PickFirstLoadBalancerProvider { *; }
-keep class io.grpc.okhttp.OkHttpChannelProvider { *; }
-keep class io.grpc.android.** { *; }

# ── Protobuf (Firestore wire format uses proto3) ───────────────────────────────
-keep class com.google.protobuf.** { *; }
-keep class com.google.protobuf.GeneratedMessageLite { *; }
-dontwarn com.google.protobuf.**

# ── Java util logging (gRPC uses j.u.l internally) ───────────────────────────
# Stripping this causes the {0}/{1} unfilled-placeholder bug in logcat messages.
-keep class java.util.logging.** { *; }

# ── Firebase ──────────────────────────────────────────────────────────────────
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keepattributes EnclosingMethod

# Firebase Crashlytics — preserve mapping for de-obfuscated crash reports
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception
-keep class com.google.firebase.crashlytics.** { *; }

# Firebase Firestore — model classes use reflection for serialization
-keep class com.google.firebase.firestore.** { *; }

# Firebase Auth
-keep class com.google.firebase.auth.** { *; }

# Firebase Auth reCAPTCHA client — loaded reflectively during email/password
# sign-in. CRITICAL: if R8 strips these classes the sign-in Task silently
# never completes (infinite spinner) in minified release builds only.
-keep class com.google.android.recaptcha.** { *; }
-dontwarn com.google.android.recaptcha.**

# Firebase Messaging (FCM)
-keep class com.google.firebase.messaging.** { *; }

# ── Google Sign-In / Play Services ───────────────────────────────────────────
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }
-keep class com.google.android.gms.tasks.** { *; }

# ── Google Maps ───────────────────────────────────────────────────────────────
-keep class com.google.android.gms.maps.** { *; }
-keep class com.google.maps.android.** { *; }

# ── Stripe ────────────────────────────────────────────────────────────────────
-keep class com.stripe.** { *; }
-keep class com.reactnativestripesdk.** { *; }

# ── OkHttp (used internally by Firebase, Stripe, http package) ───────────────
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-keep class okio.** { *; }

# ── Gson (JSON serialization) ─────────────────────────────────────────────────
-keepattributes Signature
-keepattributes InnerClasses
-keep class sun.misc.Unsafe { *; }
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# ── In-App Purchase (Play Billing) ────────────────────────────────────────────
-keep class com.android.billingclient.** { *; }
-keep class com.android.vending.billing.** { *; }

# ── image_picker / FileProvider ───────────────────────────────────────────────
-keep class io.flutter.plugins.imagepicker.** { *; }
-keep class androidx.core.content.FileProvider { *; }

# ── photo_view ────────────────────────────────────────────────────────────────
-keep class com.github.piasy.biv.** { *; }

# ── share_plus ────────────────────────────────────────────────────────────────
-keep class dev.fluttercommunity.plus.share.** { *; }

# ── url_launcher ──────────────────────────────────────────────────────────────
-keep class io.flutter.plugins.urllauncher.** { *; }

# ── geolocator ────────────────────────────────────────────────────────────────
-keep class com.baseflow.geolocator.** { *; }

# ── geocoding ────────────────────────────────────────────────────────────────
-keep class com.baseflow.geocoding.** { *; }

# ── cached_network_image / Glide ─────────────────────────────────────────────
-keep public class * implements com.bumptech.glide.module.GlideModule
-keep class * extends com.bumptech.glide.module.AppGlideModule { <init>(...); }
-keep public enum com.bumptech.glide.load.ImageHeaderParser$** {
    **[] $VALUES;
    public *;
}

# ── Kotlin ────────────────────────────────────────────────────────────────────
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-keepclassmembers class **$WhenMappings {
    <fields>;
}
-keepclassmembers class kotlin.Lazy {
    <fields>;
}
-dontwarn kotlin.**

# ── Kotlin Coroutines ─────────────────────────────────────────────────────────
-keepclassmembernames class kotlinx.** {
    volatile <fields>;
}

# ── AndroidX ─────────────────────────────────────────────────────────────────
-keep class androidx.** { *; }
-keep interface androidx.** { *; }
-dontwarn androidx.**

# ── Serializable / Parcelable ─────────────────────────────────────────────────
-keepclassmembers class * implements java.io.Serializable {
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}

# ── Reflection / Annotations ──────────────────────────────────────────────────
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# ── Suppress noisy warnings from transitive deps ──────────────────────────────
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-dontwarn org.checkerframework.**
-dontwarn com.google.j2objc.annotations.**
-dontwarn afu.org.checkerframework.**
