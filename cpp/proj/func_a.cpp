#include <iostream>
#include <typeinfo>
#include "cpp/proj/func_a.hpp"

namespace proj {

template <typename T>
void func_a() {
  std::cout << typeid(T).name() << std::endl;
}

template void func_a<T_>();

} // namespace proj
