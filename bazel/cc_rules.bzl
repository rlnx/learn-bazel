load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")

def _define_by_cpu(cpu):
    return "_CPU_=proj::cpu_dispatch::" + cpu

def _compile(name, ctx, feature_configuration, cc_toolchain, local_defines=[]):
    compilation_ctx, compilation_out = cc_common.compile(
        name = name,
        actions = ctx.actions,
        cc_toolchain = cc_toolchain,
        feature_configuration = feature_configuration,
        srcs = ctx.files.srcs,
        public_hdrs = ctx.files.hdrs,
        local_defines = local_defines,
    )
    return compilation_ctx, compilation_out

def _compile_multicpu(name, ctx, feature_configuration, cc_toolchain):
    compilation_ctxs = []
    compilation_outs = []
    for cpu in ctx.attr.cpus:
        name = name + '_' + cpu
        local_compilation_ctx, local_compilation_out = _compile(
            name,
            ctx,
            feature_configuration,
            cc_toolchain,
            local_defines = [_define_by_cpu(cpu)]
        )
        compilation_ctxs.append(local_compilation_ctx)
        compilation_outs.append(local_compilation_out)
    return compilation_ctxs, compilation_outs

def _create_cc_info_from_multiple_compilation_contexts(compilation_ctxs, linking_ctx):
    cc_infos = []
    for cctx in compilation_ctxs:
        local_cc_info = CcInfo(
            compilation_context = cctx,
            linking_context = linking_ctx
        )
        cc_infos.append(local_cc_info)
    return cc_common.merge_cc_infos(cc_infos=cc_infos)

def _cc_multicpu_library_impl(ctx):
    cc_toolchain = find_cpp_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )
    compilation_ctxs, compilation_outs = _compile_multicpu(
        name = ctx.label.name,
        ctx = ctx,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain
    )
    merged_compilation_outs = cc_common.merge_compilation_outputs(
        compilation_outputs = compilation_outs
    )
    linking_ctx, linking_out = cc_common.create_linking_context_from_compilation_outputs(
        name = ctx.label.name,
        actions = ctx.actions,
        cc_toolchain = cc_toolchain,
        feature_configuration = feature_configuration,
        compilation_outputs = merged_compilation_outs,
    )
    files_to_build = (merged_compilation_outs.pic_objects +
                      merged_compilation_outs.objects)
    cc_info = _create_cc_info_from_multiple_compilation_contexts(
        compilation_ctxs,
        linking_ctx
    )
    default_info = DefaultInfo(
        files = depset(files_to_build)
    )
    return [default_info, cc_info]

cc_multicpu_library = rule(
    implementation = _cc_multicpu_library_impl,
    attrs = {
        "srcs": attr.label_list(allow_files=True, mandatory=True),
        "hdrs": attr.label_list(allow_files=True),
        "cpus": attr.string_list(default=["avx"]),
        "_cc_toolchain": attr.label(
            default = Label("@bazel_tools//tools/cpp:current_cc_toolchain")
        ),
    },
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    fragments = ["cpp"],
)
