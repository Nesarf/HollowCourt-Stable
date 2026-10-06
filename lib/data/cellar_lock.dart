import 'dart:io';

/// Raised when a cellar is already open in another process.
///
/// **A separate exception rather than a false return**, because the two ways opening can fail are different things:
/// a file that cannot be read, and **a file somebody else is writing right now**. A caller that has to tell them
/// apart can only do so if they arrive as different types.
final class CellarInUse implements Exception {
  const CellarInUse(this.path, this.holder);

  /// The log that is already open elsewhere.
  final String path;

  /// The process id that holds it, when the owner file could be read.
  final int? holder;

  @override
  String toString() => holder == null
      ? 'the cellar at $path is open in another copy of the application; close that one first, because two '
          'writers would corrupt it'
      : 'the cellar at $path is held by process $holder; close that copy first, because two writers would '
          'corrupt it';
}

/// **An exclusive claim on one cellar, held across processes.**
///
/// ## What this is for
///
/// `EventLog` serialises its own writes through `_writeTail`, and that is correct **within one instance**. It is not
/// a claim about the file. A desktop reader can start the application twice -- two icons, a launcher and a shortcut,
/// a double-click that felt like it did nothing -- and two processes then hold one cellar with no knowledge of each
/// other.
///
/// **What follows is not a lost update but a corrupt file.** Every append is a line, and the reader *rewrites* the
/// log when it discards a torn tail: two writers mean one process appending while the other truncates and rewrites,
/// and the surviving file is neither version's. **An append-only log is worth having because it can be trusted line
/// by line**, so this is the one failure the design cannot absorb.
///
/// ## The same process is allowed back in, and that is a measurement
///
/// **Dart's `lock` is per handle, not per process.** Probed on 2026-10-01: a second handle in the *same* process is
/// refused with `PathAccessException ... errno = 33`, exactly as a foreign process would be. A lock taken naively
/// therefore refuses the application's own `reload` and every test that opens a cellar twice -- **64 tests failed on
/// the first attempt**, which is how this was found.
///
/// **The two cases are told apart by process id.** The pid is written beside the lock *before* it is taken, so a
/// failed acquire can read it back: **our own pid means this process already holds the cellar**, which is
/// legitimate; **anybody else's means another process has it**, which is what this class is for. A lock that refused
/// both would be one the application could not use.
///
/// ## One exclusive lock, not a shared lock plus a write lock
///
/// A reader-only mode would be more polite -- two copies could browse one cellar -- and it is deliberately not
/// built. **The reader and the writer are the same object here**: opening a log folds it, and a fold is followed by
/// writes as soon as the reader touches anything. A shared mode would be a promise this layer cannot keep, and a
/// lock meaning "read-only" while the process goes on to write is worse than none, because a second instance would
/// trust it.
///
/// ## A separate file rather than the log itself
///
/// The log is opened, closed and rewritten during recovery, so a lock held on it would be dropped whenever the store
/// reopens it. **A sibling `<log>.lock` is opened once and stays open**, which is also what makes the lock's
/// lifetime exactly the log's -- and it leaves the log's bytes untouched, which matters because the log is a sync
/// format and a `.courtpack` is a copy of it.
final class CellarLock {
  CellarLock._(this._handle, this.path);

  /// **A claim this process already holds.** Nothing to lock and nothing to release: the handle that owns the lock
  /// is still open somewhere in this process, and closing this one would drop a claim it does not hold.
  CellarLock.reentrant(this.path) : _handle = null;

  /// The open handle, or null when this is a [CellarLock.reentrant] view of a claim taken earlier.
  final RandomAccessFile? _handle;

  /// The lock file this claim is held on.
  final String path;

  /// The sibling that names the process which is trying to hold this cellar.
  ///
  /// **Written before the lock is taken, not after**, because its one job is to answer *"was that refusal mine?"*
  /// and a file written after a successful lock cannot answer anything about a failed one. It is therefore a record
  /// of **who is trying**; the lock remains the only source of truth about who succeeded, which is why a missing or
  /// unreadable owner file degrades to refusing rather than to allowing.
  static const ownerSuffix = '.owner';

  /// Takes the claim, or throws [CellarInUse] when another process holds it.
  ///
  /// [logPath] is the log itself; the lock lives beside it as `<logPath>.lock`.
  static Future<CellarLock> acquire(String logPath) async {
    final owner = File('$logPath.lock$ownerSuffix');
    // Best-effort: a cellar whose directory is not writable will fail to open for its own reasons, and this is not
    // one of them.
    try {
      await owner.writeAsString('$pid${'\n'}');
    } on FileSystemException {
      // Ignored on purpose; see above.
    }

    final handle = await File('$logPath.lock').open(mode: FileMode.write);
    try {
      // **`exclusive` and not `shared`.** The lock is a claim to write, because any process that opens a cellar is
      // one keystroke from writing to it.
      await handle.lock(FileLock.exclusive);
    } on FileSystemException {
      // Closing first matters: a handle that failed to lock is still a handle the operating system counts.
      await handle.close();
      final holder = await _holderPid(owner);
      if (holder == pid) return CellarLock.reentrant('$logPath.lock');
      throw CellarInUse(logPath, holder);
    }
    return CellarLock._(handle, '$logPath.lock');
  }

  /// What the owner file says, or null when it is absent or not a number.
  static Future<int?> _holderPid(File owner) async {
    try {
      return int.tryParse((await owner.readAsString()).trim());
    } on FileSystemException {
      // No owner file means nobody recorded an attempt; refusing is the safe reading of that.
      return null;
    }
  }

  /// Gives the claim up.
  ///
  /// **For tests, and for an application closing its cellar on purpose.** Production holds the lock until the
  /// process ends, which is the behaviour that survives a crash, and the operating system does the dropping -- so a
  /// caller that never calls this is not leaking anything. What it *is* needed for is a test that opens a cellar and
  /// then removes its temporary directory: the lock file is still open, and the deletion fails with `errno = 32`,
  /// which names a directory rather than a lock.
  Future<void> release() async {
    final handle = _handle;
    // **A reentrant view releases nothing.** The claim belongs to the handle that took it, and this object never had
    // one -- closing here would drop a lock another part of this process still relies on.
    if (handle == null) return;
    try {
      await handle.unlock();
    } on FileSystemException {
      // Already gone, which is what a process that ended abruptly leaves behind.
    }
    await handle.close();
  }
}
