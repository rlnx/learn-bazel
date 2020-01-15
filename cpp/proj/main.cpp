#include "foo.hpp"

int main(int argc, char const *argv[]) {
  proj::foo(proj::cpu_feature::avx);
  proj::foo(proj::cpu_feature::avx2);
  proj::foo(proj::cpu_feature::avx512);
  return 0;
}
