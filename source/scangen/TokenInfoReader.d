import std.regex;
import std.stdio;
import std.conv;

import TokenInfo;


class TokenInfoReaderException : Exception
{
  this(string message, string file = __FILE__, int line = __LINE__, Throwable next = null)
  {
    super(message, file, line, next);
  }
}

class TokenInfoReader
{
private:
  static Regex!char commentRegex = regex(r"^#.*$|^\s*$");
  static Regex!char tokenRegex = regex(r"^\s*(\w+)\s+/(.*)/\s*$");


  static bool isCommentLine(in char[] line)
  {
    return !matchFirst(line, commentRegex).empty;
  }

public:

  static bool readLine(in char[] line, out TokenInfo tokenInfo)
  {
      auto captures = matchFirst(line, tokenRegex);
      if (captures.empty)
        return false;
      debug {
        writeln("captures[0] = '", captures[0], "'");
        writeln("captures[1] = '", captures[1], "'");
        writeln("captures[2] = '", captures[2], "'");
      }
      tokenInfo = new TokenInfo(to!string(captures[1]),
                                to!string(captures[2]));
      return true;
  }

  unittest
  {
    assert(!isCommentLine("Hello There"));
    assert(isCommentLine("#Hello There"));
    assert(isCommentLine("   "));
    assert(isCommentLine(""));

    TokenInfo ti;
    assert(readLine(r"LEVEL_START /^==+/", ti));
    assert(ti.name == "LEVEL_START");
    assert(!matchFirst("====", ti.regex).empty);

    assert(readLine(r"    LEVEL_END       /==+$/  ", ti));
    assert(ti.name == "LEVEL_END");
    assert(matchFirst("hambo ====", ti.regex).empty);
    assert(!matchFirst("====", ti.regex).empty);

  }

  static TokenInfo[] readFile(in string filename)
  {
    TokenInfo[] tokenInfos;
    uint lineNumber = 0;
    TokenInfo tokenInfo;

    auto file = File(filename, "r");

    foreach (line; file.byLine()) {
      lineNumber++;

      // Check for comment lines and skip them.
      if (isCommentLine(line))
        continue;

      // Try to read our config.
      if (!readLine(line, tokenInfo))
        throw new TokenInfoReaderException("Format error:  " ~ to!string(line),
                                           filename, lineNumber);
      tokenInfos ~= tokenInfo;
    }
    return tokenInfos;
  }

}

