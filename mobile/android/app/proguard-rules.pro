# Flutter's own rules come from the Flutter Gradle plugin; these cover
# the native plugins we ship.

# flutter_reactive_ble (protobuf-based message layer)
-keep class com.google.protobuf.** { *; }
-keep class com.signify.hue.** { *; }

# mobile_scanner / ML Kit barcode
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.vision.** { *; }

# flutter_secure_storage uses Tink for EncryptedSharedPreferences
-keep class com.google.crypto.tink.** { *; }
