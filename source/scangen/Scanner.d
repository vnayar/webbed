import std.conv;
import std.regex;
import std.uni;
import std.string;
import std.stdio;

import TokenInfo;

public import Token;



class ScannerException : Exception
{
  this(string message, string file = __FILE__, int line = __LINE__, Throwable next = null)
  {
    super(message, file, line, next);
  }
}

/**
 * Tokens are assumed to have white-space in between them, which is
 * mulched before token regexes are considered.
 */
class Scanner
{
  TokenInfo[] tokenInfos;
  Token stopToken;

  size_t lineNum = 0;
  size_t linePos = 0;
  string[] lines;

  this(TokenInfo[] tokenInfos, size_t stopSymbolId)
  {
    this.tokenInfos = tokenInfos;
    this.stopToken = Token.Token(stopSymbolId);
  }

  void load(string input)
  {
    lines = input.splitLines();
    lineNum = 0;
    linePos = 0;

    skipSpace();  // Position our read at the first potential token.
  }

  void skip(size_t num)
  {
    if (empty())
      return;
    if (lineNum < lines.length && linePos >= lines[lineNum].length) {
      linePos = linePos - lines[lineNum].length;
      lineNum++;
    }
    linePos += num;
  }

  // Skip past all consecutive whitespace.
  void skipWhite()
  {
    while (!empty() && lines[lineNum].length > 0 &&
           (linePos == lines[lineNum].length || isWhite(lines[lineNum][linePos]))) {
      skip(1);
    }
  }

  // Skip past all consecutive space.
  void skipSpace()
  {
    while (!empty() && lines[lineNum].length > 0 &&
           linePos < lines[lineNum].length && isSpace(lines[lineNum][linePos])) {
      skip(1);
    }
  }


  bool empty()
  {
    return lineNum > lines.length - 1 ||
      lineNum == lines.length - 1 && linePos >= lines[lineNum].length;
  }

  Token getToken()
    in {
      assert(empty() || lines[lineNum].length == 0 ||
             linePos == lines[lineNum].length || !isWhite(lines[lineNum][linePos]));
    }
  body {
    // If there is no input left, issue a stop token.
    if (empty())
      return stopToken;

    Token token;
    string line = lines[lineNum];
    // Iterate through tokens to see which one matches.
    size_t i = 0;
    for (; i < tokenInfos.length; i++) {
      auto captures = matchFirst(line[linePos .. $], tokenInfos[i].regex);
      if (!captures.empty &&
          (tokenInfos[i].lineStart == false || linePos == 0)) {
        token.id = tokenInfos[i].symbolId;
        token.text = captures.front;
        captures.popFront();
        while (!captures.empty) {
          token.groups ~= captures.front;
          captures.popFront();
        }
        skip(token.text.length);
        break;
      }
    }
    if (i == tokenInfos.length)
      throw new ScannerException("No valid token on line " ~
                                 to!string(lineNum) ~ " for line:\n" ~ line ~
                                 "\n  --> " ~ line[linePos .. $]);

    // Prepare for the next call to getToken() or hasToken().
    skipSpace();

    return token;
  }

}
