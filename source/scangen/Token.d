/**
 * A basic structure matching a terminal symbol in a source program.
 * The token contains data extracted from its regular expression
 * information.
 *
 * See_Also: TokenInfo
 */
struct Token
{
  size_t id;    // The token symbold ID.
  string text;  // The text of the token itself.
  string[] groups;  // Any associated match data.
}

