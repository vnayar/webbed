import std.regex;
import std.range;
import std.stdio;
import std.conv : to;
import std.array : split;

import container;
public import TokenInfo;


// Some test data shared by multiple unittests.
version(unittest)
{
  string[] grammarConfig =
    [
     r"# Tokens",
     r"VAR /_\w+/",
     r"FUNC /\w+/",
     r"PLUS /\+/",
     r"LPAREN /\(/",
     r"RPAREN /\)/",
     r"= Productions =",
     r"E => PREFIX LPAREN E RPAREN",
     r"E => VAR TAIL",
     r"PREFIX => FUNC",
     r"PREFIX =>",
     r"TAIL => PLUS E",
     r"TAIL =>"
     ];
}

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
    START
  };
  Type type;
  string name;  // Useful for debugging.
  size_t id;
}

/**
 * Productions describe combinations of symbols that are in the language.
 * A grammar production rule of the form:
 *  PRODUCTION_SYMBOL => SYMBOL SYMBOL SYMBOL ...
 */
struct Production
{
  size_t symbolId;
  size_t[] symbolIds;
}

/**
 * Exceptions specific to the evaluation of a grammar description.
 */
class GrammarException : Exception
{
  this(string message, int line = __LINE__, Throwable next = null)
  {
    super(message, __FILE__, line, next);
  }
}


/**
 * A set of symbols (both terminal and non-terminal) that together describe
 * the rules that indicate valid instances of a language.  All these rules,
 * and their operations, collectively are the grammar.
 */
class Grammar
{
private:
  // Regular expressions used to recognize configuration data.
  static Regex!char commentRegex = regex(r"^#.*$|^\s*$");
  static Regex!char tokenRegex = regex(r"^\s*(\w+)\s+/(.*)/\s*$");
  static Regex!char productionRegex = regex(r"^\s*(\w+)\s*=>\s*(.*)\s*$");
  static Regex!char symbolNameRegex = regex(r"^\s*(\w+)[\s=]");


  static bool isComment(in char[] line)
  {
    return !matchFirst(line, commentRegex).empty;
  }

  unittest
  {
    assert(!isComment("Hello There"));
    assert(isComment("#Hello There"));
    assert(isComment("   "));
    assert(isComment(""));
    debug writeln("isComment [OK]");
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
  // Core data for the grammar.
  Symbol[] symbols;  // A complete listing of all symbols in the grammar.
  size_t START_ID;
  size_t STOP_ID;
  size_t LAMBDA_ID;
  TokenInfo[] tokenInfos;  // Details about token symbols.
  Production[] productions;  // Details about production symbols.

  // Helper data for displaying and looking up symbols.
  size_t[string] nameSymbolIdMap;  // Used while processing config file.
  size_t[size_t] symbolIdTokenInfoIdMap;  // A symbol may map to 1 token.
  size_t[][size_t] symbolIdProductionIdsMap;  // A symbol may map to many productions.

  this() {
    symbols ~= Symbol(Symbol.Type.START, "START");
    nameSymbolIdMap["START"] = symbols.length - 1;
    START_ID = symbols.length - 1;
    symbols ~= Symbol(Symbol.Type.TOKEN, "STOP");
    nameSymbolIdMap["STOP"] = symbols.length - 1;
    STOP_ID = symbols.length - 1;
    symbols ~= Symbol(Symbol.Type.TOKEN, "LAMBDA");
    nameSymbolIdMap["LAMBDA"] = symbols.length - 1;
    LAMBDA_ID = symbols.length - 1;
  }

  // Interperet a configuration line as a TokenInfo record.
  static bool readTokenInfo(in char[] line, TokenInfo* tokenInfo)
  {
      auto captures = matchFirst(line, tokenRegex);
      if (captures.empty)
        return false;
      *tokenInfo = TokenInfo.TokenInfo(to!string(captures[1]),
                             to!string(captures[2]));
      return true;
  }

  unittest
  {
    TokenInfo ti;

    assert(readTokenInfo(r"LEVEL_START /^==+/", &ti));
    assert(ti.name == "LEVEL_START");
    assert(!matchFirst("====", ti.regex).empty);

    assert(readTokenInfo(r"    LEVEL_END       /==+$/  ", &ti));
    assert(ti.name == "LEVEL_END");
    assert(matchFirst("hambo ====", ti.regex).empty);
    assert(!matchFirst("====", ti.regex).empty);
    debug writeln("readTokenInfo [OK]");
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
    symbolIdProductionIdsMap[symbolId] ~= productions.length - 1;
    Production* production = &productions[productions.length - 1];

    string productionText = captures[2];
    foreach (name; split(productionText)) {
      debug writeln("  name=", name);
      if (name !in nameSymbolIdMap)
        throw new GrammarException("Reference to unknown symbol " ~ name ~
                                   " in line " ~ line);
      production.symbolIds ~= nameSymbolIdMap[name];
    }


    return true;
  }

  /**
   * Load full grammar configuration and store all symbols and productions.
   * Any valid range may be used as an input, e.g. file.byLine() or string[].
   */
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
      symbols ~= Symbol(Symbol.Type.TOKEN, tokenInfo.name);
      tokenInfo.symbolId = symbols.length - 1;
      // And make sure we can map the name to it's symbol-id.
      nameSymbolIdMap[tokenInfo.name] = symbols.length - 1;

      tokenInfos ~= tokenInfo;  // Add our new token.
      symbolIdTokenInfoIdMap[symbols.length - 1] = tokenInfos.length - 1;
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
    assert(g.symbols.length == 5);  // Don't forget "START", "STOP", and "LAMBDA".
    debug writeln("load[1] [OK]");
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
    assert(g.symbols.length == 7);  // Don't forget "START", "STOP", and "LAMBDA".
    assert(g.nameSymbolIdMap.length == 7);
    assert(g.symbolIdTokenInfoIdMap.length == 2);
    assert(g.symbolIdProductionIdsMap.length == 2);
    assert(g.symbolIdProductionIdsMap[g.nameSymbolIdMap["cat"]].length == 2);
    debug writeln("load[2] [OK]");
  }

public:
  // Utility data and functions used for complex grammar parsing.
  bool[] symbolDerivesLambda;
  Set!(size_t)[] symbolFirstSet;
  Set!(size_t)[] symbolFollowSet;

