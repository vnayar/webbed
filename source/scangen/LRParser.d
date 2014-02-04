import std.stdio;

import container;
import Scanner;
import Token;
import Grammar;
import LR1ParserGenerator;


class LRParser
{
  size_t[][] gotoTable;
  Action[][] actionTable;
  Grammar grammar;

  this(Grammar grammar, size_t[][] gotoTable, Action[][] actionTable)
  {
    this.grammar = grammar;
    this.gotoTable = gotoTable;
    this.actionTable = actionTable;
  }

  void showSyntaxError()
  {
    writeln("Syntax error detected!!!");
  }

  void cleanUpAndFinish()
  {
    writeln("Cleaning up and finishing.");
  }

  // A shift-reduce parser.
  void parse(Scanner scanner)
  {
    auto stateIdStack = new Stack!size_t();

    // Begin with a start state
    stateIdStack.push(1u);
    Token token = scanner.getToken();
    writeln("Reading token: ", token);
    while (true) {
      writeln("stateIdStack.size() = ", stateIdStack.size());
      writeln("stateIdStack.top() = ", stateIdStack.top());
      size_t stateId = stateIdStack.top();
      size_t lineNum = scanner.lineNum;
      size_t linePos = scanner.linePos;
      Action action = actionTable[stateId][token.id];

      final switch (action.type) {
      case Action.Type.ERROR:
        writeln("Syntax Error near line:", lineNum, ", pos:", linePos);
        writeln(scanner.lines[lineNum]);
        writeln(actionTable[stateId]);
        writeln(actionTable[stateId][token.id]);
        showSyntaxError();
        return;
      case Action.Type.ACCEPT:
        // The input has been correctly parsed.
        cleanUpAndFinish();
        return;
      case Action.Type.SHIFT:
        stateIdStack.push(gotoTable[stateId][token.id]);
        token = scanner.getToken();  // Get the next token.
        writeln("Reading token: ", token);
        break;
      case Action.Type.REDUCE:
        // Reduce_I:
        // Assume i-th production is X => Y1 .. Ym
        // Remove states corresponding to the RHS of
        // the production.
        writeln("Reducing production ", action.productionId);
        writeln("  ", grammar.toString(grammar.productions[action.productionId]));
        auto prod = grammar.productions[action.productionId];
        writeln(prod.symbolId, " -> len(", prod.symbolIds.length, ")");
        foreach (i; 0 .. prod.symbolIds.length) {
          stateIdStack.pop();
        }

        // Use the gotoTable to place the next stateId.
        size_t currentStateId = stateIdStack.top();
        size_t nextStateId = gotoTable[currentStateId][prod.symbolId];
        writeln("==> Transitioning to from state ", currentStateId,
                " to state ", nextStateId, " on lookAhead ",
                grammar.symbols[prod.symbolId].name);
        stateIdStack.push(nextStateId);
        break;
      }
    }
  }
}
