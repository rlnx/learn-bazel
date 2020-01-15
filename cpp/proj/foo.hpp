#pragma once

namespace proj {

namespace cpu_dispatch {
struct avx {};
struct avx2 {};
struct avx512 {};
} // namespace cpu_dispatch

#ifndef _CPU_
#define _CPU_ proj::cpu_dispatch::avx;
#endif

enum class cpu_feature {
  avx,
  avx2,
  avx512
};

template <typename Cpu>
void foo_cpu();

inline void foo(cpu_feature feature) {
  switch (feature) {
    case cpu_feature::avx: return foo_cpu<cpu_dispatch::avx>();
    case cpu_feature::avx2: return foo_cpu<cpu_dispatch::avx2>();
    case cpu_feature::avx512: return foo_cpu<cpu_dispatch::avx512>();
  }
}

} // namespace proj
