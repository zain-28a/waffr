// SmileForm: seven faces by score, and the hysteresis that keeps the face
// from flipping while the score hovers on an edge.

import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/core/insights/smart/wallet_mood.dart';
import 'package:waffr/widgets/brand/waffr_mouth.dart';

void main() {
  test('every score maps to one of seven forms, happiest first', () {
    expect(SmileForm.values, hasLength(7));
    // The logo's own smile is the happiest face.
    expect(SmileForm.values.first, SmileForm.excellent);
    expect(SmileForm.forScore(100), SmileForm.excellent);
    expect(SmileForm.forScore(85), SmileForm.excellent);
    expect(SmileForm.forScore(75), SmileForm.happy);
    expect(SmileForm.forScore(68), SmileForm.pleased);
    expect(SmileForm.forScore(60), SmileForm.content);
    expect(SmileForm.forScore(50), SmileForm.neutral);
    expect(SmileForm.forScore(35), SmileForm.uneasy);
    expect(SmileForm.forScore(10), SmileForm.sad);
    expect(SmileForm.forScore(0), SmileForm.sad);
  });

  test('a score hovering on an edge keeps the current face', () {
    // pleased covers 65-71; 64 and 63 stay pleased, 61 moves on.
    expect(SmileForm.next(64, SmileForm.pleased), SmileForm.pleased);
    expect(SmileForm.next(65, SmileForm.content), SmileForm.content);
    expect(SmileForm.next(62, SmileForm.pleased), SmileForm.pleased);
    expect(SmileForm.next(61, SmileForm.pleased), SmileForm.content);
    expect(SmileForm.next(68, SmileForm.content), SmileForm.pleased);
    // A big jump moves straight to the right face.
    expect(SmileForm.next(95, SmileForm.sad), SmileForm.excellent);
    expect(SmileForm.next(5, SmileForm.excellent), SmileForm.sad);
    expect(SmileForm.next(70, null), SmileForm.pleased);
  });

  test('alternating scores across an edge never flip the face', () {
    var form = SmileForm.next(65, null);
    for (final score in [64, 65, 64, 66, 63, 65, 64]) {
      form = SmileForm.next(score, form);
      expect(form, SmileForm.pleased);
    }
  });

  test('each form has its own mouth, from smile to frown', () {
    final shapes = SmileForm.values.map(MouthShape.of).toSet();
    expect(shapes, hasLength(7));
    expect(MouthShape.of(SmileForm.excellent), MouthShape.excellent);
    // Smiles curve down in the middle, frowns curve up.
    expect(MouthShape.excellent.lowerDepth, greaterThan(0));
    expect(MouthShape.sad.upperDepth, lessThan(0));
    expect(MouthShape.topmost, MouthShape.excellent.cornerY);
  });
}
