#!/bin/bash
# Shared helpers for FacetX development builds.

facetx_repo_root() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "$script_dir/.." && pwd
}

facetx_slug() {
    printf '%s' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//'
}

facetx_detect_variant() {
    local repo="$1"
    local explicit="${2:-}"
    local branch

    if [ -n "${FACETX_VARIANT:-}" ]; then
        facetx_slug "$FACETX_VARIANT"
        return
    fi

    if [ -n "$explicit" ]; then
        facetx_slug "$explicit"
        return
    fi

    branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    if [ "$branch" = "main" ] || [ "$branch" = "master" ] || [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
        printf ''
    else
        facetx_slug "$branch"
    fi
}

facetx_app_name() {
    local variant="$1"
    if [ -n "${FACETX_APP_NAME:-}" ]; then
        printf '%s' "$FACETX_APP_NAME"
    elif [ -n "$variant" ]; then
        printf 'FacetX-%s' "$variant"
    else
        printf 'FacetX'
    fi
}

facetx_bundle_id() {
    local variant="$1"
    if [ -n "${FACETX_BUNDLE_ID:-}" ]; then
        printf '%s' "$FACETX_BUNDLE_ID"
    elif [ -n "$variant" ]; then
        printf 'com.facetx.app.dev.%s' "$variant"
    else
        printf 'com.facetx.app'
    fi
}

facetx_support_name() {
    local variant="$1"
    if [ -n "${FACETX_SUPPORT_NAME:-}" ]; then
        printf '%s' "$FACETX_SUPPORT_NAME"
    elif [ -n "$variant" ]; then
        printf 'FacetX-%s' "$variant"
    else
        printf 'FacetX'
    fi
}

facetx_sign_identity() {
    if [ -n "${FACETX_SIGN_IDENTITY:-}" ]; then
        printf '%s' "$FACETX_SIGN_IDENTITY"
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

facetx_print_summary() {
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
        echo "signing:      ad-hoc (Calendar/Reminders may ask again after rebuilds)"
    else
        echo "signing:      $sign_identity"
    fi
}
