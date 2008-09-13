is_acceptable_license <- function(license) {
    # determine if license text is acceptable

    if (length(grep('^file ',license))) {
        # skip file licenses
        return(FALSE)
    }
    license <- license_text_reduce(license)
    action = db_license_override_name(license)
    if (!is.null(action)) {
        return(action)
    }
    license <- license_text_further_reduce(license)
    action = db_license_override_name(license)
    if (!is.null(action)) {
        warn('Accepting/rejecting wild license as',license,'. FIX THE PACKAGE!')
        return(action)
    }
    license <- license_text_extreme_reduce(license)
    action = db_license_override_name(license)
    if (!is.null(action)) {
        warn('Accepting/rejecting wild license as',license,'. FIX THE PACKAGE!')
        return(action)
    }
    error('Wild license',license,'did not match classic rules; rejecting')
    return(F)
}

license_text_reduce <- function(license) {
    # these reduction steps are sound for all conformant R license
    # specifications.

    # compress spaces into a single space
    license = gsub('[[:space:]]+',' ',license)
    # make all characters lower case
    license = tolower(license)
    # don't care about versions of licenses
    license = chomp(sub('\\( ?[<=>!]+ ?[0-9.-]+ ?\\)',''
                    ,sub('-[0-9.-]+','',license)))
    # remove any extra space introduced
    license = chomp(gsub('[[:space:]]+',' ',license))
    return(license)
}

license_text_further_reduce <- function(license) {
    # these reduction steps are heuristic and may lead to
    # in correct acceptances, if care is not taken.

    # uninteresting urls
    license = gsub('http://www.gnu.org/[[:alnum:]/._-]*','',license)
    license = gsub('http://www.x.org/[[:alnum:]/._-]*','',license)
    license = gsub('http://www.opensource.org/[[:alnum:]/._-]*','',license)
    # remove all punctuation
    license = gsub('[[:punct:]]+','',license)
    # remove any extra space introduced
    license = chomp(gsub('[[:space:]]+',' ',license))
    # redundant
    license = gsub('the','',license)
    license = gsub('see','',license)
    license = gsub('standard','',license)
    license = gsub('licen[sc]e','',license)
    license = gsub('(gnu )?(gpl|general public)','gpl',license)
    license = gsub('(mozilla )?(mpl|mozilla public)','mpl',license)
    # remove any extra space introduced
    license = chomp(gsub('[[:space:]]+',' ',license))
    return(license)
}

license_text_extreme_reduce <- function(license) {
    # remove everything that may or may not be a version specification
    license = gsub('(ver?sion|v)? *[0-9.-]+ *(or *(higher|later|newer|greater|above))?',''
                   ,license)
    # remove any extra space introduced
    license = chomp(gsub('[[:space:]]+',' ',license))
    return(license)
}

license_text_hash_reduce <- function(text) {
    # reduction of license text, suitable for hashing.
    return(chomp(tolower(gsub('[[:space:]]+',' ',text))))
}

get_license <- function(pkg,license) {
    license <- chomp(gsub('[[:space:]]+',' ',license))
    if (length(grep('^file ',license))) {
        if (length(grep('^file LICEN[CS]E$',license))) {
            file = gsub('file ','',license)
            path = file.path(pkg$path, file)
            if (file.exists(path)) {
                license <- license_text_reduce(readChar(path,file.info(path)$size))
            } else {
                path = file.path(pkg$path, 'inst', file)
                if (file.exists(path)) {
                    license <- license_text_reduce(readChar(path,file.info(path)$size))
                } else {
                    error('said to look at a license file but license file is missing')
                }
            }
        } else {
            error('invalid license file specification',license)
            return(NA)
        }
    }
    return(license)
}

get_license_hash <- function(pkg,license) {
    return(digest(get_license(pkg,license),algo='sha1',serialize=FALSE))
}

is_acceptable_hash_license <- function(pkg,license) {
    license_sha1 <- get_license_hash(pkg,license)
    if (is.null(license_sha1)) {
        return(FALSE)
    }
    action = db_license_override_hash(license_sha1)
    if (is.null(action)) {
        action = FALSE
    }
    if (action) {
        warn('Wild license',license,'accepted via hash',license_sha1)
    }
    return(action)
}


accept_license <- function(pkg) {
    # check the license
    if (!('License' %in% names(pkg$description[1,]))) {
        fail('package has no License: field in description!')
    }
    accept=NULL
    for (license in strsplit(chomp(pkg$description[1,'License'])
                            ,'[[:space:]]*\\|[[:space:]]*')[[1]]) {
        if (is_acceptable_license(license)) {
            accept=license
            break
        }
        if (is_acceptable_hash_license(pkg,license)) {
            accept=license
            break
        }
    }
    if (is.null(accept)) {
        fail('No acceptable license:',pkg$description[1,'License'])
    } else {
        notice('Auto-accepted license',accept)
    }
    if (accept == 'Unlimited') {
        # definition of Unlimited from ``Writing R extensions''
        accept=paste('Unlimited (no restrictions on distribution or'
                    ,'use other than those imposed by relevant laws)')
    }
    return(accept)
}
