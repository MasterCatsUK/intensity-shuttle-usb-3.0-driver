// GPL-2.0-or-later. Use the native macOS administrator authorization dialog.
#include <Security/Authorization.h>
#include <Security/AuthorizationTags.h>
#include <cstdio>
#include <cstring>
#include <sys/wait.h>
int main(int argc,char **argv) {
    if(argc!=2) return 64;
    AuthorizationRef auth=nullptr;
    OSStatus s=AuthorizationCreate(nullptr,kAuthorizationEmptyEnvironment,kAuthorizationFlagDefaults,&auth);
    if(s) return 1;
    AuthorizationItem item{kAuthorizationRightExecute,0,nullptr,0};
    AuthorizationRights rights{1,&item};
    s=AuthorizationCopyRights(auth,&rights,kAuthorizationEmptyEnvironment,
         kAuthorizationFlagInteractionAllowed|kAuthorizationFlagExtendRights|kAuthorizationFlagPreAuthorize,nullptr);
    if(s) { printf("Administrator authorization failed: %d\n",s);return 2; }
    char *args[]={argv[1],nullptr};FILE *pipe=nullptr;
    s=AuthorizationExecuteWithPrivileges(auth,"/bin/sh",kAuthorizationFlagDefaults,args,&pipe);
    if(s) { printf("Installer launch failed: %d\n",s);return 3; }
    bool ok=false;char line[1024];while(fgets(line,sizeof(line),pipe)) { fputs(line,stdout);if(strstr(line,"Shuttle audio driver installed")) ok=true; }
    fclose(pipe);AuthorizationFree(auth,kAuthorizationFlagDefaults);
    return ok?0:4;
}
