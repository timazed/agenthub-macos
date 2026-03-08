#import "ChromiumSubprocessEntry.h"

#include <cstring>

#include "include/cef_app.h"
#include "include/wrapper/cef_library_loader.h"

static bool AHChromiumIsSubprocess(int argc, char* _Nullable argv[_Nullable]) {
  for (int index = 0; index < argc; index += 1) {
    const char* argument = argv[index];
    if (!argument) {
      continue;
    }
    if (strncmp(argument, "--type=", 7) == 0) {
      return true;
    }
    if (strcmp(argument, "--type") == 0 && index + 1 < argc) {
      return true;
    }
  }
  return false;
}

class AHChromiumApp : public CefApp {
 public:
  AHChromiumApp() = default;

 private:
  IMPLEMENT_REFCOUNTING(AHChromiumApp);
  DISALLOW_COPY_AND_ASSIGN(AHChromiumApp);
};

int AHChromiumMaybeRunSubprocess(int argc, char* _Nullable argv[_Nullable]) {
  if (!AHChromiumIsSubprocess(argc, argv)) {
    return -1;
  }

  CefScopedLibraryLoader libraryLoader;
  if (!libraryLoader.LoadInHelper()) {
    return 1;
  }

  CefMainArgs mainArgs(argc, argv);
  CefRefPtr<CefApp> app = new AHChromiumApp();
  return CefExecuteProcess(mainArgs, app, nullptr);
}
