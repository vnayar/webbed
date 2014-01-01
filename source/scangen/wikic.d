import std.stdio;
import std.getopt;

import Token;
import TokenInfo;
import TokenInfoReader;
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

  TokenInfoReader reader = new TokenInfoReader();
  TokenInfo[] tokenInfos = reader.readFile(configFile);
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
[http://somelink.com]
[http://somelink.com Some Link]
EOS";

  scanner.load(text);
  Token token;
  while ((token = scanner.getToken()) != EOF_TOKEN) {
    writeln(tokenInfos[token.id].name, " => ", token.text);
  }
  writeln(token);
}
