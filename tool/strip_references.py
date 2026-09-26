"""Remove references to other people's projects from everything that would be published.

Owner's rule, 2026-09-25: no trace of a reference to anybody else's project may be pushed to the public
repository.

Run from the repository root. The replacements are descriptive rather than vague -- "a rhythm game" says what was
learned without saying whose it is -- and they are word-bounded, because a **coupe is a glass** and the vocabulary
of drink-making is not a citation.
"""
import io
import os
import re

RULES = [
    (re.compile(r'a mobile game|a mobile game'), 'a mobile game'),
    (re.compile(r'\bBlue Archive\b'), 'a mobile game'),
    (re.compile(r'\bArcaea\b'), 'a rhythm game'),
    (re.compile(r'a rhythm game'), 'a rhythm game'),
    (re.compile(r'\bPotion Craft\b'), 'a crafting game'),
    (re.compile(r'\bVRChat\b'), 'a social platform'),
    (re.compile(r'\bZenless\b'), 'a mobile game'),
    (re.compile(r'\bInscryption\b'), 'a card game'),
    (re.compile(r'\bBuckshot Roulette\b'), 'a card game'),
    (re.compile(r'\bHollow Knight\b'), 'an action game'),
    (re.compile(r'\bMixel\b'), 'another source'),
    (re.compile(r'\bCoupe\b'), 'one source'),
    (re.compile(r'\bMonotype\b'), 'an earlier face'),
]

# A grammar pass, because a mechanical rewrite of prose needs to be read afterwards and these are the breaks it
# made last time.
FIXES = [
    (re.compile(r'\bthe a (rhythm game|mobile game|crafting game|social platform)\b'), r'the \1'),
    (re.compile(r'\ba (rhythm game|mobile game|crafting game) study\b'), r'a study of \1'),
    (re.compile(r"\b(one|another) source's\b"), lambda m: "one source's" if m.group(1) == 'one' else "another source's"),
]

SKIP_PREFIXES = ('tools/', 'an earlier survey', 'audio/wwise/', 'build/', '.git/', '.dart_tool/')
# **The files that define the rule, not the files that break it.** `principles_test.dart` lists the product
# names in order to forbid them, `seed_vocabulary_test.dart` uses `'Coupe'` as a *glass* in a vocabulary test, and
# this file is its own rule table. A sweep that rewrites these is a sweep that deletes the thing it is enforcing
# -- which is what the first run of this tool did, three times, and why the list exists.
SKIP_EXACT = {
    'tool/sanitise_public.py', 'tool/push_public.sh', 'tool/publish_public.sh',
    'tool/strip_references.py',
    'test/data/principles_test.dart',
    'test/domain/model/seed_vocabulary_test.dart',
    'test/ui/private_name_test.dart',
}
TEXT = ('.md', '.json', '.yaml', '.yml', '.dart', '.sh', '.py', '.txt')


def main() -> int:
    changed = []
    for base, dirs, files in os.walk('.'):
        dirs[:] = [d for d in dirs if not (os.path.join(base, d).replace(os.sep, '/').lstrip('./') + '/').startswith(SKIP_PREFIXES)]
        for name in files:
            path = os.path.join(base, name).replace(os.sep, '/')
            if path.startswith('./'):
                path = path[2:]
            if path in SKIP_EXACT or path.startswith(SKIP_PREFIXES):
                continue
            if not path.endswith(TEXT):
                continue
            try:
                text = io.open(path, encoding='utf-8').read()
            except (OSError, UnicodeDecodeError):
                continue
            out = text
            for pattern, replacement in RULES:
                out = pattern.sub(replacement, out)
            for pattern, replacement in FIXES:
                out = pattern.sub(replacement, out)
            if out != text:
                io.open(path, 'w', encoding='utf-8', newline='\n').write(out)
                changed.append(path)
    for path in changed:
        print('swept:', path)
    print('files swept:', len(changed))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
