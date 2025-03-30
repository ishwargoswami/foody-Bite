import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_foodybite/models/user_model.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    clientId: '16247673730-n0b42cctdqti1adfgph33dinbh4mkkbk.apps.googleusercontent.com',
  );

  // Create user object based on FirebaseUser
  UserModel? _userFromFirebaseUser(User? user) {
    return user != null
        ? UserModel(
            uid: user.uid,
            email: user.email,
            name: user.displayName,
            photoUrl: user.photoURL,
          )
        : null;
  }

  // Auth change user stream
  Stream<UserModel?> get user {
    return _auth.authStateChanges().map(_userFromFirebaseUser);
  }

  // Sign in with email & password
  Future<UserModel?> signInWithEmailAndPassword(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
          email: email, password: password);
      User? user = result.user;
      
      // Save user session
      await _saveUserSession(true);
      
      return _userFromFirebaseUser(user);
    } catch (e) {
      print('Error in signInWithEmailAndPassword: ${e.toString()}');
      throw e;
    }
  }

  // Register with email & password
  Future<UserModel?> registerWithEmailAndPassword(
      String email, String password, String name) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      User? user = result.user;

      // Update the username
      await user?.updateDisplayName(name);
      
      // Create a new document for the user with uid
      await _firestore.collection('users').doc(user?.uid).set({
        'uid': user?.uid,
        'email': email,
        'name': name,
        'photoUrl': '',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Save user session
      await _saveUserSession(true);
      
      return _userFromFirebaseUser(user);
    } catch (e) {
      print('Error in registerWithEmailAndPassword: ${e.toString()}');
      throw e;
    }
  }

  // Sign in with Google
  Future<UserModel?> signInWithGoogle() async {
    try {
      // Handle web platform differently
      if (kIsWeb) {
        // Create a new provider
        GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('profile');
        
        // Sign in using a popup
        final UserCredential result = await _auth.signInWithPopup(googleProvider);
        final User? user = result.user;

        await _handleSignedInUser(user);
        return _userFromFirebaseUser(user);
      } else {
        // For Android/iOS flow
        // Show loading indicator or disable buttons before starting sign-in
        try {
          print("Starting Google Sign In process...");
          // Begin interactive sign-in process
          final GoogleSignInAccount? googleSignInAccount = await _googleSignIn.signIn();
          
          if (googleSignInAccount == null) {
            print("Google Sign In was canceled by user");
            throw Exception("Google Sign In was canceled by user");
          }
          
          print("Google Sign In success, getting credentials...");
          // Show loading indicator during authentication
          final GoogleSignInAuthentication googleSignInAuthentication =
              await googleSignInAccount.authentication;

          final AuthCredential credential = GoogleAuthProvider.credential(
            accessToken: googleSignInAuthentication.accessToken,
            idToken: googleSignInAuthentication.idToken,
          );

          try {
            print("Signing in to Firebase with Google credential...");
            final UserCredential result = await _auth.signInWithCredential(credential);
            final User? user = result.user;

            print("Firebase sign in successful, handling user data...");
            await _handleSignedInUser(user);
            return _userFromFirebaseUser(user);
          } catch (credentialError) {
            print('Credential error: $credentialError');
            throw Exception("Failed to sign in with Google. Please try again.");
          }
        } catch (error) {
          print('Google sign in error: $error');
          if (error.toString().contains('network_error')) {
            throw Exception("Network error. Check your connection.");
          } else if (error.toString().contains('canceled')) {
            throw Exception("Google Sign In was canceled.");
          } else {
            throw error;
          }
        }
      }
    } catch (e) {
      print('Error in signInWithGoogle: ${e.toString()}');
      throw e;
    }
  }

  // Helper method to handle signed in user
  Future<void> _handleSignedInUser(User? user) async {
    if (user != null) {
      // Check if the user already exists in Firestore
      DocumentSnapshot doc = await _firestore.collection('users').doc(user.uid).get();
      
      // If the user doesn't exist, create a new document
      if (!doc.exists) {
        await _firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'email': user.email,
          'name': user.displayName,
          'photoUrl': user.photoURL,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // Save user session
      await _saveUserSession(true);
    }
  }

  // Save user session
  Future<void> _saveUserSession(bool isLoggedIn) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', isLoggedIn);
  }

  // Check if user is logged in
  Future<bool> isUserLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isLoggedIn') ?? false;
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _auth.signOut();
      
      // Clear user session
      await _saveUserSession(false);
    } catch (e) {
      print(e.toString());
    }
  }

  // Password reset
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      print(e.toString());
      throw e;
    }
  }
} 