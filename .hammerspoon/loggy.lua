-- LogLevel - what logs make it to the console?
-- 5 ==> error, warning, info, debug, verbose
-- 4 ==> error, warning, info, debug
-- 3 ==> error, warning, info
-- 2 ==> error, warning
-- 1 ==> error
-- 0 ==> Nothing. Not even ERRORs
hs.logger.defaultLogLevel = 5
local log = hs.logger.new("loggy")
log.v("   Hello! I'm an verbose log")
log.d("       Hello! I'm an   debug log")
log.i("           Hello! I'm an    info log")
log.w("Hello! I'm an warning log")
log.e("     Hello! I'm an   error log")
