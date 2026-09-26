/// What this device is called, and which of its two names it shows to the network.
///
/// **Two names, because they answer different questions.** A device has a name its operating system gave
/// it -- `NesarfDX`, a phone, a laptop -- and a cellar has a name its owner gave it. The first says *which
/// machine*, the second says *whose cellar*, and a person sharing a cellar may reasonably want either one
/// in front of a stranger. The owner asked for both, and for the choice to be theirs:
///
/// > 在设置一栏里，里面可以给自己的空庭命名，然后对外同步的时候可以选择"同步时使用的名义"，
/// > 即设备名称和空庭名称二选一。
///
/// **The choice is a presentation and not an identity.** Whichever name is shown, the key fingerprint
/// still travels beside it and is still what recognises a device (`DeviceRoster`), so switching names
/// never makes one device look like another -- and a stranger copying a familiar name gains nothing,
/// because the fingerprint is not theirs to copy. The name is a label; the fingerprint is the identity.
library;

/// Which of the two names is presented to other devices.
enum NameChoice {
  /// The machine's name: `NesarfDX`.
  device,

  /// The cellar's name: what the owner called their 空庭.
  cellar;

  static NameChoice byName(String? name) => switch (name) {
    'cellar' => NameChoice.cellar,
    // Anything unrecognised -- including a value written by a later version -- means the device name,
    // because that is the name a device is guaranteed to have.
    _ => NameChoice.device,
  };

  String get wire => name;
}

/// This device's names, and which one it shows.
final class SyncNames {
  const SyncNames({
    required this.deviceName,
    this.cellarName = '',
    this.shows = NameChoice.device,
  });

  /// **A device always has a name, even when the machine will not say one.**
  ///
  /// `Platform.localHostname` is the honest source and the obvious default, but it is not reliably
  /// useful: on Android it answers `localhost`, which would put every phone in the world in the list as
  /// the same device. A name that identifies nobody is worse than a generic one, because it looks like an
  /// answer -- so the fallback names the *platform* rather than pretending to know the machine.
  factory SyncNames.defaultsFor(String hostname, {required bool isAndroid}) {
    final trimmed = hostname.trim();
    final useless = trimmed.isEmpty ||
        trimmed.toLowerCase() == 'localhost' ||
        trimmed.toLowerCase() == 'localhost.localdomain';
    if (!useless) return SyncNames(deviceName: trimmed);
    return SyncNames(deviceName: isAndroid ? 'Android 设备' : '这台设备');
  }

  /// What the operating system calls this machine, or a platform name when it will not say.
  final String deviceName;

  /// What the owner called their cellar. **Empty until they name it**, which is a real state rather than
  /// a missing value: an unnamed cellar presents its device name, and a settings screen says so.
  final String cellarName;

  final NameChoice shows;

  /// The name other devices see.
  ///
  /// **A name that does not exist cannot be presented.** Choosing the cellar name while the cellar has
  /// none falls back to the device name, so the announcement always carries something a reader can act
  /// on; the alternative -- an empty name on the wire -- would put a blank row in somebody else's list.
  String get presented =>
      shows == NameChoice.cellar && cellarName.trim().isNotEmpty
          ? cellarName.trim()
          : deviceName.trim();

  /// True when the owner asked for the cellar name and has not given one yet, which is what a settings
  /// screen has to say out loud rather than silently ignoring.
  bool get wantsAnUnnamedCellar =>
      shows == NameChoice.cellar && cellarName.trim().isEmpty;

  SyncNames withDeviceName(String name) =>
      SyncNames(deviceName: name, cellarName: cellarName, shows: shows);

  SyncNames withCellarName(String name) =>
      SyncNames(deviceName: deviceName, cellarName: name, shows: shows);

  SyncNames withChoice(NameChoice choice) =>
      SyncNames(deviceName: deviceName, cellarName: cellarName, shows: choice);

  Map<String, Object?> toJson() => {
    'deviceName': deviceName,
    'cellarName': cellarName,
    'shows': shows.wire,
  };

  /// Reads what was stored, falling back per field rather than wholesale.
  ///
  /// A settings file that is missing a field is a file written by an older version, and the right answer
  /// is to keep what is there and default the rest -- refusing the whole file would throw away a name the
  /// owner chose because of a field they never set.
  factory SyncNames.fromJson(Map<String, Object?> json, {required String fallbackDeviceName}) {
    final device = json['deviceName'];
    final cellar = json['cellarName'];
    return SyncNames(
      deviceName: device is String && device.trim().isNotEmpty
          ? device.trim()
          : fallbackDeviceName,
      cellarName: cellar is String ? cellar.trim() : '',
      shows: NameChoice.byName(json['shows'] is String ? json['shows']! as String : null),
    );
  }
}
