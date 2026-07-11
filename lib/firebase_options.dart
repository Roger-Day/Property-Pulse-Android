import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase options aligned with [GoogleService-Info.plist] (iOS) and
/// [android/app/google-services.json] (Android).
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      default:
        return android;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCBRJSP_rJkZWyKTX6hT1gtbdlOLybp8vU',
    appId: '1:1024386037978:android:1a797e9d8436f1c14c4de3',
    messagingSenderId: '1024386037978',
    projectId: 'property-pulse-7676f',
    authDomain: 'property-pulse-7676f.firebaseapp.com',
    storageBucket: 'property-pulse-7676f.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCBRJSP_rJkZWyKTX6hT1gtbdlOLybp8vU',
    appId: '1:1024386037978:android:1a797e9d8436f1c14c4de3',
    messagingSenderId: '1024386037978',
    projectId: 'property-pulse-7676f',
    storageBucket: 'property-pulse-7676f.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCyeFMQN0cashFuhmEm2MGisWyzk9bg_Kk',
    appId: '1:1024386037978:ios:712b60380823915f4c4de3',
    messagingSenderId: '1024386037978',
    projectId: 'property-pulse-7676f',
    storageBucket: 'property-pulse-7676f.firebasestorage.app',
    iosBundleId: 'com.rogerday.propertypulse.app',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyCyeFMQN0cashFuhmEm2MGisWyzk9bg_Kk',
    appId: '1:1024386037978:ios:712b60380823915f4c4de3',
    messagingSenderId: '1024386037978',
    projectId: 'property-pulse-7676f',
    storageBucket: 'property-pulse-7676f.firebasestorage.app',
    iosBundleId: 'com.rogerday.propertypulse.app',
  );
}
