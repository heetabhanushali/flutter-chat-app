import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EncryptionService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // ── Algorithms ──────────────────────────────────────────────
  final _keyExchange = X25519();
  final _aesGcm = AesGcm.with256bits();
  final _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 100000,
    bits: 256,
  );
  final _hkdf = Hkdf(hmac: Hmac.sha256() , outputLength: 32);

  // ── Caches (static → survive across instances) ─────────────
  static final Map<String, SecretKey> _sharedKeyCache = {};
  static final Map<String, String> _publicKeyCache = {};

  // ── Secure-storage keys ────────────────────────────────────
  static const _kPrivateKey = 'e2ee_private_key';
  static const _kPublicKey = 'e2ee_public_key';

  // ── AES-GCM constants ─────────────────────────────────────
  static const _nonceLen = 12;
  static const _macLen = 16;

  // ============================================================
  // KEY GENERATION (Registration)
  // ============================================================

  /// Generate X25519 key pair, encrypt the private key with the
  /// user's password, upload to Supabase, and store locally.
  Future<void> generateAndStoreKeys({
    required String userId,
    required String password,
  }) async {
    // 1. Generate key pair
    final keyPair = await _keyExchange.newKeyPair();
    final extracted = await keyPair.extract();

    final privateKeyB64 = base64Encode(extracted.bytes);
    final publicKeyB64 = base64Encode(extracted.publicKey.bytes);

    // 2. Encrypt private key with password
    final salt = _secureRandomBytes(16);
    final saltB64 = base64Encode(salt);
    final passwordKey = await _deriveKeyFromPassword(password, salt);
    final encryptedPrivateKey = await _encryptRaw(
      plainText: privateKeyB64,
      key: passwordKey,
    );

    // 3. Upload to Supabase
    await _supabase.from('users').update({
      'public_key': publicKeyB64,
      'encrypted_private_key': encryptedPrivateKey,
      'key_salt': saltB64,
    }).eq('id', userId);

    // 4. Store locally
    await _secureStorage.write(key: _kPrivateKey, value: privateKeyB64);
    await _secureStorage.write(key: _kPublicKey, value: publicKeyB64);
  }

  // ============================================================
  // KEY RECOVERY (New device login)
  // ============================================================

  /// Download the encrypted private key from the server,
  /// decrypt it with the user's password, and store locally.
  /// Returns `true` on success.
  Future<bool> recoverKeysFromServer({
    required String userId,
    required String password,
  }) async {
    try {
      final row = await _supabase
          .from('users')
          .select('public_key, encrypted_private_key, key_salt')
          .eq('id', userId)
          .single();

      final publicKeyB64 = row['public_key'] as String?;
      final encPrivKey = row['encrypted_private_key'] as String?;
      final saltB64 = row['key_salt'] as String?;

      if (publicKeyB64 == null || encPrivKey == null || saltB64 == null) {
        return false; // No keys on server yet
      }

      final salt = base64Decode(saltB64);
      final passwordKey = await _deriveKeyFromPassword(password, salt);
      final privateKeyB64 = await _decryptRaw(
        encryptedText: encPrivKey,
        key: passwordKey,
      );

      await _secureStorage.write(key: _kPrivateKey, value: privateKeyB64);
      await _secureStorage.write(key: _kPublicKey, value: publicKeyB64);

      return true;
    } catch (e) {
      print('Key recovery failed: $e');
      return false;
    }
  }

  // ============================================================
  // KEY STATUS CHECKS
  // ============================================================

  /// Does this device already have the private key?
  Future<bool> hasLocalKeys() async {
    final pk = await _secureStorage.read(key: _kPrivateKey);
    return pk != null && pk.isNotEmpty;
  }

  /// Does the server have keys for this user?
  Future<bool> hasServerKeys(String userId) async {
    try {
      final row = await _supabase
          .from('users')
          .select('public_key')
          .eq('id', userId)
          .single();
      return row['public_key'] != null;
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // PASSWORD CHANGE
  // ============================================================

  /// Re-encrypt the private key with a new password.
  /// Call this when the user changes their password.
  Future<void> reEncryptPrivateKey({
    required String userId,
    required String newPassword,
  }) async {
    final privateKeyB64 = await _secureStorage.read(key: _kPrivateKey);
    if (privateKeyB64 == null) {
      throw Exception('No local private key to re-encrypt');
    }

    final newSalt = _secureRandomBytes(16);
    final newSaltB64 = base64Encode(newSalt);
    final newKey = await _deriveKeyFromPassword(newPassword, newSalt);
    final newEncrypted = await _encryptRaw(
      plainText: privateKeyB64,
      key: newKey,
    );

    await _supabase.from('users').update({
      'encrypted_private_key': newEncrypted,
      'key_salt': newSaltB64,
    }).eq('id', userId);
  }

  /// When a password is **reset** (old password unknown),
  /// old messages become unreadable. Generate fresh keys.
  Future<void> regenerateKeys({
    required String userId,
    required String newPassword,
  }) async {
    _sharedKeyCache.clear();
    _publicKeyCache.clear();
    await generateAndStoreKeys(userId: userId, password: newPassword);
  }

  // ============================================================
  // LOGOUT — clear local keys
  // ============================================================

  Future<void> clearLocalKeys() async {
    await _secureStorage.delete(key: _kPrivateKey);
    await _secureStorage.delete(key: _kPublicKey);
    _sharedKeyCache.clear();
    _publicKeyCache.clear();
  }

  // ============================================================
  // MESSAGE ENCRYPTION / DECRYPTION
  // ============================================================

  /// Encrypt a plain-text message for the conversation partner.
  Future<String> encryptMessage({
    required String plainText,
    required String otherUserId,
  }) async {
    final sharedKey = await _deriveSharedKey(otherUserId);

    final box = await _aesGcm.encrypt(
      utf8.encode(plainText),
      secretKey: sharedKey,
    );

    final blob = Uint8List.fromList([
      ...box.nonce,       // 12 bytes
      ...box.cipherText,  // variable
      ...box.mac.bytes,   // 16 bytes
    ]);

    return base64Encode(blob);
  }

  /// Decrypt an encrypted message from the conversation partner.
  /// Falls back to returning [encryptedText] as-is if decryption
  /// fails (e.g. legacy unencrypted message).
  Future<String> decryptMessage({
    required String encryptedText,
    required String otherUserId,
  }) async {
    try {
      final blob = base64Decode(encryptedText);

      // Too short to be a valid encrypted payload
      if (blob.length < _nonceLen + _macLen + 1) {
        return encryptedText;
      }

      final sharedKey = await _deriveSharedKey(otherUserId);

      final box = SecretBox(
        blob.sublist(_nonceLen, blob.length - _macLen),
        nonce: blob.sublist(0, _nonceLen),
        mac: Mac(blob.sublist(blob.length - _macLen)),
      );

      final clear = await _aesGcm.decrypt(box, secretKey: sharedKey);
      return utf8.decode(clear);
    } catch (_) {
      // Not encrypted or decryption failed → return raw text
      return encryptedText;
    }
  }

  // ============================================================
  // PUBLIC KEY FETCHING
  // ============================================================

  /// Get another user's public key (cached after first fetch).
  Future<String?> getRecipientPublicKey(String userId) async {
    if (_publicKeyCache.containsKey(userId)) {
      return _publicKeyCache[userId];
    }

    try {
      final row = await _supabase
          .from('users')
          .select('public_key')
          .eq('id', userId)
          .single();

      final key = row['public_key'] as String?;
      if (key != null) _publicKeyCache[userId] = key;
      return key;
    } catch (e) {
      print('Error fetching public key: $e');
      return null;
    }
  }

  // ============================================================
  // PRIVATE — Shared-key derivation (X25519 → HKDF → AES key)
  // ============================================================

  Future<SecretKey> _deriveSharedKey(String otherUserId) async {
    if (_sharedKeyCache.containsKey(otherUserId)) {
      return _sharedKeyCache[otherUserId]!;
    }

    // My keys from local storage
    final myPrivB64 = await _secureStorage.read(key: _kPrivateKey);
    final myPubB64 = await _secureStorage.read(key: _kPublicKey);
    if (myPrivB64 == null || myPubB64 == null) {
      throw Exception('Local encryption keys not found. Please re-login.');
    }

    // Recipient's public key from server
    final otherPubB64 = await getRecipientPublicKey(otherUserId);
    if (otherPubB64 == null) {
      throw Exception('Recipient has no encryption key.');
    }

    // Reconstruct key objects
    final myKeyPair = SimpleKeyPairData(
      base64Decode(myPrivB64),
      publicKey: SimplePublicKey(
        base64Decode(myPubB64),
        type: KeyPairType.x25519,
      ),
      type: KeyPairType.x25519,
    );

    final otherPub = SimplePublicKey(
      base64Decode(otherPubB64),
      type: KeyPairType.x25519,
    );

    // X25519 → raw shared secret
    final sharedSecret = await _keyExchange.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: otherPub,
    );

    // HKDF → deterministic AES-256 key
    final derived = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: <int>[],                        // empty salt (shared secret is already random)
      info: utf8.encode('e2ee-chat-v1'),     // domain separation
    );

    _sharedKeyCache[otherUserId] = derived;
    return derived;
  }

  // ============================================================
  // PRIVATE — Password-based key derivation (PBKDF2)
  // ============================================================

  Future<SecretKey> _deriveKeyFromPassword(
    String password,
    List<int> salt,
  ) async {
    return _pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  // ============================================================
  // PRIVATE — Low-level encrypt / decrypt (for private-key backup)
  // ============================================================

  Future<String> _encryptRaw({
    required String plainText,
    required SecretKey key,
  }) async {
    final box = await _aesGcm.encrypt(
      utf8.encode(plainText),
      secretKey: key,
    );

    final blob = Uint8List.fromList([
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);

    return base64Encode(blob);
  }

  Future<String> _decryptRaw({
    required String encryptedText,
    required SecretKey key,
  }) async {
    final blob = base64Decode(encryptedText);

    final box = SecretBox(
      blob.sublist(_nonceLen, blob.length - _macLen),
      nonce: blob.sublist(0, _nonceLen),
      mac: Mac(blob.sublist(blob.length - _macLen)),
    );

    final clear = await _aesGcm.decrypt(box, secretKey: key);
    return utf8.decode(clear);
  }

  // ============================================================
  // PRIVATE — Secure random bytes
  // ============================================================

  List<int> _secureRandomBytes(int length) {
    final rng = Random.secure();
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }
}