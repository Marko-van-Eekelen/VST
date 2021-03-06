#include "threads.h"
//#include <stdio.h>
#include <stdlib.h>

// Derived from Example 6-11 in
// Multithreaded Programming with Pthreads, Lewis & Berg

typedef struct request_t {int data;} request_t;

lock_t requests_lock;
int length[1];
cond_t requests_consumer, requests_producer;
request_t *buf[10];

void process(int data){ return; }

request_t *get_request(){
  request_t *request;
  request = (request_t *) malloc(sizeof(request_t));
  request->data = 1; //input
  return (request);
}

void process_request(request_t *request){
  int d = request->data;
  process(d);
  free(request);
}

void add(request_t *request){
  int len = length[0];
  buf[len] = request;
  return;
}

request_t *remove(void){
  int len = length[0];
  request_t *r = buf[len - 1];
  buf[len - 1] = NULL;
  return r;
}

void *producer(void *arg){
  request_t *request;

  while(1){
    request = get_request();
    acquire(&requests_lock);
    int len = length[0];
    while(len >= 10){
      wait(&requests_producer, &requests_lock);
      len = length[0];
    }
    add(request);
    length[0] = len + 1;
    release(&requests_lock);
    signal(&requests_consumer);
  }
}

void *consumer(void *arg){
  request_t *request;

  while(1){
    acquire(&requests_lock);
    int len = length[0];
    while(len == 0){
      wait(&requests_consumer, &requests_lock);
      len = length[0];
    }
    request = remove();
    length[0] = len - 1;
    release(&requests_lock);
    signal(&requests_producer);
    process_request(request);
  }
}

int main(void)
{
  for(int i = 0; i < 10; i++)
    buf[i] = NULL;
  length[0] = 0;
  makelock(&requests_lock);
  release(&requests_lock);
  makecond(&requests_producer);
  makecond(&requests_consumer);
  
  spawn_thread((void *)&consumer, (void *)NULL);
  acquire(&requests_lock);

  int len = length[0];
  while(len != 0){
    wait(&requests_producer, &requests_lock);
    len = length[0];
  }

  release(&requests_lock);
  spawn_thread((void *)&producer, (void *)NULL);

  while(1);
  return 0;
}
