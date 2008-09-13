setup <- function() {
    # set up the working directory
    tmp <- tempfile('cran2deb')
    dir.create(tmp)
    return (tmp)
}

cleanup <- function(dir) {
    # remove the working directory
    unlink(dir,recursive=T)
    invisible()
}

download_pkg <- function(dir, pkgname) {
    # download pkgname into dir, and construct some metadata

    # record some basic information
    pkg <- pairlist()
    pkg$date_stamp = format(Sys.time(),'%a, %d %b %Y %H:%M:%S %z')
    pkg$name = pkgname
    pkg$repoURL = available[pkgname,'Repository']
    pkg$repo = repourl_as_debian(pkg$repoURL)
    if (!length(grep('^[A-Za-z0-9][A-Za-z0-9+.-]+$',pkg$name))) {
        fail('Cannot convert package name into a Debian name',pkg$name)
    }
    pkg$srcname = pkgname_as_debian(pkg$name,binary=F)
    pkg$debname = pkgname_as_debian(pkg$name,repo=pkg$repo)
    pkg$version <- available[pkgname,'Version']

    # see if we have already built this release and uploaded it.
    debfn <- file.path(pbuilder_results, paste(pkg$srcname, '_', pkg$version, '.orig.tar.gz', sep=''))
    pkg$need_repack = FALSE
    if (file.exists(debfn)) {
        # if so, use the existing archive. this is good for three reasons:
        # 1. it saves downloading the archive again
        # 2. the repacking performed below changes the MD5 sum of the archive
        #    which upsets some Debian archive software.
        # 3. why repack more than once?
        pkg$archive <- file.path(dir, basename(debfn))
        file.copy(debfn,pkg$archive)
        pkg$path = file.path(dir, paste(pkg$srcname ,pkg$version ,sep='-'))
    } else {
        # see if we have a local mirror in /srv/R
        use_local = FALSE
        if (pkg$repo == 'cran') {
            localfn = file.path('/srv/R/Repositories/CRAN/src/contrib',paste(pkg$name,'_',pkg$version,'.tar.gz',sep=''))
            use_local = file.exists(localfn)
        } else if (pkg$repo == 'bioc') {
            localfn = file.path('/srv/R/Repositories/Bioconductor/release/bioc/src/contrib',paste(pkg$name,'_',pkg$version,'.tar.gz',sep=''))
            use_local = file.exists(localfn)
        }

        fn <- paste(pkgname, '_', pkg$version, '.tar.gz', sep='')
        archive <- file.path(dir, fn)

        if (use_local) {
            file.copy(localfn, archive)
        } else {
            # use this instead of download.packages as it is more resilient to
            # dodgy network connections (hello BT 'OpenWorld', bad ISP)
            url <- paste(available[pkgname,'Repository'], fn, sep='/')
            # don't log the output -- we don't care!
            ret <- system(paste('curl','-o',shQuote(archive),'-m 720 --retry 5',shQuote(url)))
            if (ret != 0) {
                fail('failed to download',url)
            }
            # end of download.packages replacement
        }

        if (length(grep('\\.\\.',archive)) || normalizePath(archive) != archive) {
            fail('funny looking path',archive)
        }
        pkg$path = sub("_\\.(zip|tar\\.gz)", ""
                      ,gsub(.standard_regexps()$valid_package_version, ""
                      ,archive))
        pkg$archive = archive
        # this is not a Debian conformant archive
        pkg$need_repack = TRUE
    }
    return(pkg)
}

repack_pkg <- function(pkg) {
    # re-pack into a Debian-named archive with a Debian-named directory.
    debpath = file.path(dirname(pkg$archive)
                   ,paste(pkg$srcname
                         ,pkg$version
                         ,sep='-'))
    file.rename(pkg$path, debpath)
    pkg$path = debpath
    debarchive = file.path(dirname(pkg$archive)
                          ,paste(pkg$srcname,'_'
                                ,pkg$version,'.orig.tar.gz'
                                ,sep=''))
    wd <- getwd()
    setwd(dirname(pkg$path))
    # remove them pesky +x files
    # BUT EXCLUDE configure and cleanup
    log_system('find',shQuote(basename(pkg$path))
                ,'-type f -a '
                ,   '! \\( -name configure -o -name cleanup \\)'
                ,'-exec chmod -x {} \\;')
    # tar it all back up
    log_system('tar -czf',shQuote(debarchive),shQuote(basename(pkg$path)))
    setwd(wd)
    file.remove(pkg$archive)
    pkg$archive = debarchive
    pkg$need_repack = FALSE
    return(pkg)
}

prepare_pkg <- function(dir, pkgname) {
    # download and extract an R package named pkgname
    # OR the bundle containing pkgname

    # based loosely on library/utils/R/packages2.R::install.packages

    # first a little trick; change pkgname if pkgname is contained in a bundle
    if (!(pkgname %in% rownames(available))) {
        bundle <- r_bundle_of(pkgname)
        if (is.null(bundle)) {
            fail('package',pkgname,'is unavailable')
        }
        pkgname <- bundle
    }

    # grab the archive and some metadata
    pkg <- download_pkg(dir, pkgname)

    # now extract the archive
    if (!length(grep('\\.tar\\.gz',pkg$archive))) {
        fail('archive is not tarball')
    }
    wd <- getwd()
    setwd(dir)
    ret = log_system('tar','xzf',shQuote(pkg$archive))
    setwd(wd)
    if (ret != 0) {
        fail('Extraction of archive',pkg$archive,'failed.')
    }

    # if necessary, repack the archive into Debian-conformant format
    if (pkg$need_repack) {
        pkg <- repack_pkg(pkg)
    }
    if (!file.info(pkg$path)[,'isdir']) {
        fail(pkg$path,'is not a directory and should be.')
    }

    # extract the DESCRIPTION file, which contains much metadata
    pkg$description = read.dcf(file.path(pkg$path,'DESCRIPTION'))

    # ensure consistency of version numbers
    if ('Version' %in% names(pkg$description[1,])) {
        if (pkg$description[1,'Version'] != available[pkg$name,'Version']) {
            # should never happen since available is the basis upon which the
            # package is retrieved.
            error('available version:',available[pkg$name,'Version'])
            error('package version:',pkg$description[1,'Version'])
            fail('inconsistency between R package version and cached R version')
        }
    }

    pkg$is_bundle = 'Bundle' %in% names(pkg$description[1,])
    # note subtly of short circuit operators (no absorption)
    if ((!pkg$is_bundle && pkg$description[1,'Package'] != pkg$name) ||
        ( pkg$is_bundle && pkg$description[1,'Bundle'] != pkg$name)) {
        fail('package name mismatch')
    }
    return(pkg)
}

