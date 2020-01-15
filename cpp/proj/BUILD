load("//bazel:cc_rules.bzl", "cc_multicpu_library")

cc_multicpu_library(
  name = "foo",
  hdrs = ["foo.hpp"],
  srcs = ["foo.cpp"],
  cpus = ["avx", "avx2", "avx512"]
)

cc_binary(
  name = "main",
  srcs = ["main.cpp"],
  deps = [
    ":foo",
  ],
)
