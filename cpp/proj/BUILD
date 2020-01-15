load("//bazel:cc_rules.bzl", "cc_compile")

FUNC_A_HPP = ["func_a.hpp"]
FUNC_A_CPP = ["func_a.cpp"]

cc_compile(
  name = "func_a_custom",
  src = "func_a.cpp"
)

cc_library(
  name = "func_a_headers",
  hdrs = FUNC_A_HPP,
)

cc_library(
  name = "func_a_int",
  hdrs = FUNC_A_HPP,
  srcs = FUNC_A_CPP,
  local_defines = [ "T_=int" ],
)

cc_library(
  name = "func_a_float",
  hdrs = FUNC_A_HPP,
  srcs = FUNC_A_CPP,
  local_defines = [ "T_=float" ],
)

cc_library(
  name = "func_a_double",
  hdrs = FUNC_A_HPP,
  srcs = FUNC_A_CPP,
  local_defines = [ "T_=double" ],
)

cc_library(
  name = "func_a",
  deps = [
    ":func_a_int",
    ":func_a_float",
    ":func_a_double",
  ],
)

cc_binary(
  name = "main",
  srcs = ["main.cpp"],
  deps = [
    ":func_a_headers",
    ":func_a_custom",
  ],
)
