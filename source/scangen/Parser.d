class Parser
{
  /*
  void shiftReduceDriver()
  {
    auto stateStack = new Stack!uint();

    // Begin with a start state
    stateStack.push(0u);
    while (true) {
      uint state = stateStack.pop();
      Token token = scanner.getToken();

      switch (action[state][token]) {
      case Action.Type.ERROR:
        announce_syntax_error();
        break;
      case Action.Type.ACCEPT:
        // The input has been correctly parsed.
        clean_up_and_finish();
        return;
      case Action.Type.SHIFT:
        push(go_to[state][token]);
        token = scanner.getToken();  // Get the next token.
        break;
      case Action.Type.REDUCE:
        // Reduce_I:
        // Assume i-th production is X => Y1 .. Ym
        // Remove states corresponding to the RHS of
        // the production.
        pop(m);
        // S2 is the new stack top.
        push(got_to[S2][X]);
        break;
      }
    }
  }
  */
}
