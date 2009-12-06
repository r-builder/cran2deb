apply_lintian <- function(pkg) {
    lintian_src = file.path(lintian_dir, pkg$name)
    if (!file.exists(lintian_src)) {
        notice('no lintian overrides ', lintian_src)
        return()
    }

    # copy the lintian file
    notice('including lintian file', lintian_src)
    lintian_tgt <- pkg$debfile(paste(pkg$debname, "lintian-overrides", sep="."))
    file.copy(lintian_src, lintian_tgt)
    invisible(NULL)
}

