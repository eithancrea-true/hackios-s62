#include <stdint.h>
#include <string.h>
#include <strings.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#define EMMC_BLOCK 512u
#define DMA_BOUNCE 0x4000
#define BOUNCE_SIZE (1u<<20)
typedef unsigned u_int;
static struct { uintptr_t dma; } su;
static int fd; static unsigned long writes;
static void read_frandom(void*p,u_int n){ for(u_int i=0;i<n;i++) ((uint8_t*)p)[i]=rand(); }
static int emmc_read_blocks(uint64_t l,uint32_t c){ return pread(fd,(void*)(su.dma+DMA_BOUNCE),c*512,l*512)==(ssize_t)(c*512)?0:EIO; }
static int emmc_write_blocks(uint64_t l,uint32_t c){ writes+=c; printf("   [disk write %u sectors at 0x%llx]\n",c,(unsigned long long)l); return pwrite(fd,(void*)(su.dma+DMA_BOUNCE),c*512,l*512)==(ssize_t)(c*512)?0:EIO; }
#define include(x)
#include "gpt_body.c"
int main(int argc,char**argv){ su.dma=(uintptr_t)malloc(DMA_BOUNCE+BOUNCE_SIZE); fd=open(argv[1],O_RDWR); srand(1);
  int r=emmc_gpt_split(atoi(argv[2]),atoi(argv[3])); printf("result %d, sectors written %lu\n",r,writes); return r!=0; }
