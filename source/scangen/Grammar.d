import std.regex;
import std.stdio;
import std.conv : to;
import std.array : split;

public import TokenInfo;


/**
 * A grammar consists of symbols:
 *  - terminal symbols, like tokens
 *  - non-terminal symbols, like productions
 *  - start-symbol
 *  - the productions themselves
 */
struct Symbol
{
  enum Type {
    TOKEN,
    PRODUCTION,
    LAMBDA,
    START,
    STOP
  };
  Type type;
  size_t id;
}

struct Production
{
  size_t id;
  Symbol[] symbols;
}


class GrammarException : Exception
{
  this(string message, string file = __FILE__, int line = __LINE__, Throwable next = null)
  {
    super(message, file, line, next);
  }
}

class Grammar
{
private:
  static Regex!char commentRegex = regex(r"^#.*$|^\s*$");
  static Regex!char tokenRegex = regex(r"^\s*(\w+)\s+/(.*)/\s*$");
  static Regex!char productionRegex = regex(r"^\s*(\w+)\s*=>\s*(.*)\s*$");
  static Regex!char symbolNameRegex = regex(r"^\s*(\w+)[\s=]");


  static bool isComment(in char[] line)
  {
    return !matchFirst(line, commentRegex).empty;
  }

  static bool isTokenInfo(in char[] line)
  {
    return !matchFirst(line, tokenRegex).empty;
  }

  static bool isProduction(in char[] line)
  {
    return !matchFirst(line, productionRegex).empty;
  }

public:
  size_t[string] nameSymbolIdMap;
  Symbol[] symbols;
  TokenInfo[] tokenInfos;
  Production[] productions;

  this() {
    symbols ~= Symbol(Symbol.Type.STOP);
    nameSymbolIdMap["STOP"] = symbols.length - 1;
    symbols ~= Symbol(Symbol.Type.LAMBDA);
    nameSymbolIdMap["LAMBDA"] = symbols.length - 1;
  }

  static bool readTokenInfo(in char[] line, out TokenInfo tokenInfo)
  {
      auto captures = matchFirst(line, tokenRegex);
      if (captures.empty)
        return false;
      tokenInfo = new TokenInfo(to!string(captures[1]),
                                          to!string(captures[2]));
      return true;
  }

  /**
   * Read a production and store it.  Note that productions may reference
   * existing productions and tokens.
   * The line of text contains the production definition.
   */
  bool readProduction(in char[] line, out Production production)
  {
    foreach (name; split(line)) {
      debug writeln("  name=", name);
      production.symbols ~= symbols[nameSymbolIdMap[name]];
    }
    debug writeln(" symbols = ", production.symbols);
    return true;
  }

  unittest
  {
    assert(!isComment("Hello There"));
    assert(isComment("#Hello There"));
    assert(isComment("   "));
    assert(isComment(""));

    TokenInfo ti;

    assert(readTokenInfo(r"LEVEL_START /^==+/", ti));
    assert(ti.name == "LEVEL_START");
    assert(!matchFirst("====", ti.regex).empty);

    assert(readTokenInfo(r"    LEVEL_END       /==+$/  ", ti));
    assert(ti.name == "LEVEL_END");
    assert(matchFirst("hambo ====", ti.regex).empty);
    assert(!matchFirst("====", ti.regex).empty);

  }

  void loadFromFile(in string filename)
  {
    uint lineNumber = 0;
    TokenInfo tokenInfo;

    auto file = File(filename, "r");

    auto range = file.byLine();
    foreach (line; range) {
      lineNumber++;

      // Check for comment lines and skip them.
      if (isComment(line))
        continue;

      // An equal sign divides sections in our format.
      if (line[0] == '=') {
        range.popFront();
        break;
      }

      // Try to read our config.
      if (!readTokenInfo(line, tokenInfo))
        throw new GrammarException("TokenInfo format error:  " ~ to!string(line),
                                   filename, lineNumber);
      tokenInfos ~= tokenInfo;  // Add our new token.
      // Create a symbolic that references this token.
      symbols ~= Symbol(Symbol.Type.TOKEN, tokenInfos.length - 1);
      // And make sure we can map the name to it's symbol-id.
      nameSymbolIdMap[tokenInfo.name] = symbols.length - 1;
    }

    // For productions, we need to make two passes.
    // This first pass saves the lines and creates a symbol.
    char[][] productionLines;
    foreach (line; range) {
      debug writeln("Reading production line: ", line);
      lineNumber++;

      // Check for comment lines and skip them.
      if (isComment(line))
        continue;

      // Try to read our config.
      if (!isProduction(line))
        throw new GrammarException("Production format error:  " ~ to!string(line),
                                   filename, lineNumber);

      // Save this line for further processing.
      productionLines ~= line.dup;
      productions ~= Production();  // Create an empty production place-holder.
      symbols ~= Symbol(Symbol.Type.PRODUCTION, productions.length - 1);

      // For now, just get the symbol name and make room.
      string symbolName = to!string(matchFirst(line, symbolNameRegex)[1]);
      nameSymbolIdMap[symbolName] = symbols.length - 1;
    }

    // This second pass builds productions with knowledge of all
    // symbols available.
    debug writeln("Reading Productions, second pass.");
    foreach (line; productionLines) {
      debug writeln("productionLine is ", line);
      auto captures = matchFirst(line, productionRegex);
      string productionName = to!string(captures[1]);
      debug writeln("Reading productionName = ", productionName);
      char[] productionText = captures[2];
      Symbol productionSymbol = symbols[nameSymbolIdMap[productionName]];
      Production* production = &productions[productionSymbol.id];
      readProduction(productionText, *production);
    }
  }

}

