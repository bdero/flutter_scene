/// Strips JSONC niceties so a hand-edited `.fscene` parses with the strict
/// JSON decoder.
///
/// Removes `//` line comments and `/* ... */` block comments, then drops
/// trailing commas before `}` and `]`. Comment characters and commas inside
/// string literals are preserved. The canonical written form is strict JSON;
/// this only loosens the read path.
String stripJsonc(String source) =>
    _stripTrailingCommas(_stripComments(source));

String _stripComments(String s) {
  final out = StringBuffer();
  final n = s.length;
  var i = 0;
  var inString = false;
  while (i < n) {
    final c = s[i];
    if (inString) {
      out.write(c);
      if (c == r'\' && i + 1 < n) {
        out.write(s[i + 1]);
        i += 2;
        continue;
      }
      if (c == '"') inString = false;
      i++;
      continue;
    }
    if (c == '"') {
      inString = true;
      out.write(c);
      i++;
      continue;
    }
    if (c == '/' && i + 1 < n && s[i + 1] == '/') {
      i += 2;
      while (i < n && s[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && i + 1 < n && s[i + 1] == '*') {
      i += 2;
      while (i + 1 < n && !(s[i] == '*' && s[i + 1] == '/')) {
        i++;
      }
      i += 2;
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

String _stripTrailingCommas(String s) {
  final out = StringBuffer();
  final n = s.length;
  var i = 0;
  var inString = false;
  while (i < n) {
    final c = s[i];
    if (inString) {
      out.write(c);
      if (c == r'\' && i + 1 < n) {
        out.write(s[i + 1]);
        i += 2;
        continue;
      }
      if (c == '"') inString = false;
      i++;
      continue;
    }
    if (c == '"') {
      inString = true;
      out.write(c);
      i++;
      continue;
    }
    if (c == ',') {
      var j = i + 1;
      while (j < n &&
          (s[j] == ' ' || s[j] == '\t' || s[j] == '\n' || s[j] == '\r')) {
        j++;
      }
      if (j < n && (s[j] == '}' || s[j] == ']')) {
        i++; // drop the trailing comma
        continue;
      }
    }
    out.write(c);
    i++;
  }
  return out.toString();
}
