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

public enum UnpackError: Error {
   case notEnoughMemory
   case msgpackLibraryFailedToUnpack(msgpack_unpack_return)

   case failedToDecodeUTF8Bytes(Data)
}

public func unpack(_ message: Data) throws -> AnyHashable {
   return try unpacking(message) { try convertToSwiftValue($0) }
}

public func unpacking<T>(_ message: Data, handleUnpackedObject: (msgpack_object) throws -> T) throws -> T {
   let byteCount = message.count

   var unpacker = msgpack_unpacker()
   guard msgpack_unpacker_init(&unpacker, Int(MSGPACK_UNPACKER_INIT_BUFFER_SIZE)) else {
      throw UnpackError.notEnoughMemory
   }
   defer {
      msgpack_unpacker_destroy(&unpacker)
   }

   guard msgpack_unpacker_reserve_buffer(&unpacker, byteCount) else {
      throw UnpackError.notEnoughMemory
   }
   let buffer = UnsafeMutableRawBufferPointer(start: msgpack_unpacker_buffer(&unpacker), count: byteCount)

   let copiedByteCount = message.copyBytes(to: buffer)
   precondition(copiedByteCount == byteCount)
   msgpack_unpacker_buffer_consumed(&unpacker, copiedByteCount)

   var result = msgpack_unpacked()
   msgpack_unpacked_init(&result)
   defer {
      msgpack_unpacked_destroy(&result)
   }

   let status = msgpack_unpacker_next(&unpacker, &result)
   guard status == MSGPACK_UNPACK_SUCCESS else {
      throw UnpackError.msgpackLibraryFailedToUnpack(status)
   }

   let object = result.data
   return try handleUnpackedObject(object)
}

private func convertToSwiftValue(_ object: msgpack_object) throws -> AnyHashable {
   let objectType = object.type
   switch objectType {
   case MSGPACK_OBJECT_NIL:
      return Nil()

   case MSGPACK_OBJECT_BOOLEAN:
      return object.via.boolean

   case MSGPACK_OBJECT_POSITIVE_INTEGER:
      return object.via.u64

   case MSGPACK_OBJECT_NEGATIVE_INTEGER:
      return object.via.i64

   case MSGPACK_OBJECT_FLOAT32:
      return Float32(object.via.f64)

   case MSGPACK_OBJECT_FLOAT64:
      return object.via.f64

   case MSGPACK_OBJECT_STR:
      let stringObject = object.via.str

      let utf8Bytes = UnsafeRawBufferPointer(start: stringObject.ptr,
                                             count: Int(stringObject.size))

      guard let string = String(bytes: utf8Bytes, encoding: .utf8) else {
         let data = Data(bytes: utf8Bytes.baseAddress!,
                         count: utf8Bytes.count)
         throw UnpackError.failedToDecodeUTF8Bytes(data)
      }
      return string

   case MSGPACK_OBJECT_BIN:
      let binaryObject = object.via.bin

      return Data(bytes: binaryObject.ptr,
                  count: Int(binaryObject.size))

   case MSGPACK_OBJECT_ARRAY:
      let arrayObject = object.via.array

      let elementCount = Int(arrayObject.size)
      let elementObjects = UnsafeBufferPointer(start: arrayObject.ptr, count: elementCount)

      return try [AnyHashable](unsafeUninitializedCapacity: elementCount) { (buffer, initializedCount) in
         for (index, object) in elementObjects.enumerated() {
            let value = try convertToSwiftValue(object)

            buffer.initializeElement(at: index, to: value)
            initializedCount += 1
         }
      }

   case MSGPACK_OBJECT_MAP:
      let mapObject = object.via.map

      let elementCount = Int(mapObject.size)
      let keyValuePairObjects = UnsafeBufferPointer(start: mapObject.ptr, count: elementCount)

      var dictionary = [AnyHashable: AnyHashable](minimumCapacity: elementCount)
      for keyValuePairObject in keyValuePairObjects {
         let key = try convertToSwiftValue(keyValuePairObject.key)
         let value = try convertToSwiftValue(keyValuePairObject.val)

         dictionary[key] = value
      }

      return dictionary

   case MSGPACK_OBJECT_EXT:
      var timestamp = msgpack_timestamp()
      let isTimestamp = withUnsafePointer(to: object) {
         msgpack_object_to_timestamp($0, &timestamp)
      }
      if isTimestamp {
         return timestamp
      }

      let extensionObject = object.via.ext

      let data = Data(bytes: extensionObject.ptr, count: Int(extensionObject.size))

      return MessagePackExtension(typeID: extensionObject.type, data: data)

   default:
      fatalError("Unhandled `msgpack_object_type`: \(objectType)")
   }
}
