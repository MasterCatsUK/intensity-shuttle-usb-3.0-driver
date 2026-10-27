// GPL-2.0-or-later. Supervise only this download's subprocess group.
#include <unistd.h>
#include <sys/wait.h>
#include <signal.h>
#include <cerrno>
#include <cstdio>
#include <chrono>
static volatile sig_atomic_t interrupted=0;
static void stop(int){interrupted=1;}
int main(int argc,char**argv){
 if(argc<2||argv[1][0]!='/')return 64;
 if(setpgid(0,0)&&getpgrp()!=getpid())return 70;
 signal(SIGTERM,stop);signal(SIGINT,stop);
 pid_t child=fork();if(child<0)return 71;
 if(!child){signal(SIGTERM,SIG_DFL);signal(SIGINT,SIG_DFL);execv(argv[1],argv+1);perror("Web video tool");_exit(72);}
 bool stopping=false;auto deadline=std::chrono::steady_clock::time_point::max();
 for(;;){
  if((interrupted||getppid()==1)&&!stopping){stopping=true;deadline=std::chrono::steady_clock::now()+std::chrono::seconds(3);kill(-getpid(),SIGTERM);}
  int status=0;pid_t done=waitpid(child,&status,WNOHANG);
  if(done==child&&!stopping)return WIFEXITED(status)?WEXITSTATUS(status):128+WTERMSIG(status);
  if(done<0&&errno!=EINTR&&!stopping)return 73;
  if(stopping&&std::chrono::steady_clock::now()>=deadline)kill(-getpid(),SIGKILL);
  usleep(50000);
 }
}