  // Fill in data indicating if a production can derive LAMBDA.
  void initSymbolDerivesLambda()
  {
    debug writeln("initSymbolDerivesLambda start");
    // Initialize our data, initialized to false.
    symbolDerivesLambda.length = symbols.length;

    bool isChange;
    do {
      isChange = false;
      foreach (production; productions) {
        writeln("Working on production:  ", production);
        if (!symbolDerivesLambda[production.symbolId]) {
          // Check if the production is itself lambda (empty).
          if (production.symbolIds.length == 0) {
            isChange = true;
            symbolDerivesLambda[production.symbolId] = true;
            continue;
          }
          // Check if each part of the RHS derives lambda.
          bool isProdLambda = true;
          foreach (symbolId; production.symbolIds)
            isProdLambda = isProdLambda && symbolDerivesLambda[symbolId];

          if (isProdLambda) {
            isChange = true;
            symbolDerivesLambda[production.symbolId] = true;
          }
        }
      }
    } while (isChange);
    debug writeln("initSymbolDerivesLambda end");
  }

  unittest
  {
    Grammar g = new Grammar();
    string[] text =
      [
       r"a  /a/",
       r"= Productions =",
       r"A => B C",
       r"B => D E",
       r"C => a",
       r"D =>",
       r"E =>",
       r"E => a",
       ];
    g.load(text);
    g.initSymbolDerivesLambda();
    assert(g.symbolDerivesLambda[g.productions[0].symbolId] == false);
    assert(g.symbolDerivesLambda[g.productions[1].symbolId] == true);
    assert(g.symbolDerivesLambda[g.productions[2].symbolId] == false);
    assert(g.symbolDerivesLambda[g.productions[3].symbolId] == true);
    assert(g.symbolDerivesLambda[g.productions[4].symbolId] == true);

    debug writeln("initSymbolDerivesLambda [OK]");
  }

  // Get the terminal symbol may be the first in a list of symbols.
  Set!size_t computeFirstSet(in size_t[] symbolIds)
  in {
    assert(symbolFirstSet.length == symbols.length,
           "Call initSymbolFirstSet before calling computeFirstSet!");
  }
  body {
    debug writeln("computeFirstSet start, symbolIds=", symbolIds);
    auto result = new Set!size_t();
    if (symbolIds.length == 0) {
      result.add(LAMBDA_ID);  // An empty list may derive lambda.
      return result;
    }

    bool canBeLambda = true;
    debug writeln("Test point alpha: symbolIds = ", symbolIds);
    result.add(symbolFirstSet[symbolIds[0]]);
    debug writeln("Test point bravo");
    for (auto i = 0; i < symbolIds.length && canBeLambda; i++) {
      auto firstSet = symbolFirstSet[symbolIds[i]];
      result.add(firstSet);

      if (!firstSet.contains(LAMBDA_ID)) {
        canBeLambda = false;
        result.remove(LAMBDA_ID);
      }
    }

    debug writeln("computeFirstSet end");
    return result;
  }

