repourl_as_debian <- function(url) {
    # map the url to a repository onto its name in debian package naming
    if (length(grep('cran',url))) {
        return('cran')
    } else if (length(grep('bioc',url))) {
        return('bioc')
    } else if (length(grep('omegahat',url))) {
        return('omegahat')
    } else if (length(grep('rforge',url))) {
        return('rforge')
    }
    fail('unknown repository',url)
}

pkgname_as_debian <- function(name, repopref=NULL, version=NULL, binary=T, build=F) {
    # generate the debian package name corresponding to the R package name
    if (name %in% base_pkgs) {
        name = 'R'
    }
    if (name == 'R') {
        # R is special.
        if (binary) {
            if (build) {
                debname='r-base-dev'
            } else {
                debname='r-base-core'
            }
        } else {
            debname='R'
        }
    } else {
        # XXX: data.frame rownames are unique, so always override repopref for
        #      now.
        debname = tolower(name)
        if (binary) {
            if (name %in% rownames(available)) {
#                repopref <- tolower(repourl_as_debian(available[name,'Repository']))
				 repopref <- tolower(repourl_as_debian(available[tolower(row.names(available))==tolower(name),'Repository']))
            } else if (is.null(repopref)) {
                repopref <- 'unknown'
            }
            debname = paste('r',repopref,debname,sep='-')
        }
    }
    if (!is.null(version) && length(version) > 1) {
        debname = paste(debname,' (',version,')',sep='')
    }
    return(debname)
}

