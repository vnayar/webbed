import std.algorithm : map;
import std.array : join;
import std.stdio;
import std.getopt;

import Token;
import TokenInfo;
import Grammar;
import Scanner;

/**
 * Program that reads an input file in wiki format, and converts
 * it into HTML format.
 */
void main(string[] args)
{
  string configFileName = "wiki.grammar";

  getopt(args,
         "config|c", &configFileName);  // string

  Grammar grammar = new Grammar();


  auto file = File(configFileName, "r");
  writeln("Loading grammar from file: ", configFileName);
  grammar.load(file.byLine());

  writeln("Found the following symbols:  ");
  foreach (symbolId, symbol; grammar.symbols) {
    writeln("(", symbolId, ") ", symbol.name, ":");
    writeln("  name ", symbol.name, " ==> ", grammar.nameSymbolIdMap[symbol.name]);
    if (symbol.type == Symbol.Type.PRODUCTION)
      writeln("  Productions:  ", grammar.symbolIdProductionsMap[symbolId]);
    else if (symbol.type == Symbol.Type.TOKEN)
      writeln("  Token: ", grammar.symbolIdTokenInfoMap[symbolId]);
  }

  writeln("Found the following productions:  ");
  foreach (production; grammar.productions) {
    write(production.symbolId, " ");
    write(grammar.symbols[production.symbolId].name, " => ");
    writeln(join(map!(s => grammar.symbols[s].name)(production.symbolIds), " "));
  }

  TokenInfo[] tokenInfos = grammar.tokenInfos;
  Scanner scanner = new Scanner(tokenInfos);

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
  while (!scanner.empty()) {
    token = scanner.getToken();
    writeln(tokenInfos[token.id].name, " => ", token.text);
    foreach (i, group; token.groups) {
      writeln("  Group ", i, ": ", group);
    }
  }
  writeln(token);
}
