iterate <- function(xs,z,fun) {
    y <- z
    for (x in xs)
        y <- fun(y,x)
    return(y)
}

chomp <- function(x) {
    # remove leading and trailing spaces
    return(sub('^[[:space:]]+','',sub('[[:space:]]+$','',x)))
}

host_arch <- function() {
    # return the host system architecture
    system('dpkg-architecture -qDEB_HOST_ARCH',intern=T)
}

err <- function(...) {
    error(...)
    exit()
}

exit <- function() {
    q(save='no')
}
