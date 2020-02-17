load(
    "@bazel_tools//tools/cpp:lib_cc_configure.bzl",
    "auto_configure_fail",
    "auto_configure_warning",
    "auto_configure_warning_maybe",
    "escape_string",
    "get_env_var",
    "get_starlark_list",
    "resolve_labels",
    "split_escaped",
    "which",
    "write_builtin_include_directory_paths",
)

def _field(name, value):
    """Returns properly indented top level crosstool field."""
    if type(value) == "list":
        return "\n".join(["  " + name + ": '" + v + "'" for v in value])
    elif type(value) == "string":
        return "  " + name + ": '" + value + "'"
    else:
        auto_configure_fail("Unexpected field type: " + type(value))
        return ""

def _uniq(iterable):
    """Remove duplicates from a list."""

    unique_elements = {element: None for element in iterable}
    return unique_elements.keys()

def _prepare_include_path(repo_ctx, path):
    """Resolve and sanitize include path before outputting it into the crosstool.

    Args:
      repo_ctx: repo_ctx object.
      path: an include path to be sanitized.

    Returns:
      Sanitized include path that can be written to the crosstoot. Resulting path
      is absolute if it is outside the repository and relative otherwise.
    """

    repo_root = str(repo_ctx.path("."))

    # We're on UNIX, so the path delimiter is '/'.
    repo_root += "/"
    path = str(repo_ctx.path(path))
    if path.startswith(repo_root):
        return escape_string(path[len(repo_root):])
    return escape_string(path)

def _get_value(it):
    """Convert `it` in serialized protobuf format."""
    if type(it) == "int":
        return str(it)
    elif type(it) == "bool":
        return "true" if it else "false"
    else:
        return "\"%s\"" % it

def _escaped_cplus_include_paths(repo_ctx):
    """Use ${CPLUS_INCLUDE_PATH} to compute the %-escaped list of flags for cxxflag."""
    if "CPLUS_INCLUDE_PATH" in repo_ctx.os.environ:
        result = []
        for p in repo_ctx.os.environ["CPLUS_INCLUDE_PATH"].split(":"):
            p = escape_string(str(repo_ctx.path(p)))  # Normalize the path
            result.append("-I" + p)
        return result
    else:
        return []

_INC_DIR_MARKER_BEGIN = "#include <...>"

# OSX add " (framework directory)" at the end of line, strip it.
_OSX_FRAMEWORK_SUFFIX = " (framework directory)"
_OSX_FRAMEWORK_SUFFIX_LEN = len(_OSX_FRAMEWORK_SUFFIX)

def _cxx_inc_convert(path):
    """Convert path returned by cc -E xc++ in a complete path. Doesn't %-escape the path!"""
    path = path.strip()
    if path.endswith(_OSX_FRAMEWORK_SUFFIX):
        path = path[:-_OSX_FRAMEWORK_SUFFIX_LEN].strip()
    return path

def get_escaped_cxx_inc_directories(repo_ctx, cc, lang_flag, additional_flags = []):
    """Compute the list of default %-escaped C++ include directories."""
    result = repo_ctx.execute([cc, "-E", lang_flag, "-", "-v"] + additional_flags)
    index1 = result.stderr.find(_INC_DIR_MARKER_BEGIN)
    if index1 == -1:
        return []
    index1 = result.stderr.find("\n", index1)
    if index1 == -1:
        return []
    index2 = result.stderr.rfind("\n ")
    if index2 == -1 or index2 < index1:
        return []
    index2 = result.stderr.find("\n", index2 + 1)
    if index2 == -1:
        inc_dirs = result.stderr[index1 + 1:]
    else:
        inc_dirs = result.stderr[index1 + 1:index2].strip()

    return [
        _prepare_include_path(repo_ctx, _cxx_inc_convert(p))
        for p in inc_dirs.split("\n")
    ]

def _is_compiler_option_supported(repo_ctx, cc, option):
    """Checks that `option` is supported by the C compiler. Doesn't %-escape the option."""
    result = repo_ctx.execute([
        cc,
        option,
        "-o",
        "/dev/null",
        "-c",
        str(repo_ctx.path("tools/cpp/empty.cc")),
    ])
    return result.stderr.find(option) == -1

def _is_linker_option_supported(repo_ctx, cc, option, pattern):
    """Checks that `option` is supported by the C linker. Doesn't %-escape the option."""
    result = repo_ctx.execute([
        cc,
        option,
        "-o",
        "/dev/null",
        str(repo_ctx.path("tools/cpp/empty.cc")),
    ])
    return result.stderr.find(pattern) == -1

