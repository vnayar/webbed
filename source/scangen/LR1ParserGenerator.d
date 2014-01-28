import std.stdio;
import std.algorithm;
import std.conv;

import container;
import Grammar;


// Introduce some test data to be used for unittests.
version(unittest)
{
  Grammar g1;
  static this() {
    g1 = new Grammar();
    string[] grammarConfig =
      [
       r"# Tokens",
       r"PLUS /\+/",
       r"ID   /\w+/",
       r"LPAREN /\(/",
       r"RPAREN /\)/",
       r"= Productions =",
       r"S => E STOP",
       r"E => E PLUS T",
       r"E => T",
       r"T => ID",
       r"T => LPAREN E RPAREN"
       ];
    g1.load(grammarConfig);
    g1.initSymbolDerivesLambda();
    g1.initSymbolFirstSet();
    g1.initSymbolFollowSet();
  }

  // A more complex grammar that is LR(1) and not LR(0).
  Grammar g3;
  static this() {
    g3 = new Grammar();
    string[] grammarConfig =
      [
       r"# Tokens",
       r"PLUS /\+/",
       r"MUL /\*/",
       r"ID   /\w+/",
       r"LPAREN /\(/",
       r"RPAREN /\)/",
       r"= Productions =",
       r"S => E STOP",
       r"E => E PLUS T",
       r"E => T",
       r"T => T MUL P",
       r"T => P",
       r"P => ID",
       r"P => LPAREN E RPAREN"
       ];
    g3.load(grammarConfig);
    g3.initSymbolDerivesLambda();
    g3.initSymbolFirstSet();
    g3.initSymbolFollowSet();
  }

}

class ParserGeneratorException : Exception
{
  this(string message, int line = __LINE__, Throwable next = null)
  {
    super(message, __FILE__, line, next);
  }
}

struct Action
{
  enum Type {
    ERROR,
    ACCEPT,
    SHIFT,
    REDUCE
  }
  Type type;
  size_t productionId;  // Used with REDUCE.
}

/**
 * This parser generator is based upon the conceptual description of
 * LR parsers in Knuth (1965).  This class follows the terminology used in
 * "Crafting a Compiler with C" by Charles N. Fischer and
 * Richard J. LeBlanc, Jr.
 */
class LR1ParserGenerator
{
private:

  Grammar grammar;

  /**
   * A configuration consists of a production, and a special "dot"
   * symbol that indicates how much of the production has already
   * been matched.
   */
  struct Configuration
  {
    size_t productionId;  // The production this configuration applies to.
    // The "dot" marks how much of the production has been matched.
    size_t dotIndex;  // The index of the first unmatched symbol.
    // The symbol that may appear after the configuration.
    size_t lookAhead;

  }

  string toString(in Configuration conf) const
  {
    string str;
    auto prod = grammar.productions[conf.productionId];
    str ~= grammar.symbols[prod.symbolId].name ~ " => ";
    foreach (symbolIndex, symbolId; prod.symbolIds) {
      if (symbolIndex == conf.dotIndex)
        str ~= ". ";
      str ~= grammar.symbols[symbolId].name ~ " ";
    }
    if (conf.dotIndex == prod.symbolIds.length)
      str ~= ". ";
    str ~= ", " ~ grammar.symbols[conf.lookAhead].name;

    return str;
  }

  void print(in Configuration conf) const
  {
    auto prod = grammar.productions[conf.productionId];
    write(grammar.symbols[prod.symbolId].name, " => ");
    foreach (symbolIndex, symbolId; prod.symbolIds) {
      if (symbolIndex == conf.dotIndex)
        write(". ");
      write(grammar.symbols[symbolId].name, " ");
    }
    if (conf.dotIndex == prod.symbolIds.length)
      write(". ");
    writeln(", ", grammar.symbols[conf.lookAhead].name);
  }

  /**
   * A set of configurations who all have the same symbols matched so far.
   * That is, all symbols before the "dot" in each configuration are the same.
   */
  alias Set!Configuration ConfigurationSet;


public:
  this(Grammar grammar)
  {
    this.grammar = grammar;
  }

