import std.regex;

struct TokenInfo
{
  size_t symbolId;
  string name;
  Regex!char regex;
  bool lineStart;

  this(string name, string regexPattern)
  {
    this.name = name;
    // All patterns must match the start of the current input.
    // We use '^' at the start of a pattern to indicate the
    // beginning of a line.
    if (regexPattern.length > 1 && regexPattern[0] == '^') {
      this.regex = .regex(regexPattern);
      this.lineStart = true;
    }
    else {
      this.regex = .regex("^" ~ regexPattern);
      this.lineStart = false;
    }
  }
}
