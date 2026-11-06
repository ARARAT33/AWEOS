#include "aosin_spec.h"
#include "../core/logging.h"
#include <string.h>

/* AOSIN v1 previously wrote dummy payload bytes and reported a fabricated
 * empty-file digest as verification. Keep this API disabled until a real
 * bounded format, authenticated manifest, and atomic deployment exist. */
int aosin_pkg_create(const char *output_file,aosin_pkg_type_t type,const char *name,const char *version,const char *payload_dir) {
 (void)type;(void)payload_dir;
 if(!output_file||!*output_file||!name||!*name||!version||!*version)return AWEOS_ERR_INVALID_PARAM;
 LOGE("AOSIN creation disabled: v1 payload/signature format is not implemented");
 return AWEOS_ERR_TRANSACTION;
}
int aosin_pkg_inspect(const char *pkg_file,aosin_pkg_info_t *info) {
 if(!pkg_file||!*pkg_file||!info)return AWEOS_ERR_INVALID_PARAM;
 memset(info,0,sizeof(*info));
 LOGE("AOSIN inspection disabled: no authenticated manifest exists");
 return AWEOS_ERR_VERIFY;
}
int aosin_pkg_install(const char *pkg_file,const char *install_root) {
 (void)install_root;if(!pkg_file||!*pkg_file)return AWEOS_ERR_INVALID_PARAM;
 LOGE("AOSIN install disabled: no verified deployment backend exists");
 return AWEOS_ERR_TRANSACTION;
}
int aosin_pkg_remove(const char *pkg_name,const char *install_root) {
 (void)install_root;if(!pkg_name||!*pkg_name)return AWEOS_ERR_INVALID_PARAM;
 LOGE("AOSIN removal disabled: no authenticated ownership database exists");
 return AWEOS_ERR_TRANSACTION;
}
int aosin_pkg_verify(const char *pkg_file) {
 if(!pkg_file||!*pkg_file)return AWEOS_ERR_INVALID_PARAM;
 LOGE("AOSIN verification disabled: no trusted signature or payload digest exists");
 return AWEOS_ERR_VERIFY;
}