  /**
   * Start with a configuration set, and add to the set all other
   * configurations that can be derived by expanding non-terminal
   * symbols (productions) immediately following the dot in
   * any configuration in the configuration set.
   */
  void closure1(ConfigurationSet set)
  {
    bool isNewConf;
    do {
      isNewConf = false;
      // Check all configurations in our configuration set.
      foreach (conf; set.toArray()) {
        auto confProd = &grammar.productions[conf.productionId];
        // We want configurations of the form:  B => a . A p, l
        // where A is a production, l is the lookahead,
        // and 'a' and 'p' are strings of any symbol.
        if (conf.dotIndex >= confProd.symbolIds.length)
          continue;

        // Get the symbol just after the dot, make sure it is a production.
        auto symbolId = confProd.symbolIds[conf.dotIndex];
        if (grammar.symbols[symbolId].type != Symbol.Type.PRODUCTION)
          continue;

        // Compute the first-set of what may come after the symbolId, p l.
        debug writeln("Computing lookAheadSet of ",
                      confProd.symbolIds[conf.dotIndex + 1 .. $] ~ conf.lookAhead);
        auto lookAheadSet =
          grammar.computeFirstSet(confProd.symbolIds[conf.dotIndex + 1 .. $] ~
                                  conf.lookAhead);

        // Remember that a production symbol maps to many productions.
        foreach (productionId; grammar.symbolIdProductionIdsMap[symbolId]) {
          // A new configuration with the dot before the first symbol, with
          // each possible lookAhead.
          foreach (lookAhead; lookAheadSet.toArray()) {
            auto newConf = Configuration(productionId, 0, lookAhead);
            if (!set.contains(newConf)) {
              set.add(newConf);
              isNewConf = true;
            }
          }
        }
      }
    } while (isNewConf == true);
  }

  unittest
  {
    auto pg = new LR1ParserGenerator(g1);

    // Create ourselves a nice configuration set to play with.
    auto set = new ConfigurationSet();
    // A configuration using the first production with dot before the start.
    set.add(Configuration(0, 0, g1.LAMBDA_ID));
    debug (3) {
      writeln("==== Initial configuration set ====");
      foreach (conf; set.toArray()) {
        pg.print(conf);
      }
    }
    debug writeln("set.size() = ", set.size());
    pg.closure1(set);
    debug (3) {
      writeln("==== Closure configuration set ====");
      foreach (conf; set.toArray()) {
        pg.print(conf);
      }
    }
    debug writeln("set.size() = ", set.size());
    assert(set.size() == 9);
    // S => . E STOP, LAMBDA
    assert(set.contains(Configuration(0, 0, g1.nameSymbolIdMap["LAMBDA"])));
    // E => . E PLUS T, STOP
    assert(set.contains(Configuration(1, 0, g1.nameSymbolIdMap["STOP"])));
    // E => . E PLUS T, PLUS
    assert(set.contains(Configuration(1, 0, g1.nameSymbolIdMap["PLUS"])));
    // E => . T, STOP
    assert(set.contains(Configuration(2, 0, g1.nameSymbolIdMap["STOP"])));
    // E => . T, PLUS
    assert(set.contains(Configuration(2, 0, g1.nameSymbolIdMap["PLUS"])));
    // T => . ID, STOP
    assert(set.contains(Configuration(3, 0, g1.nameSymbolIdMap["STOP"])));
    // T => . ID, PLUS
    assert(set.contains(Configuration(3, 0, g1.nameSymbolIdMap["PLUS"])));
    // T => . LPAREN E RPAREN, STOP
    assert(set.contains(Configuration(4, 0, g1.nameSymbolIdMap["STOP"])));
    // T => . LPAREN E RPAREN, PLUS
    assert(set.contains(Configuration(4, 0, g1.nameSymbolIdMap["PLUS"])));

    debug writeln("closure1 [OK]");
  }

  /**
   * Compute the set of configurations that would be valid after the
   * provided symbol occurs.  Productions that do not match are thrown
   * out, and new productions that are possible are added in.
   */
  ConfigurationSet successor1(ConfigurationSet s, size_t symbolId)
  {
    ConfigurationSet successorSet = new ConfigurationSet();
    // Go through s adding configurations whose symbol after the
    // dot is 'symbolId'.
    foreach (conf; s.toArray()) {
      auto confProd = &grammar.productions[conf.productionId];
      // Make sure there are symbols left in the production.
      // A configuration not having a dot before symbolId is not included.
      if (conf.dotIndex < confProd.symbolIds.length &&
          confProd.symbolIds[conf.dotIndex] == symbolId) {
        auto newConf = Configuration(conf.productionId, conf.dotIndex + 1,
                                     conf.lookAhead);
        successorSet.add(newConf);
      }
    }
    // Include all the new possible productions by using closure0.
    closure1(successorSet);
    return successorSet;
  }

