"Rules for working with transitions."

load("@bazel_skylib//lib:paths.bzl", "paths")

def _transition_platform_impl(settings, attr):
    if not attr.transition_enabled:
        return None
    if not settings["@rules_gitops//transitions:enable"]:
        return None
    return {"//command_line_option:platforms": str(attr.target_platform)}

# Transition from any input configuration to one that includes the
# --platforms command-line flag.
_transition_platform = transition(
    implementation = _transition_platform_impl,
    inputs = ["@rules_gitops//transitions:enable"],
    outputs = ["//command_line_option:platforms"],
)

def _platform_transition_filegroup_impl(ctx):
    files = []
    runfiles = ctx.runfiles()
    for src in ctx.attr.srcs:
        files.append(src[DefaultInfo].files)

    runfiles = runfiles.merge_all([src[DefaultInfo].default_runfiles for src in ctx.attr.srcs])
    return [DefaultInfo(
        files = depset(transitive = files),
        runfiles = runfiles,
    )]

platform_transition_filegroup = rule(
    _platform_transition_filegroup_impl,
    attrs = {
        # Required to Opt-in to the transitions feature.
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
        "target_platform": attr.label(
            doc = "The target platform to transition the srcs.",
            mandatory = True,
        ),
        "transition_enabled": attr.bool(
            doc = "Whether to enable the transition. Disable this to opt-out of the transition for go or other rules that don't need it. --@rules_gitops//transitions:enable=false will override this.",
            default = True,
        ),
        "srcs": attr.label_list(
            allow_empty = False,
            cfg = _transition_platform,
            doc = "The input to be transitioned to the target platform.",
        ),
    },
    doc = "Transitions the srcs to use the provided platform. The filegroup will contain artifacts for the target platform if .",
)

def _platform_transition_binary_impl(ctx):
    # We need to forward the DefaultInfo provider from the underlying rule.
    # Unfortunately, we can't do this directly, because Bazel requires that the executable to run
    # is actually generated by this rule, so we need to symlink to it, and generate a synthetic
    # forwarding DefaultInfo.

    result = []
    binary = ctx.attr.binary[0]

    default_info = binary[DefaultInfo]
    files = default_info.files
    new_executable = None
    original_executable = default_info.files_to_run.executable
    runfiles = default_info.default_runfiles

    if not original_executable:
        fail("Cannot transition a 'binary' that is not executable")

    new_executable_name = ctx.attr.basename if ctx.attr.basename else original_executable.basename

    # In order for the symlink to have the same basename as the original
    # executable (important in the case of proto plugins), put it in a
    # subdirectory named after the label to prevent collisions.
    new_executable = ctx.actions.declare_file(paths.join(ctx.label.name, new_executable_name))
    ctx.actions.symlink(
        output = new_executable,
        target_file = original_executable,
        is_executable = True,
    )
    files = depset(direct = [new_executable], transitive = [files])
    runfiles = runfiles.merge(ctx.runfiles([new_executable]))

    result.append(
        DefaultInfo(
            files = files,
            runfiles = runfiles,
            executable = new_executable,
        ),
    )

    return result

platform_transition_binary = rule(
    implementation = _platform_transition_binary_impl,
    attrs = {
        "basename": attr.string(),
        "binary": attr.label(allow_files = True, cfg = _transition_platform),
        "target_platform": attr.label(
            doc = "The target platform to transition the binary.",
            mandatory = True,
        ),
        "transition_enabled": attr.bool(
            doc = "Whether to enable the transition. Disable this to opt-out of the transition for go or other rules that don't need it. --@rules_gitops//transitions:enable=false will override this.",
            default = True,
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    executable = True,
    doc = "Transitions the binary to use the provided platform.",
)
