#include <iostream>
#include <typeinfo>

#include "cpp/proj/foo.hpp"

namespace proj {

template <typename Cpu>
void foo_cpu() {
  std::cout << typeid(Cpu).name() << std::endl;
}

template void foo_cpu<_CPU_>();

} // namespace proj
