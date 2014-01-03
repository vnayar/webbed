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
  string configFile = "tokens.scan";

  getopt(args,
         "config|c", &configFile);  // string

  Grammar grammar = new Grammar();


  writeln("Loading grammar from file: ", configFile);
  grammar.loadFromFile(configFile);

  writeln("Found the following symbols:  ");
  foreach (name, symbolId; grammar.nameSymbolIdMap) {
    writeln(name, " --> ", grammar.symbols[symbolId]);
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
