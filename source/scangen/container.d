debug import std.stdio;


class Stack(T)
{
  T[] array;

  bool empty() const
  {
    return array.length == 0;
  }

  void push(T val)
  {
    array ~= val;
  }

  T pop()
    in {
      assert(!empty());
    }
  body {
    T val = array[$ - 1];
    array.length--;
    return val;
  }
}

unittest
{
  auto s = new Stack!int();
  s.push(1);
  s.push(2);
  s.push(3);
  assert(s.pop() == 3);
  assert(s.pop() == 2);
  assert(s.pop() == 1);
  assert(s.empty());
}


class Set(T)
{
  bool[T] set;

  bool empty() const
  {
    return set.length == 0;
  }

  void add(in T elem)
  {
    set[elem] = true;
  }

  void remove(in T elem)
  {
    set.remove(elem);
  }

  bool contains(in T elem) const
  {
    return (elem in set) !is null;
  }

  size_t size() const
  {
    return set.length;
  }

  T[] toArray() const
  {
    return set.keys;
  }

  override bool opEquals (Object o) const {
    if ( auto v = cast( typeof( this ) ) o ) {
      foreach (val; toArray()) {
        if (!v.contains(val))
          return false;
      }
      foreach (val; v.toArray()) {
        if (!contains(val))
          return false;
      }
      return true;
    }
    return false;
  }
}

unittest
{
  struct Data
  {
    int a;
    int b;
  }

  auto d1 = Data(2, 3);
  auto d2 = Data(2, 3);
  auto d3 = Data(3, 4);

  auto set1 = new Set!Data();
  set1.add(d1);
  assert(set1.contains(d1));
  assert(set1.contains(d2));
  assert(!set1.contains(d3));

  auto set2 = new Set!Data();
  set2.add(d2);
  assert(set1 == set2);
  assert(set2 == set1);

  auto set3 = new Set!Data();
  set3.add(d1);
  set3.add(d3);
  assert(set1 != set3);
  assert(set3 != set1);

  debug writeln("Set [OK]");
}
