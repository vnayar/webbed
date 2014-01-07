debug import std.stdio;
import std.algorithm;

import container;
import Grammar;


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
class LR0ParserGenerator
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
    size_t dotIndex;      // The index of the symbol just after the dot.

  }

  bool skipSymbol(ref Configuration conf, size_t symbolId)
  {
    const auto symbolIds = grammar.productions[conf.productionId].symbolIds;
    if (conf.dotIndex < symbolIds.length && symbolIds[conf.dotIndex] == symbolId) {
      conf.dotIndex += 1;
      return true;
    }
    return false;
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
  void closure0(ConfigurationSet set)
  {
    ConfigurationSet nextSet = set;
    bool isNewConf;
    do {
      isNewConf = false;
      // Check all configurations in our configuration set.
      foreach (conf; set.toArray()) {
        debug writeln("Checking conf ", conf);
        auto confProd = &grammar.productions[conf.productionId];
        if (conf.dotIndex < confProd.symbolIds.length) {
          // Get the symbol just after the dot.
          auto symbolId = confProd.symbolIds[conf.dotIndex];
          // We add new configurations if the symbol after the dot is a production.
          if (grammar.symbols[symbolId].type == Symbol.Type.PRODUCTION) {
            // Remember that a production symbol maps to many productions.
            auto productionIds = grammar.symbolIdProductionIdsMap[symbolId];
            foreach (productionId; productionIds) {
              // A new configuration with the dot before the first symbol.
              auto newConf = Configuration(productionId, 0);
              // Automatically skip LAMBDA symbols.
              while (skipSymbol(newConf, grammar.LAMBDA_ID)) {}
              if (!set.contains(newConf)) {
                set.add(newConf);
                isNewConf = true;
              }
            }
          }
        }
      }
    } while (isNewConf == true);
  }

  unittest
  {
    Grammar g = new Grammar();
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
    g.load(grammarConfig);

    auto pg = new LR0ParserGenerator(g);

    // Create ourselves a nice configuration set to play with.
    auto set = new ConfigurationSet();
    // A configuration using the first production with dot before the start.
    set.add(Configuration(0, 0));
    debug writeln("set.size() = ", set.size());
    pg.closure0(set);
    debug writeln("set.size() = ", set.size());
    assert(set.size() == 5);
    debug writeln("closure0 [OK]");
  }

  /**
   * Compute the set of configurations that would be valid after the
   * provided symbol occurs.  Productions that do not match are thrown
   * out, and new productions that are possible are added in.
   */
  ConfigurationSet successor0(ConfigurationSet s, size_t symbolId)
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
        auto newConf = Configuration(conf.productionId, conf.dotIndex + 1);
        // Automatically skip LAMBDA symbols.
        while (skipSymbol(newConf, grammar.LAMBDA_ID)) {}
        successorSet.add(newConf);
      }
    }
    // Include all the new possible productions by using closure0.
    closure0(successorSet);
    return successorSet;
  }

  unittest
  {
    Grammar g = new Grammar();
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
    g.load(grammarConfig);

    auto pg = new LR0ParserGenerator(g);

    // Create ourselves a nice configuration set to play with.
    auto set = new ConfigurationSet();
    // A configuration using the first production with dot before the start.
    set.add(Configuration(0, 1));  // S => E .STOP
    set.add(Configuration(1, 1));  // E => E .PLUS T
    debug writeln("set.size() = ", set.size());
    set = pg.successor0(set, g.nameSymbolIdMap["PLUS"]);
    debug writeln("set.size() = ", set.size());
    assert(set.size() == 3);
    assert(set.contains(Configuration(1, 2))); // E => E PLUS .T
    assert(set.contains(Configuration(3, 0))); // T => .ID
    assert(set.contains(Configuration(4, 0))); // T => .LPAREN E RPAREN
    debug writeln("successor0 [OK]");
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
          auto prod = grammar.productions[conf.productionId];
          write(grammar.symbols[prod.symbolId].name, " => ");
          foreach (symbolIndex, symbolId; prod.symbolIds) {
            if (symbolIndex == conf.dotIndex)
              write(". ");
            write(grammar.symbols[symbolId].name, " ");
          }
          if (conf.dotIndex == prod.symbolIds.length)
            write(". ");
          writeln();
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
    start.add(Configuration(grammar.productions[0].symbolId, 0));
    closure0(start);
    int startStateId = cfsm.addState(start);

    // Keep building the CFSM until there are no working states.
    auto workingStateIds = new Stack!int();
    workingStateIds.push(startStateId);
    while (!workingStateIds.empty()) {
      int stateId = workingStateIds.pop();
      // Consider the terminals (tokens) and non-terminals (productions).
      foreach (symbolId, symbol; grammar.symbols) {
        if (symbol.type != Symbol.Type.TOKEN &&
            symbol.type != Symbol.Type.PRODUCTION &&
            symbol.type != Symbol.Type.STOP)
          continue;
        writeln("checking for successor to ", stateId, " under symbol ",
                grammar.symbols[symbolId].name);
        auto successor = successor0(cfsm.states[stateId], symbolId);
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
    Grammar g = new Grammar();
    string[] grammarConfig =
      [
       r"# Tokens",
       r"ID   /\w+/",
       r"= Productions =",
       r"START => S STOP",
       r"S => ID",
       r"S => LAMBDA"
       ];
    g.load(grammarConfig);

    auto pg = new LR0ParserGenerator(g);
    auto cfsm = pg.buildCFSM();

    debug writeln("cfsm.states.length = ", cfsm.states.length);
    cfsm.printStates();
    assert(cfsm.states.length == 5);

    debug writeln("buildCFSM [OK]");

    // Now test the buildGotoTable function.
    auto gotoTable = pg.buildGotoTable(cfsm);
    assert(gotoTable.length == 5);
    size_t ID_id = g.nameSymbolIdMap["ID"];
    size_t STOP_id = g.nameSymbolIdMap["START"];
    size_t S_id = g.nameSymbolIdMap["S"];
    // State 0 is the error state.
    assert(gotoTable[0][ID_id] == 0);
    assert(gotoTable[0][STOP_id] == 0);
    assert(gotoTable[0][S_id] == 0);

    // State 1 is the start state.
    //    START => . S STOP
    //    S => . ID
    //    S => LAMBDA .

    // Make sure the transition on ID has:
    //   S => ID .
    assert(cfsm.states[gotoTable[1][ID_id]].contains(Configuration(1, 1)));
    assert(gotoTable[1][STOP_id] == 0);  // The error state
    // Make sure the transition on S has:
    //   START => S . STOP
    assert(cfsm.states[gotoTable[1][S_id]].contains(Configuration(0, 1)));

    debug writeln("buildGotoTable [OK]");

    // Grammar has a shift-reduce conflict in the initial state due to LAMBDA
    // production (which can be reduced) and presense of shiftable token.
    //auto actionTable = parser.buildActionTable(cfsm);
    //debug writeln("Action Table");
    //debug writeln("============");
    //debug writeln(actionTable);
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
          if (nextSymbolType == Symbol.Type.TOKEN ||
              nextSymbolType == Symbol.Type.STOP) {
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

}