def _find_gold_linker_path(repo_ctx, cc):
    """Checks if `gold` is supported by the C compiler.

    Args:
      repo_ctx: repo_ctx.
      cc: path to the C compiler.

    Returns:
      String to put as value to -fuse-ld= flag, or None if gold couldn't be found.
    """
    result = repo_ctx.execute([
        cc,
        str(repo_ctx.path("tools/cpp/empty.cc")),
        "-o",
        "/dev/null",
        # Some macos clang versions don't fail when setting -fuse-ld=gold, adding
        # these lines to force it to. This also means that we will not detect
        # gold when only a very old (year 2010 and older) is present.
        "-Wl,--start-lib",
        "-Wl,--end-lib",
        "-fuse-ld=gold",
        "-v",
    ])
    print(result.stderr)
    if result.return_code != 0:
        return None

    for line in result.stderr.splitlines():
        if line.find("gold") == -1:
            continue
        for flag in line.split(" "):
            if flag.find("gold") == -1:
                continue
            if flag.find("--enable-gold") > -1 or flag.find("--with-plugin-ld") > -1:
                # skip build configuration options of gcc itself
                # TODO(hlopko): Add redhat-like worker on the CI (#9392)
                continue

            # flag is '-fuse-ld=gold' for GCC or "/usr/lib/ld.gold" for Clang
            # strip space, single quote, and double quotes
            flag = flag.strip(" \"'")

            # remove -fuse-ld= from GCC output so we have only the flag value part
            flag = flag.replace("-fuse-ld=", "")
            return flag
    auto_configure_warning(
        "CC with -fuse-ld=gold returned 0, but its -v output " +
        "didn't contain 'gold', falling back to the default linker.",
    )
    return None

def _add_compiler_option_if_supported(repo_ctx, cc, option):
    """Returns `[option]` if supported, `[]` otherwise. Doesn't %-escape the option."""
    return [option] if _is_compiler_option_supported(repo_ctx, cc, option) else []

def _add_linker_option_if_supported(repo_ctx, cc, option, pattern):
    """Returns `[option]` if supported, `[]` otherwise. Doesn't %-escape the option."""
    return [option] if _is_linker_option_supported(repo_ctx, cc, option, pattern) else []

def _get_no_canonical_prefixes_opt(repo_ctx, cc):
    # If the compiler sometimes rewrites paths in the .d files without symlinks
    # (ie when they're shorter), it confuses Bazel's logic for verifying all
    # #included header files are listed as inputs to the action.

    # The '-fno-canonical-system-headers' should be enough, but clang does not
    # support it, so we also try '-no-canonical-prefixes' if first option does
    # not work.
    opt = _add_compiler_option_if_supported(
        repo_ctx,
        cc,
        "-fno-canonical-system-headers",
    )
    if len(opt) == 0:
        return _add_compiler_option_if_supported(
            repo_ctx,
            cc,
            "-no-canonical-prefixes",
        )
    return opt

def get_env(repo_ctx):
    """Convert the environment in a list of export if in Homebrew. Doesn't %-escape the result!"""
    env = repo_ctx.os.environ
    if "HOMEBREW_RUBY_PATH" in env:
        return "\n".join([
            "export %s='%s'" % (k, env[k].replace("'", "'\\''"))
            for k in env
            if k != "_" and k.find(".") == -1
        ])
    else:
        return ""

def _get_coverage_flags(repo_ctx, cfg):
    if cfg.compiler_id == "clang":
        compile_flags = '"-fprofile-instr-generate",  "-fcoverage-mapping"'
        link_flags = '"-fprofile-instr-generate"'
    else:
        # gcc requires --coverage being passed for compilation and linking
        # https://gcc.gnu.org/onlinedocs/gcc/Instrumentation-Options.html#Instrumentation-Options
        compile_flags = '"--coverage"'
        link_flags = '"--coverage"'
    return compile_flags, link_flags

def _find_my_tool(repo_ctx, cfg, tool_name, mandatory=False):
    if tool_name.startswith("/"):
        return tool_name
    tool_path = repo_ctx.which(tool_name)
    if not tool_path:
        if mandatory:
            fail("Cannot find {}; try to correct your $PATH".format(tool_name))
        else:
            tool_path = "/usr/bin/" + tool_name
    return str(tool_path)

def _find_my_tools(repo_ctx, cfg):
    ar_tool_name = {
        "mac": "libtool",
        "lnx": "ar",
    } cfg.os]
    # { <key>: ( <tool_name>, <mandatory_flag> ) }
    tools_meta = {
        "ar":      ( ar_tool_name , True ),
        "ld":      ( "ld", True ),
        "cpp":     ( cfg.compiler_cpp, True ),
        "gcc":     ( cfg.compiler, True ),
        "dwp":     ( "dwp", False ),
        "gcov":    ( "gcov", True ),
        "nm":      ( "nm", True ),
        "objcopy": ( "objcopy", False ),
        "objdump": ( "objdump", True ),
        "strip":   ( "strip", True ),
    }
    return {
        key: _find_my_tool(repo_ctx, cfg, *meta)
        for key, meta in tools_meta.items()
    }

