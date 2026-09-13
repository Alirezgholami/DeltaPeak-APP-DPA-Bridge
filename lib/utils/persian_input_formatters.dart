import 'package:flutter/services.dart';

import 'persian_normalizer.dart';

/// Normalizes Arabic/Persian letter variants while the user is typing.
/// Trailing spaces are intentionally preserved here so typing multi-word names
/// remains natural; final trim/collapse still happens before persistence.
class PersianTextInputFormatter extends TextInputFormatter {
  const PersianTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalized = PersianNormalizer.normalizeTextForInput(newValue.text);
    if (normalized == newValue.text) return newValue;

    int mappedOffset(int offset) {
      if (offset < 0) return offset;
      final safe = offset.clamp(0, newValue.text.length).toInt();
      return PersianNormalizer.normalizeTextForInput(
        newValue.text.substring(0, safe),
      ).length;
    }

    return newValue.copyWith(
      text: normalized,
      selection: TextSelection(
        baseOffset: mappedOffset(newValue.selection.baseOffset),
        extentOffset: mappedOffset(newValue.selection.extentOffset),
        affinity: newValue.selection.affinity,
        isDirectional: newValue.selection.isDirectional,
      ),
      composing: TextRange.empty,
    );
  }
}

/// Converts Persian/Arabic digits and decimal separators to the canonical
/// numeric representation while the value is entered.
class LocalizedNumberInputFormatter extends TextInputFormatter {
  const LocalizedNumberInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalized = PersianNormalizer.normalizeNumberInput(newValue.text);
    if (normalized == newValue.text) return newValue;

    int mappedOffset(int offset) {
      if (offset < 0) return offset;
      final safe = offset.clamp(0, newValue.text.length).toInt();
      return PersianNormalizer.normalizeNumberInput(
        newValue.text.substring(0, safe),
      ).length;
    }

    return newValue.copyWith(
      text: normalized,
      selection: TextSelection(
        baseOffset: mappedOffset(newValue.selection.baseOffset),
        extentOffset: mappedOffset(newValue.selection.extentOffset),
        affinity: newValue.selection.affinity,
        isDirectional: newValue.selection.isDirectional,
      ),
      composing: TextRange.empty,
    );
  }
}
