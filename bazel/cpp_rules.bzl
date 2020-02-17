def _get_dep_contexts(rule_ctx):
    dep_compilation_ctxs = []
    dep_linking_ctxs = []
    for dep in rule_ctx.attr.deps:
        dep_compilation_ctxs.append(dep[CcInfo].compilation_context)
        dep_linking_ctxs.append(dep[CcInfo].linking_context)
    return dep_compilation_ctxs, dep_linking_ctxs

def _cpp_module_impl(rule_ctx):
    cc_toolchain = rule_ctx.attr.toolchain[cc_common.CcToolchainInfo]
    feature_config = cc_common.configure_features(
        ctx = rule_ctx,
        cc_toolchain = cc_toolchain,
        requested_features = rule_ctx.features,
        unsupported_features = rule_ctx.disabled_features
    )
    dep_compilation_ctxs, dep_linking_ctxs = _get_dep_contexts(rule_ctx)
    compilation_ctx, compilation_outs = cc_common.compile(
        name = rule_ctx.label.name,
        srcs = rule_ctx.files.srcs,
        public_hdrs = rule_ctx.files.hdrs,
        actions = rule_ctx.actions,
        cc_toolchain = cc_toolchain,
        compilation_contexts = dep_compilation_ctxs,
        feature_configuration = feature_config,
    )
    linking_ctx, linking_out = cc_common.create_linking_context_from_compilation_outputs(
        name = rule_ctx.label.name,
        actions = rule_ctx.actions,
        cc_toolchain = cc_toolchain,
        feature_configuration = feature_config,
        compilation_outputs = compilation_outs,
        linking_contexts = dep_linking_ctxs,
    )
    cc_info = CcInfo(
        compilation_context = compilation_ctx,
        linking_context = linking_ctx,
    )
    files_to_build = (compilation_outs.pic_objects +
                      compilation_outs.objects)
    default_info = DefaultInfo(
        files = depset(files_to_build)
    )
    return [default_info, cc_info]

cpp_module = rule(
    implementation = _cpp_module_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
        ),
        "hdrs": attr.label_list(
            allow_files = True,
        ),
        "deps": attr.label_list(
            providers = [CcInfo],
        ),
        "toolchain": attr.label(
            default = Label("@cpp_toolchain//:toolchain"),
            providers = [cc_common.CcToolchainInfo],
        )
    },
    fragments = ["cpp"],
)