  // Note: The set type used here depends on dynamic memory allocation.
  // Performance may be performed for sets with known max sizes by using
  // a bit-vector.  Consider std.container.Array!bool
  void initSymbolFirstSet()
    in {
      assert(symbolDerivesLambda.length == symbols.length,
             "Call initDerivesLambda before initSymbolFirstSet!");
    }
  body {
    debug writeln("initSymbolFirstSet start");
    symbolFirstSet.length = symbols.length;

    // Initialize the production first-sets to empty.
    foreach (production; productions) {
      symbolFirstSet[production.symbolId] = new Set!size_t();
      // We use the LAMBDA_ID to indicate symbols that may derive
      // lambda, but optionally may start with terminals as well.
      if (symbolDerivesLambda[production.symbolId] == true)
        symbolFirstSet[production.symbolId].add(LAMBDA_ID);
    }

    // The terminal symbols are straight forward, they are their own "first".
    foreach (tokenInfo; tokenInfos) {
      symbolFirstSet[tokenInfo.symbolId] = new Set!size_t();
      symbolFirstSet[tokenInfo.symbolId].add(tokenInfo.symbolId);
      // While we're here, add to productions that start with this symbol.
      foreach (production; productions) {
        if (production.symbolIds.length > 0 &&
            production.symbolIds[0] == tokenInfo.symbolId)
          symbolFirstSet[production.symbolId].add(tokenInfo.symbolId);
      }
    }
    // Don't forget the STOP symbol.
    symbolFirstSet[STOP_ID] = new Set!size_t();
    symbolFirstSet[STOP_ID].add(STOP_ID);
    symbolFirstSet[LAMBDA_ID] = new Set!size_t();
    symbolFirstSet[LAMBDA_ID].add(LAMBDA_ID);

    // New we propagate changes up depending on what symbols may derive lambda.
    bool isChange;
    do {
      isChange = false;
      foreach (production; productions) {
        auto firstSet = symbolFirstSet[production.symbolId];
        auto size = firstSet.size();
        firstSet.add(computeFirstSet(production.symbolIds));
        // Check to see if the set changed.
        if (size != firstSet.size())
          isChange = true;
      }
    } while (isChange);
    debug writeln("initSymbolFirstSet end");
  }

  unittest
  {
    auto g = new Grammar();
    g.load(grammarConfig);
    g.initSymbolDerivesLambda();
    g.initSymbolFirstSet();

    auto LPAREN_firstSet = g.symbolFirstSet[g.nameSymbolIdMap["LPAREN"]];
    assert(LPAREN_firstSet.size() == 1);
    assert(LPAREN_firstSet.contains(g.nameSymbolIdMap["LPAREN"]));

    auto E_firstSet = g.symbolFirstSet[g.nameSymbolIdMap["E"]];
    debug writeln("Testing E_firstSet ", E_firstSet.toArray());
    assert(E_firstSet.size() == 3);
    assert(E_firstSet.contains(g.nameSymbolIdMap["VAR"]));
    assert(E_firstSet.contains(g.nameSymbolIdMap["FUNC"]));
    assert(E_firstSet.contains(g.nameSymbolIdMap["LPAREN"]));

    auto PREFIX_firstSet = g.symbolFirstSet[g.nameSymbolIdMap["PREFIX"]];
    assert(PREFIX_firstSet.size() == 2);
    assert(PREFIX_firstSet.contains(g.nameSymbolIdMap["FUNC"]));
    assert(PREFIX_firstSet.contains(g.nameSymbolIdMap["LAMBDA"]));

    auto TAIL_firstSet = g.symbolFirstSet[g.nameSymbolIdMap["TAIL"]];
    assert(TAIL_firstSet.size() == 2);
    assert(TAIL_firstSet.contains(g.nameSymbolIdMap["PLUS"]));
    assert(TAIL_firstSet.contains(g.nameSymbolIdMap["LAMBDA"]));

    debug writeln("initSymbolFirstSet [OK]");
  }

