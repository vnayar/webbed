/**
 * A grammar consists of symbols:
 *  - terminal symbols, like tokens
 *  - non-terminal symbols, like productions
 *  - start-symbol
 *  - the productions themselves
 */
struct Symbol
{
  size_t id;
  bool terminal;
}

struct Production
{
  size_t id;
  Symbol[] symbols;
}
