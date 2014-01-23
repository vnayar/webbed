import std.stdio;
import std.algorithm;

import container;
import Grammar;

version(unittest)
{
  // Introduce some test data to be used for unittests.
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

  /*
  bool skipSymbol(ref Configuration conf, size_t symbolId)
  {
    const auto symbolIds = grammar.productions[conf.productionId].symbolIds;
    if (conf.dotIndex < symbolIds.length && symbolIds[conf.dotIndex] == symbolId) {
      conf.dotIndex += 1;
      return true;
    }
    return false;
  }
  */


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
    debug writeln("Calling closure1 with set: ", set.toArray());
    do {
      isNewConf = false;
      // Check all configurations in our configuration set.
      foreach (conf; set.toArray()) {
        debug writeln("Checking conf ", conf);
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
        debug writeln("Found lookAheadSet = ", lookAheadSet.toArray());

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
    writeln("==== Initial configuration set ====");
    foreach (conf; set.toArray()) {
      pg.print(conf);
    }
    debug writeln("set.size() = ", set.size());
    pg.closure1(set);
    writeln("==== Closure configuration set ====");
    foreach (conf; set.toArray()) {
      pg.print(conf);
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
        // Automatically skip LAMBDA symbols.
        //while (skipSymbol(newConf, grammar.LAMBDA_ID)) {}
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

    // Create an error state in the CFSM with an empty configuration set.
    ConfigurationSet error = new ConfigurationSet();
    cfsm.addState(error);

    // Create a start state in the CFSM that matches the first production.
    ConfigurationSet start = new ConfigurationSet();
    debug writeln("TEST A:  grammar.productions = ", grammar.productions);
    //start.add(Configuration(grammar.productions[0].symbolId, 0));
    start.add(Configuration(0, 0));
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
          writeln("Adding new state ", newStateId);
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
    auto pg = new LR1ParserGenerator(g1);
    auto cfsm = pg.buildCFSM();

    debug writeln("cfsm.states.length = ", cfsm.states.length);
    cfsm.printStates();
    assert(cfsm.states.length == 11);

    debug writeln("buildCFSM [OK]");

    // Now test the buildGotoTable function.
    auto gotoTable = pg.buildGotoTable(cfsm);
    assert(gotoTable.length == 11);
    size_t ID_id = g1.nameSymbolIdMap["ID"];
    size_t STOP_id = g1.nameSymbolIdMap["STOP"];
    size_t E_id = g1.nameSymbolIdMap["E"];

    // State 0 is the error state.
    assert(gotoTable[0][ID_id] == 0);
    assert(gotoTable[0][STOP_id] == 0);
    assert(gotoTable[0][E_id] == 0);

    // State 1 is the start state.
    //  #0  S => . E STOP
    //  #1  E => . E PLUS T
    //  #2  E => . T
    //  #3  T => . ID
    //  #4  T => . LPAREN E RPAREN
    size_t stateId = 1;

    // Make sure the transition on ID has:
    //   T => ID .
    assert(cfsm.states[gotoTable[stateId][ID_id]].contains(Configuration(3, 1)));
    // The startId has no transition on STOP.
    assert(gotoTable[stateId][STOP_id] == 0);  // The error state
    // Make sure the transition on E has:
    //   S => E . STOP
    assert(cfsm.states[gotoTable[stateId][E_id]].contains(Configuration(0, 1)));

    debug writeln("buildGotoTable [OK]");
  }

  /**
   * Build the action table that indicates what action to perform for
   * a given state.  Actions may be: SHIFT, ACCEPT, REDUCE, or ERROR.
   */
  Action[] buildActionTable(CFSM cfsm)
  {
    Action[] actionTable;
    actionTable.length = cfsm.states.length;
    // For each state, check for possible end conditions.
    foreach (stateId, state; cfsm.states) {
      uint shiftCount = 0;
      uint reduceCount = 0;
      // Check if a Configuration has been completed.
      foreach (conf; state.toArray()) {
        auto prod = &grammar.productions[conf.productionId];
        // We found a completed Configuration.
        if (conf.dotIndex == prod.symbolIds.length) {
          if (reduceCount > 0)
            throw new ParserGeneratorException("Grammar is not LR0!  "
                                               "Reduce-Reduce conflict in "
                                               "state " ~ to!string(stateId));
          if (shiftCount > 0)
            throw new ParserGeneratorException("Grammar is not LR0!  "
                                               "Shift-Reduce conflict in "
                                               "state " ~ to!string(stateId));
          // The first production is our target.
          if (conf.productionId == 0)
            actionTable[stateId] = Action(Action.Type.ACCEPT, conf.productionId);
          else
            actionTable[stateId] = Action(Action.Type.REDUCE, conf.productionId);
          reduceCount++;
        }
        // Keep checking to make sure there are no errors.
        // Check to see if there is a production with a nonterminal.
        writeln("Checking actions for state ", stateId);
        if (conf.dotIndex < prod.symbolIds.length) {
          auto nextSymbolId = prod.symbolIds[conf.dotIndex];
          writeln("Next symbol is ", grammar.symbols[nextSymbolId]);
          auto nextSymbolType = grammar.symbols[nextSymbolId].type;
          if (nextSymbolType == Symbol.Type.TOKEN) {
            if (reduceCount > 0)
              throw new ParserGeneratorException("Grammar is not LR0!  "
                                                 "Shift-Reduce conflict in "
                                                 "state " ~ to!string(stateId));
            actionTable[stateId] = Action(Action.Type.SHIFT);
            shiftCount++;
          }
        }
      }
      // If no condition was satisfied, then the action is error.
      if (shiftCount + reduceCount == 0)
        actionTable[stateId] = Action(Action.Type.ERROR);
    }
    return actionTable;
  }

  unittest
  {
    debug writeln("Building CFSM for actionTable test.");
    auto pg = new LR1ParserGenerator(g1);
    auto cfsm = pg.buildCFSM();
    cfsm.printStates();

    // Grammar has a shift-reduce conflict in the initial state due to LAMBDA
    // production (which can be reduced) and presense of shiftable token.
    auto actionTable = pg.buildActionTable(cfsm);
    debug writeln("Action Table");
    debug writeln("============");
    debug writeln(actionTable);

    // Find 4 different states based upon the ConfigurationSet.
    auto cs1 = new ConfigurationSet();
    cs1.add(Configuration(1, 2));  // E => E PLUS . T
    cs1.add(Configuration(3, 0));  // T => . ID
    cs1.add(Configuration(4, 0));  // T => . LPAREN E RPAREN
    auto cs1i = cfsm.findStateIndex(cs1);
    assert(cs1i != -1);
    writeln("Checking state ", cs1i);
    assert(actionTable[cs1i] == Action(Action.Type.SHIFT));

    auto cs2 = new ConfigurationSet();
    cs2.add(Configuration(1, 3));  // E => E PLUS T .
    auto cs2i = cfsm.findStateIndex(cs2);
    assert(cs2i != -1);
    writeln("Checking state ", cs2i);
    assert(actionTable[cs2i] == Action(Action.Type.REDUCE, 1));

    auto cs3 = new ConfigurationSet();  // Empty set is the error state.
    auto cs3i = cfsm.findStateIndex(cs3);
    assert(cs3i != -1);
    writeln("Checking state ", cs3i);
    assert(actionTable[cs3i] == Action(Action.Type.ERROR));


    auto cs4 = new ConfigurationSet();
    cs4.add(Configuration(0, 2));  // S => E STOP .
    auto cs4i = cfsm.findStateIndex(cs4);
    assert(cs4i != -1);
    writeln("Checking state ", cs4i);
    assert(actionTable[cs4i] == Action(Action.Type.ACCEPT, 0));

    debug writeln("buildActionTable [OK]");
  }

}
