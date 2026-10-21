import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// **What the reader told the application about the model it may talk to.**
///
/// The address and the model name are ordinary settings. The key is not: it is a credential, and it is kept encrypted
/// beside them rather than in the same file -- see [ChatKeyStore] for what that encryption does and does not buy.
class ChatSettings {
  const ChatSettings({this.baseUrl = '', this.model = '', this.apiKey = ''});

  factory ChatSettings.fromJson(Map<String, Object?> json) => ChatSettings(
        baseUrl: '${json['baseUrl'] ?? ''}',
        model: '${json['model'] ?? ''}',
        apiKey: '${json['apiKey'] ?? ''}',
      );

  /// Empty means "not configured", which is the state this ships in.
  final String baseUrl;
  final String model;
  final String apiKey;

  bool get isConfigured => baseUrl.trim().isNotEmpty && model.trim().isNotEmpty && apiKey.trim().isNotEmpty;

  ChatSettings copyWith({String? baseUrl, String? model, String? apiKey}) => ChatSettings(
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        apiKey: apiKey ?? this.apiKey,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'baseUrl': baseUrl,
        'model': model,
        'apiKey': apiKey,
      };
}

/// **The credential, encrypted with a key that lives in the same directory.**
///
/// Said plainly because the opposite claim would be dishonest: this stops a reader of the settings file from reading a
/// key by accident -- a `chat.json` opened in a text editor, a backup copied off the phone -- and it does not stop
/// anyone who has the device. A key that unlocks a file sitting beside it is obfuscation with a lock, not a vault.
///
/// The alternative considered and rejected was asking for the key every launch: strictly more secure, and it turns a
/// conversation into a password prompt ten times a day. The reader decides whether to keep a key on the device at all,
/// which is the decision that actually matters, and it is theirs to make in the settings.
class ChatKeyStore {
  ChatKeyStore(this.directory);

  final Directory directory;

  static const String _keyFile = 'chat.master';
  static const String _settingsFile = 'chat.json';

  File get _masterFile => File('${directory.path}${Platform.pathSeparator}$_keyFile');
  File get _settingsFileHandle => File('${directory.path}${Platform.pathSeparator}$_settingsFile');

  static final AesGcm _cipher = AesGcm.with256bits();

  /// Read, or a not-configured default when nothing has been written.
  Future<ChatSettings> read() async {
    final file = _settingsFileHandle;
    if (!await file.exists()) return const ChatSettings();
    final Map<String, Object?> json;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) return const ChatSettings();
      json = decoded;
    } on FormatException {
      // A file somebody edited into nonsense is the same as no file: better an empty form than a crash on launch.
      return const ChatSettings();
    }
    final sealed = json['key'];
    final plain = ChatSettings(
      baseUrl: '${json['baseUrl'] ?? ''}',
      model: '${json['model'] ?? ''}',
    );
    if (sealed is! Map<String, Object?>) return plain;
    final apiKey = await _open(sealed);
    return plain.copyWith(apiKey: apiKey ?? '');
  }

  /// Writes the whole thing. The key goes in encrypted; the address and the model do not, because they are not secrets
  /// and a settings file that cannot be read by eye is a settings file nobody can fix.
  Future<void> write(ChatSettings settings) async {
    await directory.create(recursive: true);
    final master = await _masterKey();
    Object? sealed;
    if (settings.apiKey.trim().isNotEmpty) {
      sealed = await _seal(master, settings.apiKey);
    }
    final json = <String, Object?>{
      'baseUrl': settings.baseUrl,
      'model': settings.model,
      'key': ?sealed,
    };
    await _settingsFileHandle.writeAsString(const JsonEncoder.withIndent('  ').convert(json), flush: true);
  }

  Future<SecretKey> _masterKey() async {
    final file = _masterFile;
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      if (bytes.length == 32) return SecretKey(bytes);
    }
    final fresh = SecretKeyData.random(length: 32);
    await file.writeAsBytes(fresh.bytes, flush: true);
    return fresh;
  }

  Future<Map<String, Object?>> _seal(SecretKey master, String plain) async {
    final nonce = _cipher.newNonce();
    final box = await _cipher.encrypt(utf8.encode(plain), secretKey: master, nonce: nonce);
    return <String, Object?>{
      'nonce': base64Encode(nonce),
      'bytes': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
  }

  /// Null when the box does not open: a master key regenerated after the settings were written, or a file somebody
  /// edited. The reader then sees an empty key field and types it again, which is the right recovery.
  Future<String?> _open(Map<String, Object?> sealed) async {
    try {
      final nonce = base64Decode('${sealed['nonce']}');
      final cipherText = base64Decode('${sealed['bytes']}');
      final mac = Mac(base64Decode('${sealed['mac']}'));
      final master = await _masterKey();
      final clear = await _cipher.decrypt(
        SecretBox(Uint8List.fromList(cipherText), nonce: Uint8List.fromList(nonce), mac: mac),
        secretKey: master,
      );
      return utf8.decode(clear);
    } on Exception {
      return null;
    }
  }
}
