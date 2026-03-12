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

class AHChromiumSubprocessApp : public CefApp {
 public:
  AHChromiumSubprocessApp() = default;

 private:
  IMPLEMENT_REFCOUNTING(AHChromiumSubprocessApp);
  DISALLOW_COPY_AND_ASSIGN(AHChromiumSubprocessApp);
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
  CefRefPtr<CefApp> app = new AHChromiumSubprocessApp();
  return CefExecuteProcess(mainArgs, app, nullptr);
}
