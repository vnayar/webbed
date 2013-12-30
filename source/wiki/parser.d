import std.conv;
import std.stdio;

import scanner;


class ParseException : Exception
{
  this(string message, string file = __FILE__, int line = __LINE__, Throwable next = null)
  {
    super(message, file, line, next);
  }
}

class Parser
{
  Scanner scanner;

  this(Scanner scanner)
  {
    this.scanner = scanner;
  }

  void match(Token.Type type)
  {
    Token token = scanner.getToken();
    if (token.type != type)
      throw new ParseException("Match Failure:  Found " ~
                               to!string(token.type) ~
                               ", Expected " ~ to!string(type));
  }

  unittest
  {
    string text = q"EOS
== Hello
----
EOS";
    Scanner scanner = new Scanner(text);
    Parser parser = new Parser(scanner);
    parser.match(Token.Type.LEVEL2_OPEN);
    parser.match(Token.Type.TEXT);
    parser.match(Token.Type.HORIZONTAL_RULE);
    parser.match(Token.Type.SCAN_EOF);

    bool foundException = false;
    try {
      parser.match(Token.Type.LEVEL3_OPEN);
    }
    catch (ParseException e) {
      debug writeln(e);
      foundException = true;
    }
    assert(foundException);
  }

  void parse() {
    bool isItalic = false;
    bool isBold = false;
    for (Token token = scanner.getToken();
         token.type != Token.Type.SCAN_EOF;
         token = scanner.getToken()) {
      switch (token.type) {
      case Token.Type.TEXT:
        write(token.text);
        break;
      case Token.Type.ITALIC:
        write(!isItalic ? "<i>" : "</i>");
        isItalic = !isItalic;
        break;
      case Token.Type.BOLD:
        write(!isBold ? "<b>" : "</b>");
        isBold = !isBold;
        break;
      case Token.Type.BOLD_ITALIC:
        if (isBold != isItalic)
          throw new ParseException("Using bold-italic when bold " ~
                                   "or italic already set!");
        if (!isBold || !isItalic)
          write("<b><i>");
        else
          write("</b></i>");
        isBold = !isBold;
        isItalic = !isItalic;
        break;
      case Token.Type.TAG_OPEN:
        if (token.text == "s" || token.text == "strike")
          write("<" ~ token.text ~ ">");
        else
          throw new ParseException("Unsupported tag '" ~ token.text ~ "'");
        break;
      case Token.Type.TAG_CLOSE:
        if (token.text == "s" || token.text == "strike")
          write("</" ~ token.text ~ ">");
        else
          throw new ParseException("Unsupported tag '" ~ token.text ~ "'");
        break;
      case Token.Type.LEVEL2_OPEN:
        write("\n<h2>");
        break;
      case Token.Type.LEVEL2_CLOSE:
        write("</h2>\n");
        break;
      case Token.Type.LEVEL3_OPEN:
        write("\n<h3>");
        break;
      case Token.Type.LEVEL3_CLOSE:
        write("</h3>\n");
        break;
      case Token.Type.LEVEL4_OPEN:
        write("\n<h4>");
        break;
      case Token.Type.LEVEL4_CLOSE:
        write("</h4>\n");
        break;
      case Token.Type.HORIZONTAL_RULE:
        write("\n<hr/>\n");
        break;
      case Token.Type.BREAK:
        write("\n<br/>\n");
        break;
      case Token.Type.LINK_START:
        write("<a href=\"");
        token = scanner.getToken();
        if (token.type != Token.Type.TEXT)
          throw new ParseException("Link must contain URL.");
        write(token.text, "\">");
        break;
      case Token.Type.LINK_END:
        write("</a>");
        break;
      default:
        throw new ParseException("Unrecognized token type " ~
                                 to!string(token.type));
      }
    }
  }

  unittest
  {
    debug writeln("==== unittest parser.d: Parser.parse() ====");
    string text = q"EOS
This is some sample text with ''italics'' and '''bold'''.
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
    Scanner scanner = new Scanner(text);
    Parser parser = new Parser(scanner);

    bool foundException = false;
    try {
      parser.parse();
    }
    catch (ParseException e) {
      debug writeln(e);
    }
  }

}
