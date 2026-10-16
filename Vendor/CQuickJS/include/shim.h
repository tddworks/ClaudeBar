// Ours, not quickjs-ng's, so scripts/bump-vendor.sh never touches it: the
// values quickjs.h spells as macros, which Swift can't import.
#ifndef CQUICKJS_SHIM_H
#define CQUICKJS_SHIM_H

#include "quickjs.h"

static inline JSValue cqjs_null(void) { return JS_NULL; }
static inline JSValue cqjs_undefined(void) { return JS_UNDEFINED; }

#endif
