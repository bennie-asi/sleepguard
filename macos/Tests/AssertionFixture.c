#include <IOKit/pwr_mgt/IOPMLib.h>
#include <unistd.h>
int main(void) {
 IOPMAssertionID id;
 if (IOPMAssertionCreateWithName(kIOPMAssertionTypeNoIdleSleep, kIOPMAssertionLevelOn, CFSTR("SleepGuard disposable acceptance fixture"), &id) != kIOReturnSuccess) return 1;
 while (1) pause();
}
