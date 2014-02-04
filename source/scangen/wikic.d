import std.stdio;
import std.getopt;

import Token;
import TokenInfo;
import Grammar;
import Scanner;
import LR1ParserGenerator;
import LRParser;


void printHelp()
{
  writeln(q"EOS
Program:  wikic [-h|--help] [-c|--config grammarFile]
  --config grammarFile
    Specify what grammar configuration file to load.
  --help
    If set, display this usage information and quit.
EOS");
}

/**
 * Program that reads an input file in wiki format, and converts
 * it into HTML format.
 */
void main(string[] args)
{
  string configFileName = "wiki.grammar";
  bool help = false;

  getopt(args,
         "config|c", &configFileName,  // string
         "help|h", &help);      // bool

  // Show help and quit if requested.
  if (help) {
    printHelp();
    return;
  }

  Grammar grammar = new Grammar();


  auto file = File(configFileName, "r");
  writeln("Loading grammar from file: ", configFileName);
  grammar.load(file.byLine());
  grammar.initSymbolDerivesLambda();
  grammar.initSymbolFirstSet();
  grammar.initSymbolFollowSet();


  writeln("Found the following symbols:  ");
  foreach (symbolId, symbol; grammar.symbols) {
    writeln("(", symbolId, ") ", symbol.name, ":");
    writeln("  name ", symbol.name, " ==> ", grammar.nameSymbolIdMap[symbol.name]);
    if (symbol.type == Symbol.Type.PRODUCTION)
      writeln("  Productions:  ", grammar.symbolIdProductionIdsMap[symbolId]);
    else if (symbol.type == Symbol.Type.TOKEN && symbolId in grammar.symbolIdTokenInfoIdMap)
      writeln("  Token: ", grammar.symbolIdTokenInfoIdMap[symbolId]);
  }

  writeln("Found the following productions:  ");
  foreach (production; grammar.productions) {
    writeln(grammar.toString(production));
  }

  TokenInfo[] tokenInfos = grammar.tokenInfos;
  Scanner scanner = new Scanner(tokenInfos, grammar.STOP_ID);

  string text = q"EOS
This is some sample text with ''bold'' and '''italics'''.
One newline '''''there'''''.

Two just there.
This line has <strike>strikethrough text</strike>.
== A valid LEVEL2 header ==
 == An invalid LEVEL2 header ==
== An unmatched LEVEL2 header
--- Not quite a horizontal rule.
---- Just the right length.
----- A touch over.
Some link here [http://somelink.com] with more text.
Other link here [http://somelink.com Some Link] with bacon.

EOS";


  writeln("== Scanner input ==");
  writeln(text);

  writeln("== Scanner output ==");
  scanner.load(text);
  Token token;
  do {
    token = scanner.getToken();

    writeln(grammar.symbols[token.id].name, " => ", token.text);
    writeln("  ", token);
    foreach (i, group; token.groups) {
      writeln("    Group ", i, ": ", group);
    }
  } while (token.id != grammar.STOP_ID);


  writeln("== Processing with LRParser ==");

  auto pg = new LR1ParserGenerator(grammar);
  auto cfsm = pg.buildCFSM();
  cfsm.printStates();
  auto gotoTable = pg.buildGotoTable(cfsm);
  auto actionTable = pg.buildActionTable(cfsm);

  LRParser lrParser = new LRParser(grammar, gotoTable, actionTable);
  scanner.load(text);
  lrParser.parse(scanner);
}
