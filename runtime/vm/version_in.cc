// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include "vm/version.h"

#include "vm/cpu.h"
#include "vm/flags.h"
#include "vm/os.h"

namespace dart {

DEFINE_FLAG(int,
            use_abi_version,
            Version::CurrentAbiVersion(),
            "ABI version to use. Valid values are "
            "{{OLDEST_SUPPORTED_ABI_VERSION}} to {{ABI_VERSION}}.");

// TODO(iposva): Avoid racy initialization.
static const char* formatted_version = NULL;

const char* Version::String() {
  if (formatted_version == NULL) {
    const char* os = OS::Name();
    const char* arch = CPU::Id();
    formatted_version = OS::SCreate(NULL, "%s on \"%s_%s\"", str_, os, arch);
  }
  return formatted_version;
}

const char* Version::SnapshotString() {
  return snapshot_hash_;
}

const char* Version::CommitString() {
  return commit_;
}

int Version::TargetAbiVersion() {
  int ver = FLAG_use_abi_version;
  if (ver < OldestSupportedAbiVersion() || ver > CurrentAbiVersion()) {
    ver = CurrentAbiVersion();
  }
  return ver;
}

int Version::CurrentAbiVersion() {
  return {{ABI_VERSION}};
}

int Version::OldestSupportedAbiVersion() {
  return {{OLDEST_SUPPORTED_ABI_VERSION}};
}

const char* Version::snapshot_hash_ = "{{SNAPSHOT_HASH}}";
const char* Version::str_ = "{{VERSION_STR}} ({{COMMIT_TIME}})";
const char* Version::commit_ = "{{VERSION_STR}}";

}  // namespace dart
