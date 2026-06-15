#!/bin/bash
# Shared helpers for VellumX development builds.

vellumx_repo_root() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "$script_dir/../.." && pwd
}

vellumx_slug() {
    printf '%s' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//'
}

vellumx_detect_variant() {
    local repo="$1"
    local explicit="${2:-}"
    local branch

    if [ -n "${VELLUMX_VARIANT:-}" ]; then
        vellumx_slug "$VELLUMX_VARIANT"
        return
    fi

    if [ -n "$explicit" ]; then
        vellumx_slug "$explicit"
        return
    fi

    branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    if [ "$branch" = "main" ] || [ "$branch" = "master" ] || [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
        printf ''
    else
        vellumx_slug "$branch"
    fi
}

vellumx_app_name() {
    local variant="$1"
    if [ -n "${VELLUMX_APP_NAME:-}" ]; then
        printf '%s' "$VELLUMX_APP_NAME"
    elif [ -n "$variant" ]; then
        printf 'VellumX-%s' "$variant"
    else
        printf 'VellumX'
    fi
}

vellumx_bundle_id() {
    local variant="$1"
    if [ -n "${VELLUMX_BUNDLE_ID:-}" ]; then
        printf '%s' "$VELLUMX_BUNDLE_ID"
    elif [ -n "$variant" ]; then
        printf 'com.ailuras.vellumx.dev.%s' "$variant"
    else
        printf 'com.ailuras.vellumx'
    fi
}

vellumx_support_name() {
    local variant="$1"
    if [ -n "${VELLUMX_SUPPORT_NAME:-}" ]; then
        printf '%s' "$VELLUMX_SUPPORT_NAME"
    elif [ -n "$variant" ]; then
        printf 'VellumX-%s' "$variant"
    else
        printf 'VellumX'
    fi
}

vellumx_sign_identity() {
    if [ -n "${VELLUMX_SIGN_IDENTITY:-}" ]; then
        printf '%s' "$VELLUMX_SIGN_IDENTITY"
        return
    fi

    local identity
    identity="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' \
        | head -1)"

    if [ -n "$identity" ]; then
        printf '%s' "$identity"
    else
        printf '-'
    fi
}

vellumx_print_summary() {
    local config="$1"
    local variant="$2"
    local app_name="$3"
    local bundle_id="$4"
    local support_name="$5"
    local sign_identity="$6"

    echo "config:       $config"
    echo "variant:      ${variant:-<canonical>}"
    echo "app:          ${app_name}.app"
    echo "bundle id:    $bundle_id"
    echo "support dir:  ~/Library/Application Support/$support_name"
    if [ "$sign_identity" = "-" ]; then
        echo "signing:      ad-hoc (Apple Development identity not found)"
    else
        echo "signing:      $sign_identity"
    fi
}