  unittest
  {
    debug writeln("successor1 unittest begin");
    auto pg = new LR1ParserGenerator(g1);

    // Create ourselves a nice configuration set to play with.
    auto set = new ConfigurationSet();

    // A configuration using the first production with dot before the start.
    set.add(Configuration(0, 1, g1.STOP_ID));    // S => E . STOP, STOP
    set.add(Configuration(1, 1, g1.LAMBDA_ID));  // E => E . PLUS T, LAMBDA
    set.add(Configuration(1, 1, g1.STOP_ID));    // E => E . PLUS T, STOP
    set.add(Configuration(1, 1, g1.LAMBDA_ID));  // E => E . PLUS T, LAMBDA
    debug writeln("set.size() = ", set.size());
    set = pg.successor1(set, g1.nameSymbolIdMap["PLUS"]);
    debug writeln("set.size() = ", set.size());
    assert(set.size() == 6);
    assert(set.contains(Configuration(1, 2, g1.STOP_ID)));   // E => E PLUS . T, STOP
    assert(set.contains(Configuration(1, 2, g1.LAMBDA_ID))); // E => E PLUS . T, LAMBDA
    assert(set.contains(Configuration(3, 0, g1.STOP_ID)));   // T => . ID, STOP
    assert(set.contains(Configuration(3, 0, g1.LAMBDA_ID))); // T => . ID, LAMBDA
    assert(set.contains(Configuration(4, 0, g1.STOP_ID)));   // T => . LPAREN E RPAREN, STOP
    assert(set.contains(Configuration(4, 0, g1.LAMBDA_ID))); // T => . LPAREN E RPAREN, LAMBDA
    debug writeln("successor1 [OK]");
  }

  /**
   * Characteristic Finite State Machine
   * Each state contains a ConfigurationSet, and transitions are made
   * via input symbols.
   */
  class CFSM
  {
    ConfigurationSet[] states;
    // transition[S][X] indicates the next state, if the input symbol is X
    // and the current state is S.
    size_t[][] transitions;

    invariant()
    {
      assert(states.length == transitions.length);
    }

    string toString(size_t stateId) const
    {
      auto state = states[stateId];

      string str;
      str ~= "State " ~ to!string(stateId) ~ "\n";
      str ~= "==========\n";
      // Display the configurations in this state.
      foreach (conf; state.toArray()) {
        str ~= LR1ParserGenerator.toString(conf) ~ "\n";
      }
      str ~= "\n";

      return str;
    }

    void printStates() const
    {
      foreach (stateIndex, state; states) {
        writeln("State ", stateIndex);
        writeln("==========");
        // Display the configurations in this state.
        foreach (conf; state.toArray()) {
          print(conf);
        }
        writeln();
      }
    }

    // Determine the index of a state matching a ConfigurationSet.
    // Returns:  -1 if no state matches the configuration set.
    int findStateIndex(in ConfigurationSet configurationSet) const
    {
      // First check that this state is not a duplicate of any other.
      return cast(int) countUntil(states, configurationSet);
    }

    int addState(ConfigurationSet state)
    {
      states ~= state;
      size_t[] transitionArray;
      transitionArray.length = grammar.symbols.length;
      transitions ~= transitionArray;

      return cast(int) states.length - 1;
    }
  }

  CFSM buildCFSM()
    in {
      assert(grammar.productions.length > 0);
    }
  body {
    CFSM cfsm = new CFSM();

    // State 0 is the error state in the CFSM with an empty configuration set.
    ConfigurationSet error = new ConfigurationSet();
    cfsm.addState(error);

    // State 1 is the start state in the CFSM that matches the first production.
    ConfigurationSet start = new ConfigurationSet();
    start.add(Configuration(0, 0, grammar.LAMBDA_ID));
    closure1(start);
    int startStateId = cfsm.addState(start);

    // Keep building the CFSM until there are no working states.
    auto workingStateIds = new Stack!int();
    workingStateIds.push(startStateId);
    while (!workingStateIds.empty()) {
      int stateId = workingStateIds.pop();
      // Consider the terminals (tokens) and non-terminals (productions).
      foreach (symbolId, symbol; grammar.symbols) {
        if (symbol.type != Symbol.Type.TOKEN &&
            symbol.type != Symbol.Type.PRODUCTION)
          continue;
        auto successor = successor1(cfsm.states[stateId], symbolId);
        auto newStateId = cfsm.findStateIndex(successor);
        if (newStateId == -1) {
          newStateId = cfsm.addState(successor);
          debug (3) writeln("Adding new state ", newStateId);
          workingStateIds.push(newStateId);
        }
        // Create a transition from the working state to our new state.
        cfsm.transitions[stateId][symbolId] = newStateId;
      }
    }

    return cfsm;
  }

