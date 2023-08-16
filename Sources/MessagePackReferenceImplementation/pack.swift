// MIT License
//
// Copyright © 2023 Darren Mo.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Cmsgpack
import Foundation

public enum PackError: Error {
   case unsupportedType(Any.Type)

   case msgpackLibraryFailedToPack(Int32)
}

public func pack(_ value: Any) throws -> Data {
   return try packIntoPacker { packer in
      try pack(value, into: &packer)
   }
}

public func packIntoPacker(minimumBufferCapacity: Int? = nil,
                           pack: (inout msgpack_packer) throws -> Void) throws -> Data {
   var buffer = msgpack_sbuffer()
   msgpack_sbuffer_init(&buffer)
   defer {
      msgpack_sbuffer_destroy(&buffer)
   }

   if let minimumBufferCapacity {
      if let newBuffer = realloc(buffer.data, minimumBufferCapacity)?.assumingMemoryBound(to: CChar.self) {
         buffer.data = newBuffer
         buffer.alloc = minimumBufferCapacity
      }
   }

   var packer = msgpack_packer()
   msgpack_packer_init(&packer, &buffer, msgpack_sbuffer_write)

   try pack(&packer)

   let byteCount = buffer.size
   let bytes = msgpack_sbuffer_release(&buffer)!
   return Data(bytesNoCopy: bytes,
               count: byteCount,
               deallocator: .free)
}

private func pack(_ value: Any, into packer: inout msgpack_packer) throws {
   switch ObjectIdentifier(type(of: value)) {
   case ObjectIdentifier(AnyHashable.self):
      let value = value as! AnyHashable
      try pack(value.base, into: &packer)

   case ObjectIdentifier(Nil.self):
      try ensureSuccess(of: msgpack_pack_nil(&packer))

   case ObjectIdentifier(Bool.self):
      if value as! Bool {
         try ensureSuccess(of: msgpack_pack_true(&packer))
      } else {
         try ensureSuccess(of: msgpack_pack_false(&packer))
      }

   case ObjectIdentifier(Int.self):
      try ensureSuccess(of: msgpack_pack_long(&packer, value as! Int))

   case ObjectIdentifier(Int8.self):
      try ensureSuccess(of: msgpack_pack_int8(&packer, value as! Int8))

   case ObjectIdentifier(Int16.self):
      try ensureSuccess(of: msgpack_pack_int16(&packer, value as! Int16))

   case ObjectIdentifier(Int32.self):
      try ensureSuccess(of: msgpack_pack_int32(&packer, value as! Int32))

   case ObjectIdentifier(Int64.self):
      try ensureSuccess(of: msgpack_pack_int64(&packer, value as! Int64))

   case ObjectIdentifier(UInt.self):
      try ensureSuccess(of: msgpack_pack_unsigned_long(&packer, value as! UInt))

   case ObjectIdentifier(UInt8.self):
      try ensureSuccess(of: msgpack_pack_uint8(&packer, value as! UInt8))

   case ObjectIdentifier(UInt16.self):
      try ensureSuccess(of: msgpack_pack_uint16(&packer, value as! UInt16))

   case ObjectIdentifier(UInt32.self):
      try ensureSuccess(of: msgpack_pack_uint32(&packer, value as! UInt32))

   case ObjectIdentifier(UInt64.self):
      try ensureSuccess(of: msgpack_pack_uint64(&packer, value as! UInt64))

   case ObjectIdentifier(Float.self):
      try ensureSuccess(of: msgpack_pack_float(&packer, value as! Float))

   case ObjectIdentifier(Double.self):
      try ensureSuccess(of: msgpack_pack_double(&packer, value as! Double))

   case ObjectIdentifier(String.self):
      var value = value as! String
      try value.withUTF8 { bytes in
         try ensureSuccess(of: msgpack_pack_str_with_body(&packer, bytes.baseAddress, bytes.count))
      }

   case ObjectIdentifier(Data.self):
      let value = value as! Data
      try value.withUnsafeBytes { bytes in
         try ensureSuccess(of: msgpack_pack_bin_with_body(&packer, bytes.baseAddress, bytes.count))
      }

   case ObjectIdentifier(MessagePackExtension.self):
      let `extension` = value as! MessagePackExtension

      let typeID = `extension`.typeID

      try `extension`.data.withUnsafeBytes { bytes in
         try ensureSuccess(of: msgpack_pack_ext_with_body(&packer, bytes.baseAddress, bytes.count, typeID))
      }

   case ObjectIdentifier(msgpack_timestamp.self):
      try withUnsafePointer(to: value as! msgpack_timestamp) {
         try ensureSuccess(of: msgpack_pack_timestamp(&packer, $0))
      }

   default:
      switch value {
      case let array as [Any]:
         try ensureSuccess(of: msgpack_pack_array(&packer, array.count))

         for element in array {
            try pack(element, into: &packer)
         }

      case let dictionary as [AnyHashable: Any]:
         try ensureSuccess(of: msgpack_pack_map(&packer, dictionary.count))

         for (key, value) in dictionary {
            try pack(key.base, into: &packer)
            try pack(value, into: &packer)
         }

      default:
         throw PackError.unsupportedType(type(of: value))
      }
   }
}

private func ensureSuccess(of operation: @autoclosure () -> Int32) throws {
   let status = operation()
   guard status == 0 else {
      throw PackError.msgpackLibraryFailedToPack(status)
   }
}
