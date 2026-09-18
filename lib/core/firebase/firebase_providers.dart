import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_bootstrap.dart';

final firebaseReadyProvider = Provider<bool>((ref) => FirebaseBootstrap.isReady);

final firebaseAuthProvider = Provider<FirebaseAuth?>((ref) {
  if (!FirebaseBootstrap.isReady) return null;
  return FirebaseAuth.instance;
});

final firestoreProvider = Provider<FirebaseFirestore?>((ref) {
  if (!FirebaseBootstrap.isReady) return null;
  return FirebaseFirestore.instance;
});

final analyticsProvider = Provider<FirebaseAnalytics?>((ref) {
  if (!FirebaseBootstrap.isReady) return null;
  return FirebaseAnalytics.instance;
});

final authStateChangesProvider = StreamProvider<User?>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  if (auth == null) {
    return const Stream<User?>.empty();
  }
  return auth.authStateChanges();
});