  /**
   * Compute the set of symbols that may come after a non-terminal in the grammar.
   *
   * For non-terminal symbols (productions), the follow-set is constructed
   * by looking at instances where the non-terminal is on the right side
   * of a production, and then looking at the first-set of the symbol
   * to its right.
   */
  void initSymbolFollowSet()
    in {
      assert(symbolDerivesLambda.length == symbols.length,
             "initSymbolFollowSet depends upon initSymbolDerivesLambda!");
      assert(symbolFirstSet.length == symbols.length,
             "initSymbolFollowSet depends upon initSymbolFirstSet!");
    }
  body {
    debug writeln("initSymbolFollowSet start");
    symbolFollowSet.length = symbols.length;

    // Initialize the follow-set of non-terminal symbols to be an empty set.
    // TODO:  Multiple productions may have the same symbol, revise our data.
    foreach (production; productions) {
      symbolFollowSet[production.symbolId] = new Set!size_t();
    }

    debug writeln("Test A");
    // No symbol may follow the start symbol, LAMBDA indicates this.
    auto startId = productions[0].symbolId;  // TODO:  Always use first production?
    symbolFollowSet[startId] = new Set!size_t();
    symbolFollowSet[startId].add(LAMBDA_ID);
    symbolFollowSet[STOP_ID] = new Set!size_t();
    symbolFollowSet[STOP_ID].add(LAMBDA_ID);

    debug writeln("Test B");
    // Because the follow-set of a non-terminal can depend on the follow-set
    // of the left-side of any production it is in, we must iterate several
    // times until no changes are made.
    bool isChange;
    do {
      isChange = false;
      foreach (production; productions) {
        foreach (prodSymIndex, prodSymId; production.symbolIds) {
          // We are only processing non-terminals.
          if (symbols[prodSymId].type != Symbol.Type.PRODUCTION)
            continue;

          debug writeln("Test C");
          // Save the size so we can check for changes.
          auto followSetSize = symbolFollowSet[prodSymId].size();
          debug writeln("Test C2");
          debug writeln("  production.symbolId = ", production.symbolId);
          debug writeln("  production.symbolIds = ", production.symbolIds);
          debug writeln("  prodSymIndex = ", prodSymIndex);

          auto rightFirstSet =
            computeFirstSet(production.symbolIds[prodSymIndex + 1 .. $]);
          debug writeln("Test C3");
          bool rightDerivesLambda = rightFirstSet.contains(LAMBDA_ID);
          rightFirstSet.remove(LAMBDA_ID);
          debug writeln("Test C4");

          // The symbols in the first-set of what follows this production
          // can be part of its follow set with the exception of LAMBDA.
          symbolFollowSet[prodSymId].add(rightFirstSet);

          debug writeln("Test D");
          // If the content to the right can be empty, add the follow-set
          // of the symbol on the left side of a production.
          if (rightDerivesLambda)
            symbolFollowSet[prodSymId].add(symbolFollowSet[production.symbolId]);

          // Check for changes.
          if (followSetSize != symbolFollowSet[prodSymId].size())
            isChange = true;
        }
      }
    } while (isChange);
    debug writeln("initSymbolFollowSet end");
  }

  unittest
  {
    auto g = new Grammar();
    g.load(grammarConfig);
    g.initSymbolDerivesLambda();
    g.initSymbolFirstSet();
    g.initSymbolFollowSet();

    auto E_followSet = g.symbolFollowSet[g.nameSymbolIdMap["E"]];
    writeln("E_followSet = ", E_followSet.toArray());
    assert(E_followSet.size() == 2);
    assert(E_followSet.contains(g.LAMBDA_ID));
    assert(E_followSet.contains(g.nameSymbolIdMap["RPAREN"]));

    auto PREFIX_followSet = g.symbolFollowSet[g.nameSymbolIdMap["PREFIX"]];
    assert(PREFIX_followSet.size() == 1);
    assert(PREFIX_followSet.contains(g.nameSymbolIdMap["LPAREN"]));

    auto TAIL_followSet = g.symbolFollowSet[g.nameSymbolIdMap["TAIL"]];
    assert(TAIL_followSet.size() == 2);
    assert(TAIL_followSet.contains(g.LAMBDA_ID));
    assert(TAIL_followSet.contains(g.nameSymbolIdMap["RPAREN"]));

    debug writeln("initSymbolFollowSet [OK]");
  }
}
