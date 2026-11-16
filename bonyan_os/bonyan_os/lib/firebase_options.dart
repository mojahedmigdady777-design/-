// lib/firebase_options.dart
//
// ⚠️ هذا ملف مؤقت للتطوير فقط.
// استبدله بالملف الحقيقي الناتج عن:
//   flutterfire configure
//
// التثبيت: dart pub global activate flutterfire_cli
// ثم: flutterfire configure --project=your-firebase-project-id

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions not configured for: '
          '$defaultTargetPlatform — run flutterfire configure',
        );
    }
  }

  // ── استبدل هذه القيم بقيمك الحقيقية من Firebase Console ──────────────────
  static const FirebaseOptions android = FirebaseOptions(
    apiKey:            'YOUR_ANDROID_API_KEY',
    appId:             'YOUR_ANDROID_APP_ID',
    messagingSenderId: 'YOUR_SENDER_ID',
    projectId:         'bonyan-os',
    storageBucket:     'bonyan-os.appspot.com',
    databaseURL:       'https://bonyan-os-default-rtdb.firebaseio.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey:            'YOUR_IOS_API_KEY',
    appId:             'YOUR_IOS_APP_ID',
    messagingSenderId: 'YOUR_SENDER_ID',
    projectId:         'bonyan-os',
    storageBucket:     'bonyan-os.appspot.com',
    databaseURL:       'https://bonyan-os-default-rtdb.firebaseio.com',
    iosBundleId:       'sa.bonyan.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey:            'YOUR_WEB_API_KEY',
    appId:             'YOUR_WEB_APP_ID',
    messagingSenderId: 'YOUR_SENDER_ID',
    projectId:         'bonyan-os',
    storageBucket:     'bonyan-os.appspot.com',
    authDomain:        'bonyan-os.firebaseapp.com',
    databaseURL:       'https://bonyan-os-default-rtdb.firebaseio.com',
  );
}
