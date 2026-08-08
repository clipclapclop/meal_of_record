class MathEvaluator {
  static double? evaluate(String expression) {
    try {
      // Remove whitespace
      final cleanExpr = expression.replaceAll(' ', '');
      if (cleanExpr.isEmpty) return null;

      // Simple recursive descent parser
      final parser = _Parser(cleanExpr);
      return parser.parse();
    } catch (e) {
      return null;
    }
  }
}

class _Parser {
  final String _text;
  int _pos = 0;
  int get _char => _pos < _text.length ? _text.codeUnitAt(_pos) : -1;

  _Parser(this._text);

  void _eatChar() {
    _pos++;
  }

  double parse() {
    final val = _parseExpression();
    if (_pos < _text.length) throw FormatException('Unexpected character');
    return val;
  }

  double _parseExpression() {
    double x = _parseTerm();
    while (true) {
      if (_char == 43) {
        // +
        _eatChar();
        x += _parseTerm();
      } else if (_char == 45) {
        // -
        _eatChar();
        x -= _parseTerm();
      } else {
        return x;
      }
    }
  }

  double _parseTerm() {
    double x = _parseFactor();
    while (true) {
      if (_char == 42) {
        // *
        _eatChar();
        x *= _parseFactor();
      } else if (_char == 47) {
        // /
        _eatChar();
        x /= _parseFactor();
      } else {
        return x;
      }
    }
  }

  double _parseFactor() {
    if (_char == 43) {
      // + (unary)
      _eatChar();
      return _parseFactor();
    }
    if (_char == 45) {
      // - (unary)
      _eatChar();
      return -_parseFactor();
    }

    double x;
    int startPos = _pos;
    if (_char == 40) {
      // (
      _eatChar();
      x = _parseExpression();
      if (_char == 41) {
        _eatChar(); // )
      }
    } else if ((_char >= 48 && _char <= 57) || _char == 46) {
      // 0-9 or .
      while ((_char >= 48 && _char <= 57) || _char == 46) {
        _eatChar();
      }
      x = double.parse(_text.substring(startPos, _pos));
    } else {
      throw FormatException('Unexpected character');
    }
    return x;
  }
}
