"""One-off: route every `Copy.X.primary.text` through the reader's language and voice.

    python E:\\DaShaoHuo\\cache\\tmp\\fix_bypasses.py --dry
    python E:\\DaShaoHuo\\cache\\tmp\\fix_bypasses.py

**Why a script rather than twenty-eight edits.** The pattern is one shape repeated: the authored Chinese
sentence is read directly, bypassing `textFor` and therefore both the locale and the voice. The replacement
is the same shape too -- `ref.copy(Copy.X)` -- so the change is a substitution, and a substitution that is
then checked by the analyzer rather than by me reading twenty-eight diffs.

**It refuses to touch `copy_resolution.dart`.** That file explains this bug and quotes the pattern in its
own documentation; a blind substitution would rewrite the explanation into the very code it warns about.
That is not hypothetical -- the dry run did exactly that, which is why the file is on the skip list.
"""
import io
import os
import re
import sys

ROOT = r'E:\hollow-court'
PATTERN = re.compile(r'Copy\.([A-Za-z]+)\.primary\.text')
IMPORT_LINE = "import 'l10n/copy_resolution.dart';\n"
SKIP = {'copy_resolution.dart'}

dry = '--dry' in sys.argv


def main() -> int:
    changed_files = 0
    changed_sites = 0
    for base, _dirs, files in os.walk(os.path.join(ROOT, 'lib')):
        for name in sorted(files):
            if not name.endswith('.dart') or name in SKIP:
                continue
            path = os.path.join(base, name)
            source = io.open(path, encoding='utf-8').read()
            hits = PATTERN.findall(source)
            if not hits:
                continue
            new = PATTERN.sub(r'ref.copy(Copy.\1)', source)
            needs_import = 'copy_resolution.dart' not in new
            if needs_import:
                # the import goes with the other l10n imports, or after the last import if there are none
                lines = new.split('\n')
                anchor = None
                for index, line in enumerate(lines):
                    if line.startswith("import '") and 'l10n/' in line:
                        anchor = index
                        break
                if anchor is None:
                    for index, line in enumerate(lines):
                        if line.startswith("import '"):
                            anchor = index
                if anchor is not None:
                    # **The path is a question about one directory, not arithmetic on a depth.** A file directly in
                    # `lib/ui/` imports `l10n/...`; a file in a subdirectory of it imports `../l10n/...`. The first
                    # version counted path components and was off by one, so six files were given a URI that did not
                    # resolve -- the analyzer said `uri_does_not_exist` for each of them, which is at least a loud way
                    # to be wrong.
                    ui = os.path.join(ROOT, 'lib', 'ui')
                    depth = '' if os.path.normpath(base) == os.path.normpath(ui) else '../'
                    lines.insert(anchor, "import '%sl10n/copy_resolution.dart';" % depth)
                    new = '\n'.join(lines)
                else:
                    print('  no import anchor in %s -- skipping' % path)
                    continue
            print('  %-52s %d site(s)%s' % (os.path.relpath(path, ROOT), len(hits),
                                            '  +import' if needs_import else ''))
            changed_files += 1
            changed_sites += len(hits)
            if not dry:
                io.open(path, 'w', encoding='utf-8', newline='\n').write(new)
    print('  %d file(s), %d site(s)%s' % (changed_files, changed_sites, ' (dry run)' if dry else ''))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
