/++
 + Utility functions for use in many modules.
 +/

import std.random : uniform;


string getRandomSalt(int length)
{
  string saltCharSet =
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  char[] salt;
  salt.length = length;
  foreach (i; 0 .. length) {
    salt[i] = saltCharSet[uniform(0, saltCharSet.length)];
  }
  return salt.idup;
}
