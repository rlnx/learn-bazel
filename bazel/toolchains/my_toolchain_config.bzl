
def _impl(ctx):
    cc_toolchain_config_info = ctx.attr.toolchain_config[CcToolchainConfigInfo]
    print(cc_toolchain_config_info.proto)

    out = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(out, "Fake executable")
    # return [
    #     cc_common.create_cc_toolchain_config_info(
    #         ctx = ctx,
    #         features = features,
    #         action_configs = action_configs,
    #         artifact_name_patterns = artifact_name_patterns,
    #         cxx_builtin_include_directories = cxx_builtin_include_directories,
    #         toolchain_identifier = toolchain_identifier,
    #         host_system_name = host_system_name,
    #         target_system_name = target_system_name,
    #         target_cpu = target_cpu,
    #         target_libc = target_libc,
    #         compiler = compiler,
    #         abi_version = abi_version,
    #         abi_libc_version = abi_libc_version,
    #         tool_paths = tool_paths,
    #         make_variables = make_variables,
    #         builtin_sysroot = builtin_sysroot,
    #         cc_target_os = cc_target_os,
    #     ),
    #     DefaultInfo(
    #         executable = out,
    #     ),
    # ]

cc_toolchain_config_my = rule(
    implementation = _impl,
    attrs = {
        "toolchain_config": attr.label(),
    },
    provides = [CcToolchainConfigInfo],
    executable = True,
)
