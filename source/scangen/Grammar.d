import std.regex;
import std.range;
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
  string name;  // Useful for debugging.
  size_t id;
}

struct Production
{
  size_t symbolId;
  size_t[] symbolIds;
}


class GrammarException : Exception
{
  this(string message, int line = __LINE__, Throwable next = null)
  {
    super(message, __FILE__, line, next);
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
  Symbol[] symbols;
  TokenInfo[] tokenInfos;
  Production[] productions;

  size_t[string] nameSymbolIdMap;  // Used while processing config file.
  // A symbol may map to 1 token.
  TokenInfo*[size_t] symbolIdTokenInfoMap;
  // A symbol may map to many productions.
  Production*[][size_t] symbolIdProductionsMap;

  this() {
    symbols ~= Symbol(Symbol.Type.STOP, "STOP");
    nameSymbolIdMap["STOP"] = symbols.length - 1;
    symbols ~= Symbol(Symbol.Type.LAMBDA, "LAMBDA");
    nameSymbolIdMap["LAMBDA"] = symbols.length - 1;
  }

  static bool readTokenInfo(in char[] line, TokenInfo* tokenInfo)
  {
      auto captures = matchFirst(line, tokenRegex);
      if (captures.empty)
        return false;
      *tokenInfo = TokenInfo.TokenInfo(to!string(captures[1]),
                             to!string(captures[2]));
      return true;
  }

  // Test1
  unittest
  {
    assert(!isComment("Hello There"));
    assert(isComment("#Hello There"));
    assert(isComment("   "));
    assert(isComment(""));

    TokenInfo ti;

    assert(readTokenInfo(r"LEVEL_START /^==+/", &ti));
    assert(ti.name == "LEVEL_START");
    assert(!matchFirst("====", ti.regex).empty);

    assert(readTokenInfo(r"    LEVEL_END       /==+$/  ", &ti));
    assert(ti.name == "LEVEL_END");
    assert(matchFirst("hambo ====", ti.regex).empty);
    assert(!matchFirst("====", ti.regex).empty);
    debug writeln("Test1 [OK]");
  }

  /**
   * Read a production and store it.  Note that productions may reference
   * existing productions and tokens.
   * The line of text contains the production definition.
   */
  bool readProduction(in string line)
  {
    auto captures = matchFirst(line, productionRegex);
    if (captures.empty)
      return false;


    string productionName = to!string(captures[1]);
    size_t symbolId = nameSymbolIdMap[productionName];
    productions ~= Production(symbolId);
    Production* production = &productions[productions.length - 1];

    string productionText = captures[2];
    foreach (name; split(productionText)) {
      debug writeln("  name=", name);
      production.symbolIds ~= nameSymbolIdMap[name];
    }

    symbolIdProductionsMap[symbolId] ~= production;

    return true;
  }


  void load(T)(T range) if (isInputRange!T)
  {
    uint lineNumber = 0;
    TokenInfo tokenInfo;

    debug writeln("Reading tokens section.");
    while (!range.empty()) {
      string line = to!string(range.front());
      range.popFront();
      writeln("line is: ", line);
      lineNumber++;

      // Check for comment lines and skip them.
      if (isComment(line))
        continue;

      // An equal sign divides sections in our format.
      if (line[0] == '=')
        break;

      // Try to read our config.
      if (!readTokenInfo(line, &tokenInfo))
        throw new GrammarException("TokenInfo format error:  " ~ to!string(line),
                                   lineNumber);
      tokenInfos ~= tokenInfo;  // Add our new token.
      // Create a symbolic that references this token.
      writeln("tokenInfo.name = ", tokenInfo.name);
      symbols ~= Symbol(Symbol.Type.TOKEN, tokenInfo.name);
      symbolIdTokenInfoMap[symbols.length - 1] =
        &tokenInfos[tokenInfos.length - 1];
      // And make sure we can map the name to it's symbol-id.
      nameSymbolIdMap[tokenInfo.name] = symbols.length - 1;
    }

    // For productions, we need to make two passes.
    // This first pass saves the lines and creates a symbol.
    debug writeln("Reading Productions, first pass.");
    string[] productionLines;
    while (!range.empty()) {
      string line = to!string(range.front());
      range.popFront();
      debug writeln("Reading production line: ", line);
      lineNumber++;

      // Check for comment lines and skip them.
      if (isComment(line))
        continue;

      // Try to read our config.
      if (!isProduction(line))
        throw new GrammarException("Production format error:  " ~ to!string(line),
                                   lineNumber);

      // Save this line for further processing.
      productionLines ~= line;

      // For now, just get the symbol name and make room.
      string symbolName = to!string(matchFirst(line, symbolNameRegex)[1]);
      debug writeln("Adding symbol: ", symbolName);
      if (symbolName !in nameSymbolIdMap) {
        symbols ~= Symbol(Symbol.Type.PRODUCTION, symbolName);
        nameSymbolIdMap[symbolName] = symbols.length - 1;
      }
    }

    // This second pass builds productions with knowledge of all
    // symbols available.
    debug writeln("Reading Productions, second pass.");
    foreach (line; productionLines) {
      debug writeln("productionLine is ", line);
      readProduction(line);
    }
  }

  // Test2
  unittest
  {
    Grammar g = new Grammar();
    string[] text =
      [
       r"EMPTY_LINE         /^$/",
       r"LEVEL_OPEN         /^==+/",
       ];
    g.load(text);
    assert(g.tokenInfos.length == 2);
    assert(g.productions.length == 0);
    assert(g.symbols.length == 4);  // Don't forget "STOP" and "LAMBDA".
    debug writeln("Test2 [OK]");
  }

  // Test3
  unittest
  {
    Grammar g = new Grammar();
    string[] text =
      [
       r"# Some comments to ignore.",
       r"# More over here.",
       r"EMPTY_LINE         /^$/",
       r"LEVEL_OPEN         /^==+/",
       r"= Productions =",
       r"ham => cat ham",
       r"# Cats are fluffy.",
       r"cat => EMPTY_LINE",
       r"cat => LEVEL_OPEN",
       r"# No more input now."
       ];
    g.load(text);
    assert(g.tokenInfos.length == 2);
    assert(g.productions.length == 3);
    assert(g.symbols.length == 6);  // Don't forget "STOP" and "LAMBDA".
    assert(g.nameSymbolIdMap.length == 6);
    assert(g.symbolIdTokenInfoMap.length == 2);
    assert(g.symbolIdProductionsMap.length == 2);
    assert(g.symbolIdProductionsMap[g.nameSymbolIdMap["cat"]].length == 2);
    debug writeln("Test3 [OK]");
  }
}