  /**
   * Build the goto table used by the parser, that indicates what state
   * to transition to given the current state and the next token.
   */
  size_t[][] buildGotoTable(CFSM cfsm)
  {
    size_t[][] gotoTable;
    gotoTable.length = cfsm.transitions.length;
    foreach (i; 0 .. gotoTable.length) {
      gotoTable[i] = cfsm.transitions[i].dup;
    }
    return gotoTable;
  }

  unittest
  {
    auto pg = new LR1ParserGenerator(g3);
    auto cfsm = pg.buildCFSM();

    debug writeln("cfsm.states.length = ", cfsm.states.length);
    debug cfsm.printStates();
    assert(cfsm.states.length == 24);

    debug writeln("buildCFSM [OK]");

    // Now test the buildGotoTable function.
    auto gotoTable = pg.buildGotoTable(cfsm);
    assert(gotoTable.length == 24);
    size_t ID_id = g3.nameSymbolIdMap["ID"];
    size_t STOP_id = g3.nameSymbolIdMap["STOP"];
    size_t PLUS_id = g3.nameSymbolIdMap["PLUS"];
    size_t MUL_id = g3.nameSymbolIdMap["MUL"];
    size_t E_id = g3.nameSymbolIdMap["E"];

    // State 0 is the error state.
    assert(gotoTable[0][ID_id] == 0);
    assert(gotoTable[0][STOP_id] == 0);
    assert(gotoTable[0][E_id] == 0);

    // State 1 is the start state.
    //  #0  S => . E STOP
    //  #1  E => . E PLUS T
    //  #2  E => . T
    //  #3  T => . T MUL P
    //  #4  T => . P
    //  #5  P => . ID
    //  #6  P => . LPAREN E RPAREN
    size_t stateId = 1;

    // Make sure the transition on ID has:
    //   P => ID .
    assert(cfsm.states[gotoTable[stateId][ID_id]].contains(Configuration(5, 1, PLUS_id)));
    assert(cfsm.states[gotoTable[stateId][ID_id]].contains(Configuration(5, 1, MUL_id)));
    assert(cfsm.states[gotoTable[stateId][ID_id]].contains(Configuration(5, 1, STOP_id)));
    // Make sure the transition on E has:
    //   S => E . STOP
    assert(cfsm.states[gotoTable[stateId][E_id]].contains(Configuration(0, 1, g3.LAMBDA_ID)));
    // The startId has no transition on STOP.
    assert(gotoTable[stateId][STOP_id] == 0);  // The error state


    debug writeln("buildGotoTable [OK]");
  }

