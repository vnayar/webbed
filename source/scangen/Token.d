struct Token
{
  size_t id;    // The token type.
  string text;  // The text of the token itself.
  string[] groups;
}

Token EOF_TOKEN = Token(size_t.max);

