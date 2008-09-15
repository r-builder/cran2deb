apply_patches <- function(pkg) {
    patch_path = file.path(patch_dir, pkg$name)
    if (!file.exists(patch_path)) {
        notice('no patches in',patch_path)
        return()
    }

    # make debian/patches for simple-patchsys
    deb_patch = pkg$debfile('patches')
    if (!dir.create(deb_patch)) {
        fail('could not create patches directory', deb_patch)
    }

    # now just copy the contents of patch_path into debian/patches
    for (patch in list.files(patch_path)) {
        notice('including patch', patch)
        file.copy(file.path(patch_path, patch), deb_patch)
    }
}