  /**
   * Build the action table that indicates what action to perform for
   * a given state.  Actions may be: SHIFT, ACCEPT, REDUCE, or ERROR.
   */
  Action[][] buildActionTable(CFSM cfsm)
  {
    // The action for [stateId][lookaheadSymbolId].
    Action[][] actionTable;
    actionTable.length = cfsm.states.length;
    // For each state, check for possible end conditions.
    foreach (stateId, state; cfsm.states) {
      // Remember that lookahead symbols may only be terminal symbols.
      // TODO:  Fix this so the terminal symbol count is not a magic number.
      actionTable[stateId].length = grammar.tokenInfos.length + 3;
      // Initialize each action for each lookahead to ERROR.
      foreach (i; 0 .. actionTable[stateId].length) {
        actionTable[stateId][i] = Action(Action.Type.ERROR);
      }

      // Check if a Configuration has been completed.
      foreach (conf; state.toArray()) {
        auto prod = &grammar.productions[conf.productionId];
        // We found a completed Configuration.
        if (conf.dotIndex == prod.symbolIds.length) {
          // Check to see if an action has already been set.
          if (actionTable[stateId][conf.lookAhead].type == Action.Type.ACCEPT ||
              actionTable[stateId][conf.lookAhead].type == Action.Type.SHIFT)
            throw new ParserGeneratorException(
                "Grammar is not LR1!  " ~
                to!string(actionTable[stateId][conf.lookAhead].type) ~
                "-REDUCE conflict in state " ~ to!string(stateId) ~ ".\n" ~
                "Configuration: " ~ toString(conf) ~ "\n" ~
                cfsm.toString(stateId));

          actionTable[stateId][conf.lookAhead] =
            Action(Action.Type.REDUCE, conf.productionId);
        }
        // Keep checking to look for SHIFT actions (even if an action already
        // exists, this can detect errors).
        if (conf.dotIndex < prod.symbolIds.length) {
          auto nextSymbolId = prod.symbolIds[conf.dotIndex];
          auto nextSymbolType = grammar.symbols[nextSymbolId].type;
          // Check to see if there is a production with a nonterminal after the dot.
          if (nextSymbolType == Symbol.Type.TOKEN) {
            // If there is already a shift, pass this configuration.
            if (actionTable[stateId][nextSymbolId].type == Action.Type.ACCEPT ||
                actionTable[stateId][nextSymbolId].type == Action.Type.REDUCE) {
              debug writeln("Error detected in conf:");
              debug print(conf);
              throw new ParserGeneratorException(
                  "Grammar is not LR1!  " ~
                  to!string(actionTable[stateId][nextSymbolId].type) ~
                  "-SHIFT conflict in state " ~ to!string(stateId) ~ ".\n" ~
                  "Configuration: " ~ toString(conf) ~ "\n" ~
                  cfsm.toString(stateId));
            }

            if (nextSymbolId == grammar.STOP_ID)
              actionTable[stateId][nextSymbolId] = Action(Action.Type.ACCEPT);
            else
              actionTable[stateId][nextSymbolId] = Action(Action.Type.SHIFT);
          }
        }
      }
    }
    return actionTable;
  }

  unittest
  {
    debug writeln("Building CFSM for actionTable test.");
    auto pg = new LR1ParserGenerator(g3);
    auto cfsm = pg.buildCFSM();
    debug cfsm.printStates();

    auto actionTable = pg.buildActionTable(cfsm);
    debug {
      writeln("Action Table");
      writeln("============");
      foreach (i; 0 .. actionTable[0].length) {
        write(g3.symbols[i].name, " ");
      }
      writeln();
      foreach (i, row; actionTable) {
        writeln("State ", i, ": ", row);
      }
    }

    auto ID_ID = g3.nameSymbolIdMap["ID"];
    auto E_ID = g3.nameSymbolIdMap["E"];
    auto PLUS_ID = g3.nameSymbolIdMap["PLUS"];
    auto MUL_ID = g3.nameSymbolIdMap["MUL"];

    // Find a known ConfigurationSet with ACCEPT and SHIFT actions.
    auto cs1 = new ConfigurationSet();
    cs1.add(Configuration(0, 1, g3.LAMBDA_ID)); // S => E . STOP, LAMBDA
    cs1.add(Configuration(1, 1, g3.STOP_ID));   // E => E . PLUS T, STOP
    cs1.add(Configuration(1, 1, PLUS_ID));      // E => E . PLUS T, PLUS
    auto cs1i = cfsm.findStateIndex(cs1);
    assert(cs1i != -1);
    debug writeln("Checking state ", cs1i);
    assert(actionTable[cs1i][g3.STOP_ID] == Action(Action.Type.ACCEPT));
    assert(actionTable[cs1i][PLUS_ID] == Action(Action.Type.SHIFT));
    assert(actionTable[cs1i][MUL_ID] == Action(Action.Type.ERROR));

    // Find a known configuration set with REDUCE[i] actions.
    auto cs7 = new ConfigurationSet();
    cs7.add(Configuration(2, 1, g3.STOP_ID));  // E => T ., STOP
    cs7.add(Configuration(2, 1, PLUS_ID));     // E => T ., PLUS
    cs7.add(Configuration(3, 1, g3.STOP_ID));  // T => T . MUL P, STOP
    cs7.add(Configuration(3, 1, PLUS_ID));     // T => T . MUL P, PLUS
    cs7.add(Configuration(3, 1, MUL_ID));      // T => T . MUL P, MUL
    auto cs7i = cfsm.findStateIndex(cs7);
    assert(cs7i != -1);
    debug writeln("Checking state ", cs7i);
    assert(actionTable[cs7i][PLUS_ID] == Action(Action.Type.REDUCE, 2));
    assert(actionTable[cs7i][MUL_ID] == Action(Action.Type.SHIFT));
    assert(actionTable[cs7i][ID_ID] == Action(Action.Type.ERROR));

    debug writeln("buildActionTable [OK]");
  }

}
