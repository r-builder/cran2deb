version_new <- function(rver,debian_revision=1, debian_epoch=db_get_base_epoch()) {
    # generate a string representation of the Debian version of an
    # R version of a package
    pkgver = rver

    # ``Writing R extensions'' says that the version consists of at least two
    # non-negative integers, separated by . or -
    if (!length(grep('^([0-9]+[.-])+[0-9]+$',rver))) {
        fail('Not a valid R package version',rver)
    }

    # Debian policy says that an upstream version should start with a digit and
    # may only contain ASCII alphanumerics and '.+-:~'
    if (!length(grep('^[0-9][A-Za-z0-9.+:~-]*$',rver))) {
        fail('R package version',rver
                  ,'does not obviously translate into a valid Debian version.')
    }

    # if rver contains a : then the Debian version must also have a colon
    if (debian_epoch == 0 && length(grep(':',pkgver)))
        debian_epoch = 1

    # if the epoch is non-zero then include it
    if (debian_epoch != 0)
        pkgver = paste(debian_epoch,':',pkgver,sep='')

    # always add the '-1' Debian release; nothing is lost and rarely will R
    # packages be Debian packages without modification.
    return(paste(pkgver,'-',debian_revision,version_suffix,version_suffix_step,sep=''))
}

version_epoch <- function(pkgver) {
    # return the Debian epoch of a Debian package version
    if (!length(grep(':',pkgver)))
        return(0)
    return(as.integer(sub('^([0-9]+):.*$','\\1',pkgver)))
}
# version_epoch . version_new(x,y) = id
# version_epoch(version_new(x,y)) = base_epoch

version_revision <- function(pkgver) {
    # return the Debian revision of a Debian package version
    return(as.integer(sub(paste('.*-([0-9]+)(',version_suffix,'[0-9]+)?$',sep=''),'\\1',pkgver)))
}
# version_revision . version_new(x) = id
# version_revision(version_new(x)) = 1

version_upstream <- function(pkgver) {
    # return the upstream version of a Debian package version
    return(sub('-[a-zA-Z0-9+.~]+$','',sub('^[0-9]+:','',pkgver)))
}
# version_upstream . version_new = id

version_update <- function(rver, prev_pkgver, prev_success) {
    # return the next debian package version
    prev_rver <- version_upstream(prev_pkgver)
    if (prev_rver == rver) {
        # increment the Debian revision if the previous build was successful
        inc = 0
        if (prev_success) {
            inc = 1
        }
        return(version_new(rver
                          ,debian_revision = version_revision(prev_pkgver)+inc
                          ,debian_epoch    = version_epoch(prev_pkgver)
                          ))
    }
    # new release
    # TODO: implement Debian ordering over version and then autoincrement
    #       Debian epoch when upstream version does not increment.
    return(version_new(rver
                      ,debian_epoch = version_epoch(prev_pkgver)
                      ))
}

new_build_version <- function(pkgname) {
    if (!(pkgname %in% rownames(available))) {
        bundle <- r_bundle_of(pkgname)
        if (is.null(bundle)) {
            fail('tried to discover new version of',pkgname,'but it does not appear to be available')
        }
        name <- bundle
    }
    db_ver <- db_latest_build_version(pkgname)
    db_succ <- db_latest_build_status(pkgname)[[1]]
    latest_r_ver <- available[pkgname,'Version']
    if (!is.null(db_ver)) {
        return(version_update(latest_r_ver, db_ver, db_succ))
    }
    return(version_new(latest_r_ver))
}