def _wrap_compilers(repo_ctx, cfg, original_tools):
    if cfg.os != "mac":
        return original_tools
    cc_wrapper_src = {
        "mac": "@bazel_tools//tools/cpp:osx_cc_wrapper.sh.tpl",
        "lnx": "@bazel_tools//tools/cpp:linux_cc_wrapper.sh.tpl",
    } cfg.os]
    substitutions = {
        "%{cc}": original_tools["gcc"],
        # TODO: Extra environment variables may be required for
        #       some compilers, no need for gcc/clang.
        "%{env}": "",
    }
    repo_ctx.template(
        "compiler_wrapper.sh",
        Label(cc_wrapper_src),
        substitutions,
    )
    repo_ctx.template(
        "compiler_cpp_wrapper.sh",
        Label(cc_wrapper_src),
        substitutions,
    )
    wrapped_tools = {k: v for k, v in original_tools.items()}
    wrapped_tools["gcc"] = "compiler_wrapper.sh"
    wrapped_tools["cpp"] = "compiler_cpp_wrapper.sh"
    return wrapped_tools

def configure_unix_toolchain(repo_ctx, cfg):
    if cfg.os_id not in ["lnx", "mac"]:
        fail("Cannot configure Unix toolchain on {}, " +
             "only Linux and Mac supported".format(cfg.os_id))
    is_mac = cfg.os_id == "mac"

    repo_ctx.file("tools/cpp/empty.cc", "int main() { return 0; }")

    my_tool_paths = _find_my_tools(repo_ctx, cfg)
    cc = my_tool_paths["gcc"]

    my_tool_paths = _wrap_compilers(repo_ctx, cfg, my_tool_paths)

    cc_toolchain_identifier = "{}{}-{}".format cfg.os, cfg.bit, cfg.compiler)

    cxx_opts = ["-std=c++17"]
    link_opts = ["-lstdc++", "-lm"]
    link_libs = []

    gold_linker_path = _find_gold_linker_path(repo_ctx, cc)
    cc_path = repo_ctx.path(cc)
    if not str(cc_path).startswith(str(repo_ctx.path(".")) + "/"):
        # cc is outside the repository, set -B
        bin_search_flag = ["-B" + escape_string(str(cc_path.dirname))]
    else:
        # cc is inside the repository, don't set -B.
        bin_search_flag = []

    coverage_compile_flags, coverage_link_flags = _get_coverage_flags(repo_ctx, is_mac)
    builtin_include_directories = _uniq(
        get_escaped_cxx_inc_directories(repo_ctx, cc, "-xc") +
        get_escaped_cxx_inc_directories(repo_ctx, cc, "-xc++", cxx_opts) +
        get_escaped_cxx_inc_directories(
            repo_ctx,
            cc,
            "-xc",
            _get_no_canonical_prefixes_opt(repo_ctx, cc),
        ) +
        get_escaped_cxx_inc_directories(
            repo_ctx,
            cc,
            "-xc++",
            cxx_opts + _get_no_canonical_prefixes_opt(repo_ctx, cc),
        ),
    )

    write_builtin_include_directory_paths(repo_ctx, cc, builtin_include_directories)
    repo_ctx.template(
        "BUILD",
        Label("@//bazel/toolchains:unix_BUILD.tpl"),
        {
            "%{cc_toolchain_identifier}": cc_toolchain_identifier,
            "%{name}": cpu_value,
            "%{supports_param_files}": "0" if is_mac else "1",
            "%{cc_compiler_deps}": get_starlark_list([":builtin_include_directory_paths"] + (
                ["compiler_wrapper.sh", "compiler_cpp_wrapper.sh"] if is_mac else []
            )),
            "%{compiler}": escape_string(get_env_var(
                repo_ctx,
                "BAZEL_COMPILER",
                "compiler",
                False,
            )),
            "%{abi_version}": escape_string(get_env_var(
                repo_ctx,
                "ABI_VERSION",
                "local",
                False,
            )),
            "%{abi_libc_version}": escape_string(get_env_var(
                repo_ctx,
                "ABI_LIBC_VERSION",
                "local",
                False,
            )),
            "%{host_system_name}": escape_string(get_env_var(
                repo_ctx,
                "BAZEL_HOST_SYSTEM",
                "local",
                False,
            )),
            "%{target_libc}": "macosx" if is_mac else escape_string(get_env_var(
                repo_ctx,
                "BAZEL_TARGET_LIBC",
                "local",
                False,
            )),
            "%{target_cpu}": escape_string(get_env_var(
                repo_ctx,
                "BAZEL_TARGET_CPU",
                cpu_value,
                False,
            )),
            "%{target_system_name}": escape_string(get_env_var(
                repo_ctx,
                "BAZEL_TARGET_SYSTEM",
                "local",
                False,
            )),
            "%{tool_paths}": ",\n        ".join(
                ['"%s": "%s"' % (k, v) for k, v in my_tool_paths.items()],
            ),
            "%{cxx_builtin_include_directories}": get_starlark_list(builtin_include_directories),
            "%{compile_flags}": get_starlark_list(
                [
                    # Security hardening requires optimization.
                    # We need to undef it as some distributions now have it enabled by default.
                    "-U_FORTIFY_SOURCE",
                    "-fstack-protector",
                    # All warnings are enabled. Maybe enable -Werror as well?
                    "-Wall",
                    # Enable a few more warnings that aren't part of -Wall.
                ] + ((
                    _add_compiler_option_if_supported(repo_ctx, cc, "-Wthread-safety") +
                    _add_compiler_option_if_supported(repo_ctx, cc, "-Wself-assign")
                )) + (
                    # Disable problematic warnings.
                    _add_compiler_option_if_supported(repo_ctx, cc, "-Wunused-but-set-parameter") +
                    # has false positives
                    _add_compiler_option_if_supported(repo_ctx, cc, "-Wno-free-nonheap-object") +
                    # Enable coloring even if there's no attached terminal. Bazel removes the
                    # escape sequences if --nocolor is specified.
                    _add_compiler_option_if_supported(repo_ctx, cc, "-fcolor-diagnostics")
                ) + [
                    # Keep stack frames for debugging, even in opt mode.
                    "-fno-omit-frame-pointer",
                ],
            ),
            "%{cxx_flags}": get_starlark_list(cxx_opts + _escaped_cplus_include_paths(repo_ctx)),
            "%{link_flags}": get_starlark_list((
                ["-fuse-ld=" + gold_linker_path] if gold_linker_path else []
            ) + _add_linker_option_if_supported(
                repo_ctx,
                cc,
                "-Wl,-no-as-needed",
                "-no-as-needed",
            ) + _add_linker_option_if_supported(
                repo_ctx,
                cc,
                "-Wl,-z,relro,-z,now",
                "-z",
            ) + (
                [
                    "-undefined",
                    "dynamic_lookup",
                    "-headerpad_max_install_names",
                ] if is_mac else bin_search_flag + [
                    # Gold linker only? Can we enable this by default?
                    # "-Wl,--warn-execstack",
                    # "-Wl,--detect-odr-violations"
                ] + _add_compiler_option_if_supported(
                    # Have gcc return the exit code from ld.
                    repo_ctx,
                    cc,
                    "-pass-exit-codes",
                )
            ) + link_opts),
            "%{link_libs}": get_starlark_list(link_libs),
            "%{opt_compile_flags}": get_starlark_list(
                [
                    # No debug symbols.
                    # Maybe we should enable https://gcc.gnu.org/wiki/DebugFission for opt or
                    # even generally? However, that can't happen here, as it requires special
                    # handling in Bazel.
                    "-g0",

                    # Conservative choice for -O
                    # -O3 can increase binary size and even slow down the resulting binaries.
                    # Profile first and / or use FDO if you need better performance than this.
                    "-O2",

                    # Security hardening on by default.
                    # Conservative choice; -D_FORTIFY_SOURCE=2 may be unsafe in some cases.
                    "-D_FORTIFY_SOURCE=1",

                    # Disable assertions
                    "-DNDEBUG",

                    # Removal of unused code and data at link time (can this increase binary
                    # size in some cases?).
                    "-ffunction-sections",
                    "-fdata-sections",
                ],
            ),
            "%{opt_link_flags}": get_starlark_list(
                [] if is_mac else _add_linker_option_if_supported(
                    repo_ctx,
                    cc,
                    "-Wl,--gc-sections",
                    "-gc-sections",
                ),
            ),
            "%{unfiltered_compile_flags}": get_starlark_list(
                _get_no_canonical_prefixes_opt(repo_ctx, cc) + [
                    # Make C++ compilation deterministic. Use linkstamping instead of these
                    # compiler symbols.
                    "-Wno-builtin-macro-redefined",
                    "-D__DATE__=\\\"redacted\\\"",
                    "-D__TIMESTAMP__=\\\"redacted\\\"",
                    "-D__TIME__=\\\"redacted\\\"",
                ],
            ),
            "%{dbg_compile_flags}": get_starlark_list(["-g"]),
            "%{coverage_compile_flags}": coverage_compile_flags,
            "%{coverage_link_flags}": coverage_link_flags,
            "%{supports_start_end_lib}": "True" if gold_linker_path else "False",
        },
    )
