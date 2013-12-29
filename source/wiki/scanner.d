import std.stdio;
import std.ascii;
import std.algorithm;


struct Token {
  enum Type {
    SCAN_EOF,         // End of file.
    TEXT,             // Generic text content.
    ITALIC,           // Italic start/end token.
    BOLD,             // Bold start/end token.
    BOLD_ITALIC,      // Bold & Italic start/end token.
    TAG_OPEN,         // HTML-like tag open (e.g. <strike>).
    TAG_CLOSE,        // HTML-like tag close (e.g. </strike>).
    LEVEL2_OPEN,      // Header level.
    LEVEL2_CLOSE,
    LEVEL3_OPEN,      // Header level.
    LEVEL3_CLOSE,
    LEVEL4_OPEN,      // Header level.
    LEVEL4_CLOSE,
    HORIZONTAL_RULE,  // Horizontal rule.
    BULLET_LIST1,     // Bulleted list.
    BULLET_LIST2,     // Bulleted list.
    BULLET_LIST3,     // Bulleted list.
    NUMBER_LIST1,     // Numbered list.
    NUMBER_LIST2,     // Numbered list.
    NUMBER_LIST3,     // Numbered list.
    BREAK,            // Line-break or paragraph separator.
    LINK_START,       // Start of link.
    LINK_END          // The end of the link section.
  };

  Type type;          // The token type.
  //int param;          // Any numerical parameter, e.g. BULLET_LIST depth.
  string text;        // The text of the token itself.
}

class Scanner
{
  immutable string TOKEN_START_CHARS = "<:;#*-='[]" ~ newline;

  enum State {
    LINE_START,
    LINE
  }

  State state;
  size_t inputPos;
  string input;

  this(string input)
  {
    this.input = input;
    this.inputPos = 0;
    this.state = State.LINE_START;
  }

  char getChar()
    in {
      assert(inputPos + 1 <= input.length);
    }
  body {
    return input[inputPos++];
  }

  void skipChar(int num=1)
    in {
      assert(inputPos + num <= input.length);
    }
  body {
    inputPos += num;
  }

  void ungetChar()
    in {
      assert(inputPos > 0);
    }
  body {
    inputPos--;
  }

  bool hasInput() {
    return inputPos != input.length;
  }

  Token getToken()
  {
    bool done = false;
    Token token = Token(Token.Type.SCAN_EOF, "");
    size_t inputStartPos = inputPos;

    while (!done && hasInput()) {
      char c = getChar();
      if (isWhite(c)) {
        inputStartPos = inputPos;  // Ignore white space.
        // Check for newline, some tokens are context sensitive.
        if (input[inputPos - 1 .. inputPos - 1 + newline.length] == newline) {
          skipChar(newline.length - 1);
          if (state == State.LINE_START) {
            token.type = Token.Type.BREAK;
            done = true;
          }
          state = State.LINE_START;
          continue;
        }
      }
      // Link related tokens.
      else if (c == '[') {
        token.text = input[inputStartPos .. inputPos];
        token.type = Token.Type.LINK_START;
        done = true;
      }
      else if (c == ']') {
        token.text = input[inputStartPos .. inputPos];
        token.type = Token.Type.LINK_END;
        done = true;
      }
      // 4 dashes at the start of a line make a horizontal rule.
      else if (c == '-' && state == State.LINE_START) {
        int count = 1;
        for (c = getChar(); hasInput() && c == '-'; c = getChar()) {
          count++;
        }
        ungetChar();
        token.text = input[inputStartPos .. inputPos];
        token.type = (count >= 4) ? Token.Type.HORIZONTAL_RULE : Token.Type.TEXT;
        done = true;
      }
      // Angle brackets indicate HTML-like tags.
      else if (c == '<') {
        c = getChar();

        if (c != '/') {
          token.type = Token.Type.TAG_OPEN;
          ungetChar();
        }
        else
          token.type = Token.Type.TAG_CLOSE;
        inputStartPos = inputPos;
        for (c = getChar(); hasInput() && c != '>'; c = getChar()) {}
        token.text = input[inputStartPos .. inputPos-1];
        done = true;
      }
      // Equal symbols indicate different levels of headers.
      else if (c == '=') {
        int level = 1;
        for (c = getChar(); hasInput() && c == '='; c = getChar()) {
          level++;
        }
        ungetChar();  // THe last char wasn't a match, so rewind.
        if (state == State.LINE_START) {
          switch (level) {
          case 2:
            token.type = Token.Type.LEVEL2_OPEN;
            break;
          case 3:
            token.type = Token.Type.LEVEL3_OPEN;
            break;
          case 4:
            token.type = Token.Type.LEVEL4_OPEN;
          default:
            token.type = Token.Type.TEXT;
          }
        }
        else {
          switch (level) {
          case 2:
            token.type = Token.Type.LEVEL2_CLOSE;
            break;
          case 3:
            token.type = Token.Type.LEVEL3_CLOSE;
            break;
          case 4:
            token.type = Token.Type.LEVEL4_CLOSE;
          default:
            token.type = Token.Type.TEXT;
          }
        }
        token.text = input[inputStartPos .. inputPos];
        done = true;
      }
      // Single quotes are used for italic, bold, or both.
      else if (c == '\'') {
        int count = 1;
        for (c = getChar(); hasInput() && c == '\''; c = getChar()) {
          count++;
        }
        ungetChar();  // The last char wasn't a match, so rewind.
        switch (count) {
        case 2:
          token.type = Token.Type.ITALIC;
          break;
        case 3:
          token.type = Token.Type.BOLD;
          break;
        case 5:
          token.type = Token.Type.BOLD_ITALIC;
          break;
        default:
          token.type = Token.Type.TEXT;
        }
        token.text = input[inputStartPos .. inputPos];
        done = true;
      }
      // A generic text token.
      else {
        token.type = Token.Type.TEXT;
        // Make sure the next character isn't a different token.
        for (c = getChar(); hasInput() &&
               find(TOKEN_START_CHARS, c).length == 0; c = getChar()) { }
        ungetChar();  // The last char might be a different token.
        token.text = input[inputStartPos .. inputPos];
        done = true;
      }

      // If we got here (not a newline) then we are no longer at line start.
      state = State.LINE;
    }
    return token;
  }
}

unittest
{
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
  writeln("---- Input Text ----");
  writeln(text);
  writeln("---- Scanning ----");
  Scanner scanner = new Scanner(text);
  Token token;
  do {
    token = scanner.getToken();
    writeln(token);
  } while (token.type != Token.Type.SCAN_EOF);
}

