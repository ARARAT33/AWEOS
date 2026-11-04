#include "../aosin_spec.h"
#include "../../core/logging.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
void aweos_log(aweos_log_level_t level,const char *format,...) {(void)level;(void)format;}
static void write_text(const char *p,const char *v){FILE*f=fopen(p,"wb");assert(f);assert(fputs(v,f)>=0);assert(fclose(f)==0);}
static void check_text(const char*p,const char*v){char b[128]={0};FILE*f=fopen(p,"rb");assert(f);assert(fread(b,1,127,f)>0);assert(fclose(f)==0);assert(strcmp(b,v)==0);}
int main(int argc,char**argv){
 assert(argc==2);const char*r=argv[1];char out[512],fresh[512],candidate[512],root[512],db[512],meta[512],var[512],lib[512];
 assert(snprintf(out,sizeof(out),"%s/existing.pkg",r)>0);assert(snprintf(fresh,sizeof(fresh),"%s/new.pkg",r)>0);
 assert(snprintf(candidate,sizeof(candidate),"%s/candidate.pkg",r)>0);assert(snprintf(root,sizeof(root),"%s/install-root",r)>0);assert(mkdir(root,0755)==0);
 write_text(out,"preserve existing user data");assert(aosin_pkg_create(out,PKG_TYPE_ASP,"demo","1.0.0",r)==AWEOS_ERR_TRANSACTION);check_text(out,"preserve existing user data");
 assert(aosin_pkg_create(fresh,PKG_TYPE_ASP,"demo","1.0.0",r)==AWEOS_ERR_TRANSACTION);assert(access(fresh,F_OK)!=0);
 write_text(candidate,"untrusted candidate");aosin_pkg_info_t info;memset(&info,0xA5,sizeof(info));
 assert(aosin_pkg_inspect(candidate,&info)==AWEOS_ERR_VERIFY);assert(info.header.magic==0);assert(aosin_pkg_verify(candidate)==AWEOS_ERR_VERIFY);
 assert(aosin_pkg_install(candidate,root)==AWEOS_ERR_TRANSACTION);assert(snprintf(db,sizeof(db),"%s/var/lib/awepkg",root)>0);assert(access(db,F_OK)!=0);
 assert(snprintf(var,sizeof(var),"%s/var",root)>0);assert(mkdir(var,0755)==0);assert(snprintf(lib,sizeof(lib),"%s/var/lib",root)>0);assert(mkdir(lib,0755)==0);assert(mkdir(db,0755)==0);
 assert(snprintf(meta,sizeof(meta),"%s/demo.meta",db)>0);write_text(meta,"keep this metadata");assert(aosin_pkg_remove("demo",root)==AWEOS_ERR_TRANSACTION);check_text(meta,"keep this metadata");
 assert(aosin_pkg_create(NULL,PKG_TYPE_ASP,"demo","1.0.0",r)==AWEOS_ERR_INVALID_PARAM);assert(aosin_pkg_inspect(NULL,&info)==AWEOS_ERR_INVALID_PARAM);
 assert(aosin_pkg_install(NULL,root)==AWEOS_ERR_INVALID_PARAM);assert(aosin_pkg_remove(NULL,root)==AWEOS_ERR_INVALID_PARAM);assert(aosin_pkg_verify(NULL)==AWEOS_ERR_INVALID_PARAM);
 puts("PASS: AOSIN APIs fail closed and preserve existing files, package metadata, and target roots.");return 0;
}
