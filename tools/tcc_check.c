#include <stdio.h>
#include <IOKit/hidsystem/IOHIDLib.h>
int main(void){
    printf("listen access: %d\n", (int)IOHIDCheckAccess(kIOHIDRequestTypeListenEvent));
    printf("post access: %d\n", (int)IOHIDCheckAccess(kIOHIDRequestTypePostEvent));
    return 0;
}
