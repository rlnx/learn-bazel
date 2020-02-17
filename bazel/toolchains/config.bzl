load("@//bazel/toolchains:unix_config.bzl", "configure_unix_toolchain")

def _detect_platform(repo_ctx):
    # TODO: Check whether $MY_PLAT matches actual OS
    # TODO: Check whether $MY_COMPILER is supported
    # TODO: Check $MY_PLAT format
    return struct(
        os = repo_ctx.os.environ["MY_PLAT"][:3],
        bit = repo_ctx.os.environ["MY_PLAT"][3:],
        compiler = repo_ctx.os.environ["MY_COMPILER"],
        # TODO: Detect appropriate C++ compiler name
        compiler_cpp = repo_ctx.os.environ["MY_COMPILER"] + "++",
    )

def _configure_toolchain(repo_ctx, platform):
    if platform.os == "mac":
        configure_unix_toolchain(repo_ctx, platform)
    else:
        fail("Cannot configure toolchain for platform '{}''".format(platform))

def _my_cpp_toolchain_impl(repo_ctx):
    platform = _detect_platform(repo_ctx)
    _configure_toolchain(repo_ctx, platform)

my_cpp_toolchain = repository_rule(
    implementation = _my_cpp_toolchain_impl,
    environ = [
        "MY_PLAT",
        "MY_COMPILER"
    ],
)
