import 'package:hollow_court/domain/overlay/overlay_key.dart';
import 'package:test/test.dart';

/// The key is where section 8's promise is kept or broken.
///
/// The seed is replaced wholesale on update and the overlay never is, so a key
/// derived from the seed's *contents* -- an index, a position, a display name --
/// loses the user's data on the one occasion the layer exists to survive. These
/// tests are about the two things that make the key survive: it is built from an
/// id section 4.4 promised not to renumber, and it can be validated, because a
/// user never mints one.
void main() {
  group('OverlayKey', () {
    test('packs to a form that parses back to itself', () {
      for (final packed in [
        'recipe:dry_manhattan17517.note',
        'ingredient:gin.alias',
        'copy:stockEmptyHint.en',
        'ingredient:gin.extras.glass',
      ]) {
        expect(OverlayKey.parse(packed).toString(), packed);
      }
    });

    test('a round trip through the packed form changes nothing', () {
      final key = OverlayKey.recipe('dry_manhattan17517');
      expect(OverlayKey.parse(key.toString()), key);
    });

    test('identity is all three parts, not the packed string', () {
      expect(OverlayKey('recipe', 'a', 'note'), OverlayKey('recipe', 'a', 'note'));
      expect(
        OverlayKey('recipe', 'a', 'note'),
        isNot(OverlayKey('recipe', 'a', 'alias')),
      );
      expect(
        OverlayKey('recipe', 'a', 'note'),
        isNot(OverlayKey('ingredient', 'a', 'note')),
      );
      expect(
        OverlayKey('recipe', 'a', 'note').hashCode,
        OverlayKey('recipe', 'a', 'note').hashCode,
      );
    });

    test('a kind this build has never seen is still a valid key', () {
      // Two versions of the app meet during a sync, and the older one has to carry
      // the newer one's entries rather than drop them -- dropping an event in an
      // op-log loses a real operation, here somebody's note. So validation is
      // about shape and never about membership.
      expect(() => OverlayKey('cellar_shelf', 'a', 'order'), returnsNormally);
      expect(() => OverlayKey('shelf2', 'a', 'order'), returnsNormally);
    });

    test('and a malformed one is refused at the door', () {
      for (final bad in [
        () => OverlayKey('Recipe', 'a', 'note'), // not lowercase
        () => OverlayKey('', 'a', 'note'),
        () => OverlayKey('2shelf', 'a', 'note'),
        () => OverlayKey('recipe', 'a:b', 'note'), // reserved: ends the kind
        () => OverlayKey('recipe', 'a.b', 'note'), // reserved: ends the id
        () => OverlayKey('recipe', '', 'note'),
        () => OverlayKey('recipe', 'a', '9note'),
        () => OverlayKey('recipe', 'a', ''),
      ]) {
        expect(bad, throwsFormatException);
      }
    });

    test('the two reserved characters are what lets parse exist at all', () {
      // An id carrying either separator would make the packed form ambiguous and
      // there would be no inverse of it -- so refusing them is not a restriction
      // for its own sake, it is the price of the human-readable form.
      expect(() => OverlayKey.parse('recipe:a'), throwsFormatException);
      expect(() => OverlayKey.parse('recipe:'), throwsFormatException);
      expect(() => OverlayKey.parse(':a.note'), throwsFormatException);
      expect(() => OverlayKey.parse('a.note'), throwsFormatException);
      expect(() => OverlayKey.parse('recipe:a:b.note'), throwsFormatException);
    });

    test('a field may contain dots, which is how extras are expressed', () {
      final extra = OverlayKey.extra('ingredient', 'gin', 'glass');
      expect(extra.field, 'extras.glass');
      expect(extra.toString(), 'ingredient:gin.extras.glass');
      // Parse splits on the *first* dot after the colon, so everything past it
      // belongs to the field -- which is exactly the reason an id may not hold one.
      // `recipe:a.b.note` is therefore not ambiguous, it is id `a` field `b.note`.
      expect(OverlayKey.parse('recipe:a.b.note').field, 'b.note');
      expect(OverlayKey.parse('recipe:a.b.note').id, 'a');
    });

    test('the named kinds carry the field their consumer needs', () {
      expect(OverlayKey.recipe('x').field, 'note');
      expect(OverlayKey.ingredient('gin').field, 'alias');
      expect(OverlayKey.copy('stockEmptyHint').field, 'en');
    });

    test('a correction is keyed by language, so two do not overwrite each other', () {
      // The proposal's 4.2(b) puts a user's correction in the overlay keyed by the
      // string's key. One string can be corrected in more than one language, so the
      // language has to be part of the key -- and keying on a locale tag rather than
      // on "primary"/"secondary" means a correction survives the reader changing
      // which of their two languages is which.
      expect(
        OverlayKey.copy('stockEmptyHint', language: 'ja'),
        isNot(OverlayKey.copy('stockEmptyHint', language: 'en')),
      );
      expect(OverlayKey.copy('stockEmptyHint').toString(), 'copy:stockEmptyHint.en');
    });
  });
}
