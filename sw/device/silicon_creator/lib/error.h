// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef OPENTITAN_SW_DEVICE_SILICON_CREATOR_LIB_ERROR_H_
#define OPENTITAN_SW_DEVICE_SILICON_CREATOR_LIB_ERROR_H_

#include "sw/device/lib/base/bitfield.h"

#define USING_ABSL_STATUS
#include "sw/device/silicon_creator/lib/absl_status.h"
#undef USING_ABSL_STATUS

#ifdef __cplusplus
extern "C" {
#endif

/**
 * List of modules which can produce errors.
 *
 * Choose a two-letter identifier for each module and encode the module
 * identifier the concatenated ASCII representation of those letters.
 */
enum module_ {
  kModuleUnknown = 0,
  kModuleAlertHandler = 0x4148,  // ASCII "AH".
  kModuleUart = 0x4155,          // ASCII "UA".
  kModuleHmac = 0x4d48,          // ASCII "HM".
  kModuleSigverify = 0x5653,     // ASCII "SV".
  kModuleKeymgr = 0x4d4b,        // ASCII "KM".
  kModuleManifest = 0x414d,      // ASCII "MA".
  kModuleMaskRom = 0x524d,       // ASCII "MR".
  kModuleRomextimage = 0x4552,   // ASCII "RE".
  kModuleInterrupt = 0x5249,     // ASCII "IR".
  kModuleEpmp = 0x5045,          // ASCII "EP",
  kModuleOtp = 0x504f,           // ASCII "OP".
  kModuleOtbn = 0x4e42,          // ASCII "BN".
};

/**
 * Field definitions for the different fields of the error word.
 */
#define ROM_ERROR_FIELD_ERROR ((bitfield_field32_t){.mask = 0xFF, .index = 24})
#define ROM_ERROR_FIELD_MODULE \
  ((bitfield_field32_t){.mask = 0xFFFF, .index = 8})
#define ROM_ERROR_FIELD_STATUS ((bitfield_field32_t){.mask = 0xFF, .index = 0})

/**
 * Helper macro for building up error codes.
 * @param status_ An appropriate general status code from absl_staus.h.
 * @param module_ The module identifier which produces this error.
 * @param error_ The unique error id in that module.  Error ids must not
 *               repeat within a module.
 */
#define ERROR_(error_, module_, status_) \
  ((error_ << 24) | (module_ << 8) | (status_))

// clang-format off
// Use an X-macro to facilitate writing unit tests.
// Note: This list is extend-only and you may not renumber errors after they
//       have been created.  This is required for error-space stability
//       after the ROM is frozen.
#define DEFINE_ERRORS(X) \
  X(kErrorOk, 0x739), \
  X(kErrorUartInvalidArgument,        ERROR_(1, kModuleUart, kInvalidArgument)), \
  X(kErrorUartBadBaudRate,            ERROR_(2, kModuleUart, kInvalidArgument)), \
  X(kErrorHmacInvalidArgument,        ERROR_(1, kModuleHmac, kInvalidArgument)), \
  X(kErrorSigverifyBadEncodedMessage, ERROR_(1, kModuleSigverify, kInvalidArgument)), \
  X(kErrorSigverifyBadExponent,       ERROR_(2, kModuleSigverify, kInvalidArgument)), \
  X(kErrorSigverifyBadKey,            ERROR_(3, kModuleSigverify, kInvalidArgument)), \
  X(kErrorKeymgrInternal,             ERROR_(1, kModuleKeymgr, kInternal)), \
  X(kErrorManifestBadLength,          ERROR_(1, kModuleManifest, kInternal)), \
  X(kErrorManifestBadEntryPoint,      ERROR_(2, kModuleManifest, kInternal)), \
  X(kErrorManifestBadCodeRegion,      ERROR_(3, kModuleManifest, kInternal)), \
  X(kErrorRomextimageInvalidArgument, ERROR_(1, kModuleRomextimage, kInvalidArgument)), \
  X(kErrorRomextimageInternal,        ERROR_(2, kModuleRomextimage, kInternal)), \
  X(kErrorAlertBadIndex,              ERROR_(1, kModuleAlertHandler, kInvalidArgument)), \
  X(kErrorAlertBadClass,              ERROR_(2, kModuleAlertHandler, kInvalidArgument)), \
  X(kErrorAlertBadEnable,             ERROR_(3, kModuleAlertHandler, kInvalidArgument)), \
  X(kErrorAlertBadEscalation,         ERROR_(4, kModuleAlertHandler, kInvalidArgument)), \
  X(kErrorMaskRomBootFailed,          ERROR_(1, kModuleMaskRom, kFailedPrecondition)), \
  /* The high-byte of kErrorInterrupt is modified with the interrupt cause */ \
  X(kErrorInterrupt,                  ERROR_(0, kModuleInterrupt, kUnknown)), \
  X(kErrorEpmpBadCheck,               ERROR_(1, kModuleEpmp, kInternal)), \
  X(kErrorOtpBadAlignment,            ERROR_(1, kModuleOtp, kInvalidArgument)), \
  X(kErrorOtbnInvalidArgument,        ERROR_(1, kModuleOtbn, kInvalidArgument)), \
  X(kErrorOtbnBadOffsetLen,           ERROR_(2, kModuleOtbn, kInvalidArgument)), \
  X(kErrorOtbnBadOffset,              ERROR_(3, kModuleOtbn, kInvalidArgument)), \
  X(kErrorUnknown, 0xFFFFFFFF)
// clang-format on

#define ERROR_ENUM_INIT(name_, value_) name_ = value_

/**
 * Unified set of errors for Mask ROM and ROM_EXT.
 */
typedef enum rom_error {
  DEFINE_ERRORS(ERROR_ENUM_INIT),
} rom_error_t;

/**
 * Evaluate an expression and return if the result is an error.
 *
 * @param expr_ An expression which results in an rom_error_t.
 */
#define RETURN_IF_ERROR(expr_)        \
  do {                                \
    rom_error_t local_error_ = expr_; \
    if (local_error_ != kErrorOk) {   \
      return local_error_;            \
    }                                 \
  } while (0)

#ifdef __cplusplus
}
#endif
#endif  // OPENTITAN_SW_DEVICE_SILICON_CREATOR_LIB_ERROR_H_
