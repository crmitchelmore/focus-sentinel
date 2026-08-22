#!/bin/zsh
# Project integrity.
#
# The Xcode project and the workspace are hand-authored source files, not generated
# output. Two things have to be true of them, and this script checks both:
#
#   1. They parse. `xcodebuild -list -workspace` resolves the workspace, the project and
#      all five local packages, or it does not.
#   2. The toolchain did not rewrite them. If a build, a test run or an Xcode.app session
#      has edited `project.pbxproj` or a shared scheme, that edit must be reverted — from
#      git, or from Appendix A of the epic plan — never committed.
#
# The gate runs this first and again last, because the stages in between are the ones that
# could provoke a rewrite.
set -u

REPO_ROOT="${0:A:h}/.."
cd "$REPO_ROOT" || exit 1

PROJECT_PATHS=(FocusSentinel.xcodeproj Focus.xcworkspace)
rc=0

print "== xcodebuild -list -workspace Focus.xcworkspace"
if ! xcodebuild -list -workspace Focus.xcworkspace; then
    print -u2 "FAIL: the workspace does not parse"
    rc=1
fi

print
print "== git diff --exit-code -- ${PROJECT_PATHS[*]}"
if ! git diff --exit-code -- "${PROJECT_PATHS[@]}"; then
    print -u2 "FAIL: the committed project or workspace was modified."
    print -u2 "      The project file is source, not output. Revert the change with"
    print -u2 "      'git checkout -- ${PROJECT_PATHS[*]}' rather than committing it."
    rc=1
fi

print
print "== git diff --cached --exit-code -- ${PROJECT_PATHS[*]}"
if ! git diff --cached --exit-code -- "${PROJECT_PATHS[@]}"; then
    print -u2 "FAIL: a modification to the project or workspace is staged."
    rc=1
fi

# `git diff` cannot see a file that was added but never tracked, and an Xcode rewrite can
# add one (a stray scheme, a settings file). Untracked-but-not-ignored content inside these
# directories is just as much a drift as a modification.
print
print "== untracked content under ${PROJECT_PATHS[*]}"
untracked=$(git ls-files --others --exclude-standard -- "${PROJECT_PATHS[@]}")
if [[ -n "$untracked" ]]; then
    print -u2 "FAIL: untracked files inside the committed project/workspace:"
    print -u2 "$untracked"
    rc=1
else
    print "none"
fi

print
if (( rc == 0 )); then
    print "PROJECT INTEGRITY OK"
else
    print -u2 "PROJECT INTEGRITY FAILED"
fi
exit $rc
